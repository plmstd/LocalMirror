import Combine
import Foundation

@MainActor
final class BackupOrchestrator: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: BackupRunState = .idle
    @Published private(set) var installation: SyncInstallation?
    @Published private(set) var preflightProgress: PreflightProgress?

    private let engine: SyncEngine
    private let exclusions: [String]

    init(
        engine: SyncEngine,
        exclusions: [String] = BackupExclusions.defaults
    ) {
        self.engine = engine
        self.exclusions = exclusions
        self.installation = try? engine.validateInstallation()
    }

    func refreshInstallation() {
        installation = try? engine.validateInstallation()
    }

    func beginPreflight(for pair: BackupPair) {
        guard !engine.isRunning else { return }
        preflightProgress = PreflightProgress(
            phase: "Scanning source and target…",
            plannedChangeCount: 0,
            currentPath: nil,
            warningCount: 0
        )
        state = .preflighting

        Task {
            do {
                let report = try await buildPreflightReport(for: pair)
                preflightProgress = nil
                state = .review(report)
            } catch {
                let diagnostics = (error as? BackupError)?.diagnostics
                preflightProgress = nil
                state = .failed(
                    RunFailure(
                        pairID: pair.id,
                        startedAt: diagnostics?.startedAt,
                        finishedAt: Date(),
                        reason: error.localizedDescription,
                        warnings: diagnostics.map { RsyncOutputParser.parseWarnings(stderr: $0.stderrLines, exitCode: $0.terminationStatus, wasCancelled: false) } ?? [],
                        logFileURL: nil,
                        log: diagnostics.map { makeFailureLog(for: pair.id, diagnostics: $0) }
                    )
                )
            }
        }
    }

    func dismissReview() {
        guard case .review = state else { return }
        state = .idle
    }

    func startApprovedRun() {
        guard case .review(let report) = state else { return }
        let engine = self.engine
        let exclusions = self.exclusions
        let plannedChangeCount = max(report.plannedChanges.count, report.statistics.totalChangeCount)

        let initialProgress = RunProgress(
            phase: "Starting clone backup…",
            totalPlannedChanges: plannedChangeCount,
            appliedChangeCount: 0,
            currentPath: nil,
            lastAppliedChange: nil,
            warningCount: report.warningMessages.count,
            estimatedTransferBytes: report.statistics.estimatedTransferBytes,
            completedTransferBytes: 0,
            currentPathUpdatedAt: nil,
            lastTransferProgressAt: nil,
            lastOutputAt: Date(),
            currentChangeProgress: 0,
            currentFilePercent: nil,
            currentFileBytesTransferred: nil,
            currentFileEstimatedBytes: nil
        )
        state = .running(initialProgress)

        Task.detached(priority: .userInitiated) { [self, report, engine, exclusions, plannedChangeCount] in
            let startedAt = Date()
            do {
                let completion = try await engine.run(
                    pair: report.pair,
                    plannedChanges: report.plannedChanges,
                    exclusions: exclusions
                ) { [weak self] event in
                    guard let self else { return }
                    let orchestrator = self
                    await MainActor.run {
                        orchestrator.apply(event: event, plannedChangeCount: plannedChangeCount)
                    }
                }

                let finishedAt = completion.log.finishedAt
                let logURL = AppPaths.logsDirectory.appendingPathComponent(completion.log.textLogRelativePath)

                if completion.log.wasCancelled {
                    await MainActor.run {
                        state = .cancelled(
                            RunFailure(
                                pairID: report.pair.id,
                                startedAt: startedAt,
                                finishedAt: finishedAt,
                                reason: "Clone backup cancelled. The target may now be partially synced; the next run must start with a fresh preflight.",
                                warnings: completion.log.warnings,
                                logFileURL: logURL,
                                log: completion.log
                            )
                        )
                    }
                    return
                }

                let combinedWarnings = completion.log.warnings
                let outcome = BackupOutcomeStatus.rsyncOutcome(for: completion.log.exitCode)

                if outcome == .success || outcome == .partial {
                    await MainActor.run {
                        state = .completed(
                            RunResult(
                                outcome: outcome,
                                pairID: report.pair.id,
                                startedAt: startedAt,
                                finishedAt: finishedAt,
                                appliedChangeCount: completion.log.appliedChanges.count,
                                deletionCount: completion.log.appliedChanges.filter { $0.operation == .delete }.count,
                                warnings: combinedWarnings,
                                logFileURL: logURL,
                                log: completion.log,
                                summary: outcome == .partial
                                    ? "Clone backup completed with issues (rsync exit code \(completion.log.exitCode))."
                                    : combinedWarnings.isEmpty
                                    ? "Clone backup completed successfully."
                                    : "Clone backup completed with \(combinedWarnings.count) warning(s)."
                            )
                        )
                    }
                } else {
                    await MainActor.run {
                        state = .failed(
                            RunFailure(
                                pairID: report.pair.id,
                                startedAt: startedAt,
                                finishedAt: finishedAt,
                                reason: "rsync exited with code \(completion.log.exitCode).",
                                warnings: combinedWarnings,
                                logFileURL: logURL,
                                log: completion.log
                            )
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    state = .failed(
                        RunFailure(
                            pairID: report.pair.id,
                            startedAt: startedAt,
                            finishedAt: Date(),
                            reason: error.localizedDescription,
                            warnings: [],
                            logFileURL: nil,
                            log: nil
                        )
                    )
                }
            }
        }
    }

    func requestCancellation() {
        guard engine.isRunning else { return }
        state = .cancelling("Cancellation requested. The target may be partially synced until the process exits.")
        Task {
            await engine.requestCancellation()
        }
    }

    func resetTerminalState() {
        switch state {
        case .completed, .failed, .cancelled:
            state = .idle
        default:
            break
        }
    }

    private func buildPreflightReport(for pair: BackupPair) async throws -> PreflightReport {
        let sourceURL = try BookmarkResolver.resolve(pair.sourceBookmark)
        let targetURL = try BookmarkResolver.resolve(pair.targetBookmark)

        let pathValidation = BackupPathValidator.validate(source: sourceURL, target: targetURL)
        let currentSourceVolume = try VolumeIdentityResolver.resolve(for: sourceURL)
        let currentTargetVolume = try VolumeIdentityResolver.resolve(for: targetURL)
        let currentTargetCapabilities = try VolumeIdentityResolver.resolveTargetCapabilities(for: targetURL)

        var validationMessages = pathValidation.messages
        if !FileManager.default.isReadableFile(atPath: pathValidation.sourceCanonicalPath) {
            validationMessages.append(.init(severity: .blocking, message: "The selected source folder is not readable by LocalMirror."))
        }
        if !FileManager.default.isWritableFile(atPath: pathValidation.targetCanonicalPath) {
            validationMessages.append(.init(severity: .blocking, message: "The selected target folder is not writable by LocalMirror."))
        }
        if currentTargetCapabilities.isReadOnly {
            validationMessages.append(.init(severity: .blocking, message: "The selected target volume is read-only. Choose a writable target before cloning."))
        }

        if pair.targetVolume.uuid != nil, pair.targetVolume.uuid != currentTargetVolume.uuid {
            validationMessages.append(.init(severity: .blocking, message: "The mounted target volume does not match the saved target drive. Reselect the target before cloning."))
        }
        if pair.targetCapabilities.fileSystemType != TargetCapabilities.unknown.fileSystemType,
           pair.targetCapabilities.fileSystemType != currentTargetCapabilities.fileSystemType {
            validationMessages.append(.init(severity: .info, message: "The target file system is now \(currentTargetCapabilities.fileSystemType); it was previously saved as \(pair.targetCapabilities.fileSystemType)."))
        }

        let preflight = try await engine.preflight(
            pair: BackupPair(
                id: pair.id,
                sourceBookmark: pair.sourceBookmark,
                targetBookmark: pair.targetBookmark,
                sourceCanonicalPath: pathValidation.sourceCanonicalPath,
                targetCanonicalPath: pathValidation.targetCanonicalPath,
                sourceVolume: pair.sourceVolume,
                targetVolume: pair.targetVolume,
                targetCapabilities: currentTargetCapabilities,
                createdAt: pair.createdAt,
                lastRun: pair.lastRun
            ),
            exclusions: exclusions
        ) { [weak self] event in
            guard let self else { return }
            let orchestrator = self
            await MainActor.run {
                orchestrator.apply(preflightEvent: event)
            }
        }

        let availableFreeBytes = VolumeIdentityResolver.availableCapacity(for: targetURL)
        if let availableFreeBytes, preflight.statistics.estimatedTransferBytes > 0, availableFreeBytes < preflight.statistics.estimatedTransferBytes {
            validationMessages.append(.init(severity: .blocking, message: "The target volume does not have enough free space for the planned transfer."))
        } else if availableFreeBytes == nil {
            validationMessages.append(.init(severity: .warning, message: "LocalMirror could not determine the target volume’s available free space."))
        }

        let sourceAppearsEmpty = preflight.statistics.totalSourceItems <= 1 && preflight.statistics.deletionCount > 0
        if sourceAppearsEmpty {
            validationMessages.append(.init(severity: .warning, message: "The source appears empty while the target has pending deletions. Double-check the selected source path."))
        }

        let warningLines = RsyncOutputParser.parseWarnings(stderr: preflight.stderrLines, exitCode: 0, wasCancelled: false)
        let deletionRatio = preflight.statistics.totalSourceItems > 0
            ? Double(preflight.statistics.deletionCount) / Double(preflight.statistics.totalSourceItems)
            : (preflight.statistics.deletionCount > 0 ? 1 : 0)

        let requiresTypedConfirmation =
            preflight.statistics.deletionCount > 0 &&
            (
                pair.lastRun == nil ||
                sourceAppearsEmpty ||
                (preflight.statistics.deletionCount >= 5 && deletionRatio >= 0.10)
            )

        let riskLevel = determineRiskLevel(
            validationMessages: validationMessages,
            warnings: warningLines,
            deletionCount: preflight.statistics.deletionCount,
            requiresTypedConfirmation: requiresTypedConfirmation
        )

        return PreflightReport(
            pair: BackupPair(
                id: pair.id,
                sourceBookmark: pair.sourceBookmark,
                targetBookmark: pair.targetBookmark,
                sourceCanonicalPath: pathValidation.sourceCanonicalPath,
                targetCanonicalPath: pathValidation.targetCanonicalPath,
                sourceVolume: currentSourceVolume,
                targetVolume: currentTargetVolume,
                targetCapabilities: currentTargetCapabilities,
                createdAt: pair.createdAt,
                lastRun: pair.lastRun
            ),
            currentSourceVolume: currentSourceVolume,
            currentTargetVolume: currentTargetVolume,
            currentTargetCapabilities: currentTargetCapabilities,
            statistics: preflight.statistics,
            plannedChanges: preflight.plannedChanges,
            exclusions: exclusions,
            availableFreeBytes: availableFreeBytes,
            validationMessages: validationMessages,
            warnings: warningLines,
            riskLevel: riskLevel,
            requiresTypedConfirmation: requiresTypedConfirmation,
            confirmationToken: confirmationToken(for: targetURL, targetVolume: currentTargetVolume),
            isFirstRun: pair.lastRun == nil
        )
    }

    private func apply(event: SyncRunEvent, plannedChangeCount: Int) {
        let now = Date()
        switch event {
        case .started:
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            state = .running(
                RunProgress(
                    phase: "Preparing clone run…",
                    totalPlannedChanges: plannedChangeCount,
                    appliedChangeCount: 0,
                    currentPath: nil,
                    lastAppliedChange: nil,
                    warningCount: 0,
                    estimatedTransferBytes: current.estimatedTransferBytes,
                    completedTransferBytes: current.completedTransferBytes,
                    currentPathUpdatedAt: nil,
                    lastTransferProgressAt: current.lastTransferProgressAt,
                    lastOutputAt: now,
                    currentChangeProgress: 0,
                    currentFilePercent: nil,
                    currentFileBytesTransferred: nil,
                    currentFileEstimatedBytes: nil
                )
            )
        case .changeDetected(let change):
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            state = .running(
                RunProgress(
                    phase: "Cloning files…",
                    totalPlannedChanges: current.totalPlannedChanges,
                    appliedChangeCount: current.appliedChangeCount,
                    currentPath: change.path,
                    lastAppliedChange: current.lastAppliedChange,
                    warningCount: current.warningCount,
                    estimatedTransferBytes: current.estimatedTransferBytes,
                    completedTransferBytes: current.completedTransferBytes,
                    currentPathUpdatedAt: now,
                    lastTransferProgressAt: current.lastTransferProgressAt,
                    lastOutputAt: now,
                    currentChangeProgress: 0,
                    currentFilePercent: nil,
                    currentFileBytesTransferred: nil,
                    currentFileEstimatedBytes: nil
                )
            )
        case .appliedChange(let change):
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            let pathUpdatedAt = change.operation == .create || change.operation == .update
                ? current.currentPathUpdatedAt
                : now
            state = .running(
                RunProgress(
                    phase: "Cloning files…",
                    totalPlannedChanges: current.totalPlannedChanges,
                    appliedChangeCount: current.appliedChangeCount + 1,
                    currentPath: change.path,
                    lastAppliedChange: change,
                    warningCount: current.warningCount,
                    estimatedTransferBytes: current.estimatedTransferBytes,
                    completedTransferBytes: current.completedTransferBytes,
                    currentPathUpdatedAt: pathUpdatedAt,
                    lastTransferProgressAt: current.lastTransferProgressAt,
                    lastOutputAt: now,
                    currentChangeProgress: 0,
                    currentFilePercent: nil,
                    currentFileBytesTransferred: nil,
                    currentFileEstimatedBytes: nil
                )
            )
        case .transferProgress(let progress):
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            let completedTransferBytes = progress.isCompleted
                ? current.completedTransferBytes + progress.bytesTransferred
                : current.completedTransferBytes
            state = .running(
                RunProgress(
                    phase: "Cloning files…",
                    totalPlannedChanges: current.totalPlannedChanges,
                    appliedChangeCount: current.appliedChangeCount,
                    currentPath: progress.path,
                    lastAppliedChange: current.lastAppliedChange,
                    warningCount: current.warningCount,
                    estimatedTransferBytes: current.estimatedTransferBytes,
                    completedTransferBytes: completedTransferBytes,
                    currentPathUpdatedAt: current.currentPathUpdatedAt,
                    lastTransferProgressAt: now,
                    lastOutputAt: now,
                    currentChangeProgress: progress.isCompleted ? 0 : progress.percentComplete,
                    currentFilePercent: progress.isCompleted ? nil : progress.percentComplete,
                    currentFileBytesTransferred: progress.isCompleted ? nil : progress.bytesTransferred,
                    currentFileEstimatedBytes: progress.isCompleted ? nil : progress.estimatedFileBytes
                )
            )
        case .warning:
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            state = .running(
                RunProgress(
                    phase: "Cloning files…",
                    totalPlannedChanges: current.totalPlannedChanges,
                    appliedChangeCount: current.appliedChangeCount,
                    currentPath: current.currentPath,
                    lastAppliedChange: current.lastAppliedChange,
                    warningCount: current.warningCount + 1,
                    estimatedTransferBytes: current.estimatedTransferBytes,
                    completedTransferBytes: current.completedTransferBytes,
                    currentPathUpdatedAt: current.currentPathUpdatedAt,
                    lastTransferProgressAt: current.lastTransferProgressAt,
                    lastOutputAt: now,
                    currentChangeProgress: current.currentChangeProgress,
                    currentFilePercent: current.currentFilePercent,
                    currentFileBytesTransferred: current.currentFileBytesTransferred,
                    currentFileEstimatedBytes: current.currentFileEstimatedBytes
                )
            )
        case .info(let message):
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            state = .running(
                RunProgress(
                    phase: message,
                    totalPlannedChanges: current.totalPlannedChanges,
                    appliedChangeCount: current.appliedChangeCount,
                    currentPath: current.currentPath,
                    lastAppliedChange: current.lastAppliedChange,
                    warningCount: current.warningCount,
                    estimatedTransferBytes: current.estimatedTransferBytes,
                    completedTransferBytes: current.completedTransferBytes,
                    currentPathUpdatedAt: current.currentPathUpdatedAt,
                    lastTransferProgressAt: current.lastTransferProgressAt,
                    lastOutputAt: now,
                    currentChangeProgress: current.currentChangeProgress,
                    currentFilePercent: current.currentFilePercent,
                    currentFileBytesTransferred: current.currentFileBytesTransferred,
                    currentFileEstimatedBytes: current.currentFileEstimatedBytes
                )
            )
        }
    }

    private func apply(preflightEvent event: SyncPreflightEvent) {
        let current = preflightProgress ?? PreflightProgress(
            phase: "Scanning source and target…",
            plannedChangeCount: 0,
            currentPath: nil,
            warningCount: 0
        )

        switch event {
        case .started:
            preflightProgress = PreflightProgress(
                phase: "Scanning source and target…",
                plannedChangeCount: current.plannedChangeCount,
                currentPath: current.currentPath,
                warningCount: current.warningCount
            )
        case .plannedChange(let change):
            preflightProgress = PreflightProgress(
                phase: "Building preflight review…",
                plannedChangeCount: current.plannedChangeCount + 1,
                currentPath: change.path,
                warningCount: current.warningCount
            )
        case .warning:
            preflightProgress = PreflightProgress(
                phase: current.phase,
                plannedChangeCount: current.plannedChangeCount,
                currentPath: current.currentPath,
                warningCount: current.warningCount + 1
            )
        case .info(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            preflightProgress = PreflightProgress(
                phase: trimmed.isEmpty ? current.phase : trimmed,
                plannedChangeCount: current.plannedChangeCount,
                currentPath: current.currentPath,
                warningCount: current.warningCount
            )
        }
    }

    private func currentProgress(plannedChangeCount: Int) -> RunProgress {
        if case .running(let progress) = state {
            return progress
        }
        return RunProgress(
            phase: "Preparing clone run…",
            totalPlannedChanges: plannedChangeCount,
            appliedChangeCount: 0,
            currentPath: nil,
            lastAppliedChange: nil,
            warningCount: 0,
            estimatedTransferBytes: 0,
            completedTransferBytes: 0,
            currentPathUpdatedAt: nil,
            lastTransferProgressAt: nil,
            lastOutputAt: nil,
            currentChangeProgress: 0,
            currentFilePercent: nil,
            currentFileBytesTransferred: nil,
            currentFileEstimatedBytes: nil
        )
    }

    private func determineRiskLevel(validationMessages: [ValidationMessage], warnings: [String], deletionCount: Int, requiresTypedConfirmation: Bool) -> RiskLevel {
        if validationMessages.contains(where: { $0.severity == .blocking }) {
            return .critical
        }
        if requiresTypedConfirmation {
            return .high
        }
        if deletionCount > 0 || !warnings.isEmpty {
            return .medium
        }
        return .low
    }

    private func confirmationToken(for targetURL: URL, targetVolume: VolumeIdentity) -> String {
        let folderName = targetURL.lastPathComponent
        if !targetVolume.displayName.isEmpty {
            return targetVolume.displayName
        }
        return folderName.isEmpty ? targetURL.path : folderName
    }

    private func makeFailureLog(for pairID: UUID, diagnostics: CommandDiagnostics) -> RunLog {
        let logID = UUID()
        let commandLine = ([diagnostics.binaryPath] + diagnostics.arguments)
            .map(quotedArgument(_:))
            .joined(separator: " ")
        let syntheticStdout = [
            "[LocalMirror] Command phase: \(diagnostics.phase)",
            "[LocalMirror] Termination: \(diagnostics.terminationReason.rawValue) \(diagnostics.terminationStatus)",
            "[LocalMirror] Command: \(commandLine)",
            ""
        ] + diagnostics.stdoutLines

        return RunLog(
            id: logID,
            pairID: pairID,
            startedAt: diagnostics.startedAt,
            finishedAt: diagnostics.finishedAt,
            exitCode: diagnostics.terminationStatus,
            wasCancelled: false,
            stdoutLines: syntheticStdout,
            stderrLines: diagnostics.stderrLines,
            warnings: RsyncOutputParser.parseWarnings(stderr: diagnostics.stderrLines, exitCode: diagnostics.terminationStatus, wasCancelled: false),
            appliedChanges: [],
            plannedChanges: RsyncOutputParser.parseChanges(from: diagnostics.stdoutLines),
            textLogRelativePath: "\(logID.uuidString).log"
        )
    }

    private func quotedArgument(_ argument: String) -> String {
        if argument.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            return argument
        }
        return "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
