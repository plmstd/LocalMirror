import Combine
import Foundation

@MainActor
final class BackupOrchestrator: ObservableObject {
    @Published private(set) var state: BackupRunState = .idle
    @Published private(set) var installation: SyncInstallation?

    private let engine: SyncEngine
    private let exclusions: [String]

    init(engine: SyncEngine, exclusions: [String] = BackupExclusions.defaults) {
        self.engine = engine
        self.exclusions = exclusions
        self.installation = try? engine.validateInstallation()
    }

    func refreshInstallation() {
        installation = try? engine.validateInstallation()
    }

    func beginPreflight(for pair: BackupPair) {
        guard !engine.isRunning else { return }
        state = .preflighting

        Task {
            do {
                let report = try await buildPreflightReport(for: pair)
                state = .review(report)
            } catch {
                let diagnostics = (error as? BackupError)?.diagnostics
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

        let initialProgress = RunProgress(
            phase: "Starting mirror backup…",
            totalPlannedChanges: max(report.plannedChanges.count, report.statistics.totalChangeCount),
            appliedChangeCount: 0,
            currentPath: nil,
            lastAppliedChange: nil,
            warningCount: report.warningMessages.count
        )
        state = .running(initialProgress)

        Task {
            let startedAt = Date()
            do {
                let completion = try await engine.run(
                    pair: report.pair,
                    plannedChanges: report.plannedChanges,
                    exclusions: exclusions
                ) { [weak self] event in
                    Task { @MainActor in
                        self?.apply(event: event, plannedChangeCount: max(report.plannedChanges.count, report.statistics.totalChangeCount))
                    }
                }

                let finishedAt = completion.log.finishedAt
                let logURL = AppPaths.logsDirectory.appendingPathComponent(completion.log.textLogRelativePath)

                if completion.log.wasCancelled {
                    state = .cancelled(
                        RunFailure(
                            pairID: report.pair.id,
                            startedAt: startedAt,
                            finishedAt: finishedAt,
                            reason: "Mirror backup cancelled. The target may now be partially synced; the next run must start with a fresh preflight.",
                            warnings: completion.log.warnings,
                            logFileURL: logURL,
                            log: completion.log
                        )
                    )
                    return
                }

                if completion.log.exitCode == 0 {
                    state = .completed(
                        RunResult(
                            pairID: report.pair.id,
                            startedAt: startedAt,
                            finishedAt: finishedAt,
                            appliedChangeCount: completion.log.appliedChanges.count,
                            deletionCount: completion.log.appliedChanges.filter { $0.operation == .delete }.count,
                            warnings: completion.log.warnings,
                            logFileURL: logURL,
                            log: completion.log,
                            summary: completion.log.warnings.isEmpty
                                ? "Mirror backup completed successfully."
                                : "Mirror backup completed with \(completion.log.warnings.count) warning(s)."
                        )
                    )
                } else {
                    state = .failed(
                        RunFailure(
                            pairID: report.pair.id,
                            startedAt: startedAt,
                            finishedAt: finishedAt,
                            reason: "rsync exited with code \(completion.log.exitCode).",
                            warnings: completion.log.warnings,
                            logFileURL: logURL,
                            log: completion.log
                        )
                    )
                }
            } catch {
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

        var validationMessages = pathValidation.messages
        if !FileManager.default.isReadableFile(atPath: pathValidation.sourceCanonicalPath) {
            validationMessages.append(.init(severity: .blocking, message: "The selected source folder is not readable by YeOldBackup."))
        }
        if !FileManager.default.isWritableFile(atPath: pathValidation.targetCanonicalPath) {
            validationMessages.append(.init(severity: .blocking, message: "The selected target folder is not writable by YeOldBackup."))
        }

        if pair.targetVolume.uuid != nil, pair.targetVolume.uuid != currentTargetVolume.uuid {
            validationMessages.append(.init(severity: .blocking, message: "The mounted target volume does not match the saved target drive. Reselect the target before mirroring."))
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
                createdAt: pair.createdAt,
                lastRun: pair.lastRun
            ),
            exclusions: exclusions
        )

        let availableFreeBytes = VolumeIdentityResolver.availableCapacity(for: targetURL)
        if let availableFreeBytes, preflight.statistics.estimatedTransferBytes > 0, availableFreeBytes < preflight.statistics.estimatedTransferBytes {
            validationMessages.append(.init(severity: .blocking, message: "The target volume does not have enough free space for the planned transfer."))
        } else if availableFreeBytes == nil {
            validationMessages.append(.init(severity: .warning, message: "YeOldBackup could not determine the target volume’s available free space."))
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
                createdAt: pair.createdAt,
                lastRun: pair.lastRun
            ),
            currentSourceVolume: currentSourceVolume,
            currentTargetVolume: currentTargetVolume,
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
        switch event {
        case .started:
            state = .running(
                RunProgress(
                    phase: "Preparing mirror run…",
                    totalPlannedChanges: plannedChangeCount,
                    appliedChangeCount: 0,
                    currentPath: nil,
                    lastAppliedChange: nil,
                    warningCount: 0
                )
            )
        case .appliedChange(let change):
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            state = .running(
                RunProgress(
                    phase: "Mirroring files…",
                    totalPlannedChanges: current.totalPlannedChanges,
                    appliedChangeCount: current.appliedChangeCount + 1,
                    currentPath: change.path,
                    lastAppliedChange: change,
                    warningCount: current.warningCount
                )
            )
        case .warning:
            let current = currentProgress(plannedChangeCount: plannedChangeCount)
            state = .running(
                RunProgress(
                    phase: "Mirroring files…",
                    totalPlannedChanges: current.totalPlannedChanges,
                    appliedChangeCount: current.appliedChangeCount,
                    currentPath: current.currentPath,
                    lastAppliedChange: current.lastAppliedChange,
                    warningCount: current.warningCount + 1
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
                    warningCount: current.warningCount
                )
            )
        }
    }

    private func currentProgress(plannedChangeCount: Int) -> RunProgress {
        if case .running(let progress) = state {
            return progress
        }
        return RunProgress(
            phase: "Preparing mirror run…",
            totalPlannedChanges: plannedChangeCount,
            appliedChangeCount: 0,
            currentPath: nil,
            lastAppliedChange: nil,
            warningCount: 0
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
            "[YeOldBackup] Command phase: \(diagnostics.phase)",
            "[YeOldBackup] Termination: \(diagnostics.terminationReason.rawValue) \(diagnostics.terminationStatus)",
            "[YeOldBackup] Command: \(commandLine)",
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
