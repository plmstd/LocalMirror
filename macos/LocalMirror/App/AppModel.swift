import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum SelectionKind {
        case source
        case target
    }

    @Published var sourcePath: String = ""
    @Published var targetPath: String = ""
    @Published var pairs: [BackupPair] = []
    @Published var runHistory: [RunHistoryItem] = []
    @Published var selectedPairID: UUID?
    @Published var runState: BackupRunState = .idle
    @Published var installation: SyncInstallation?
    @Published var preflightProgress: PreflightProgress?
    @Published var statusNote: String?

    private let store: BackupStore
    private let orchestrator: BackupOrchestrator
    private var settings = AppSettings.current
    private var sourceURL: URL?
    private var targetURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init(store: BackupStore = BackupStore(), engine: SyncEngine = RsyncSyncEngine()) {
        self.store = store
        self.orchestrator = BackupOrchestrator(engine: engine)
        bindOrchestrator()
    }

    var reviewReport: PreflightReport? {
        if case .review(let report) = runState {
            return report
        }
        return nil
    }

    var canStartBackup: Bool {
        sourceURL != nil &&
        targetURL != nil &&
        !isBusy
    }

    var canOpenLatestLog: Bool {
        latestLogURL != nil
    }

    var canRevealLogsDirectory: Bool {
        FileManager.default.fileExists(atPath: AppPaths.logsDirectory.path)
    }

    var selectedTargetCapabilities: TargetCapabilities? {
        if let targetURL {
            return try? VolumeIdentityResolver.resolveTargetCapabilities(for: targetURL)
        }
        return selectedPair?.targetCapabilities
    }

    var canStopBackup: Bool {
        switch runState {
        case .running:
            return true
        case .cancelling:
            return false
        default:
            return false
        }
    }

    var isBusy: Bool {
        switch runState {
        case .preflighting, .running, .cancelling:
            return true
        default:
            return false
        }
    }

    func load() {
        do {
            let state = try store.loadState()
            settings = state.settings
            pairs = state.pairs.sorted(by: sortPairs)
            runHistory = state.runHistory.sorted { $0.finishedAt > $1.finishedAt }
            installation = orchestrator.installation

            if let lastSelectedPairID = settings.lastSelectedPairID,
               let pair = pairs.first(where: { $0.id == lastSelectedPairID }) {
                load(pair: pair)
            }

            if let installation, installation.kind != .systemProvided {
                statusNote = "LocalMirror is using a custom rsync binary at \(installation.binaryURL.path)."
            }
        } catch {
            runState = .failed(
                RunFailure(
                    pairID: nil,
                    startedAt: nil,
                    finishedAt: Date(),
                    reason: error.localizedDescription,
                    warnings: [],
                    logFileURL: nil,
                    log: nil
                )
            )
        }
    }

    func selectDirectory(_ kind: SelectionKind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = kind == .target
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.title = kind == .source ? "Select Source Folder" : "Select Target Folder"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.applySelection(url, kind: kind)
            }
        }
    }

    func beginCloneBackup() {
        guard let sourceURL, let targetURL else {
            runState = .failed(
                RunFailure(
                    pairID: nil,
                    startedAt: nil,
                    finishedAt: Date(),
                    reason: "Select both a source and a target folder before starting a clone backup.",
                    warnings: [],
                    logFileURL: nil,
                    log: nil
                )
            )
            return
        }

        do {
            let pair = try makeActivePair(sourceURL: sourceURL, targetURL: targetURL)
            upsertPair(pair)
            settings.lastSelectedPairID = pair.id
            try persistState()
            orchestrator.beginPreflight(for: pair)
        } catch {
            runState = .failed(
                RunFailure(
                    pairID: nil,
                    startedAt: nil,
                    finishedAt: Date(),
                    reason: error.localizedDescription,
                    warnings: [],
                    logFileURL: nil,
                    log: nil
                )
            )
        }
    }

    func approvePreflight(typedConfirmation: String) {
        guard let report = reviewReport else { return }
        if report.requiresTypedConfirmation, typedConfirmation != report.confirmationToken {
            statusNote = "Typed confirmation must match \(report.confirmationToken ?? "the target name") exactly."
            return
        }
        statusNote = nil
        orchestrator.startApprovedRun()
    }

    func cancelReview() {
        statusNote = nil
        orchestrator.dismissReview()
    }

    func stopCloneBackup() {
        orchestrator.requestCancellation()
    }

    func openSystemSettings() {
        SystemSettingsNavigator.openFullDiskAccess()
    }

    func openLatestLog() {
        guard let url = latestLogURL else {
            statusNote = "No run log is available for the current state."
            return
        }
        statusNote = nil
        NSWorkspace.shared.open(url)
    }

    func revealLogsInFinder() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.logsDirectory, withIntermediateDirectories: true, attributes: nil)
            statusNote = nil
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logsDirectory])
        } catch {
            statusNote = "LocalMirror could not reveal the logs directory: \(error.localizedDescription)"
        }
    }

    func copySupportDiagnostics() {
        let diagnostics = makeSupportDiagnostics()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(diagnostics, forType: .string)
        statusNote = success ? "Support diagnostics copied to the clipboard." : "LocalMirror could not copy support diagnostics to the clipboard."
    }

    func deleteSelectedPairs(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pairs.removeAll { ids.contains($0.id) }
        runHistory.removeAll { ids.contains($0.pairID) }
        if let selectedPairID, ids.contains(selectedPairID) {
            clearSelection()
        }
        try? persistState()
    }

    func loadSelectedPair(id: UUID?) {
        guard let id, let pair = pairs.first(where: { $0.id == id }) else { return }
        load(pair: pair)
    }

    private func bindOrchestrator() {
        orchestrator.$state
            .sink { [weak self] state in
                self?.runState = state
                self?.handle(runState: state)
            }
            .store(in: &cancellables)

        orchestrator.$installation
            .sink { [weak self] installation in
                self?.installation = installation
            }
            .store(in: &cancellables)

        orchestrator.$preflightProgress
            .sink { [weak self] progress in
                self?.preflightProgress = progress
            }
            .store(in: &cancellables)
    }

    private func applySelection(_ url: URL, kind: SelectionKind) {
        switch kind {
        case .source:
            sourceURL = url
            sourcePath = url.path
        case .target:
            targetURL = url
            targetPath = url.path
        }
        selectedPairID = nil
        settings.lastSelectedPairID = nil
        statusNote = nil
        orchestrator.resetTerminalState()
    }

    private func load(pair: BackupPair) {
        do {
            let resolvedSource = try BookmarkResolver.resolve(pair.sourceBookmark)
            let resolvedTarget = try BookmarkResolver.resolve(pair.targetBookmark)
            sourceURL = resolvedSource
            targetURL = resolvedTarget
            sourcePath = resolvedSource.path
            targetPath = resolvedTarget.path
            selectedPairID = pair.id
            settings.lastSelectedPairID = pair.id
            try? persistState()
            statusNote = nil
        } catch {
            statusNote = "The selected backup pair is no longer available. Reselect the source and target."
        }
    }

    private func clearSelection() {
        selectedPairID = nil
        settings.lastSelectedPairID = nil
        sourceURL = nil
        targetURL = nil
        sourcePath = ""
        targetPath = ""
    }

    private func makeActivePair(sourceURL: URL, targetURL: URL) throws -> BackupPair {
        let sourceBookmark = try BookmarkResolver.makeBookmark(for: sourceURL)
        let targetBookmark = try BookmarkResolver.makeBookmark(for: targetURL)
        let sourceCanonical = BackupPathValidator.canonicalPath(for: sourceURL)
        let targetCanonical = BackupPathValidator.canonicalPath(for: targetURL)
        let currentTargetCapabilities = try VolumeIdentityResolver.resolveTargetCapabilities(for: targetURL)

        if let selectedPairID,
           let existing = pairs.first(where: { $0.id == selectedPairID }) {
            return BackupPair(
                id: existing.id,
                sourceBookmark: sourceBookmark,
                targetBookmark: targetBookmark,
                sourceCanonicalPath: sourceCanonical,
                targetCanonicalPath: targetCanonical,
                sourceVolume: existing.sourceVolume,
                targetVolume: existing.targetVolume,
                targetCapabilities: currentTargetCapabilities,
                createdAt: existing.createdAt,
                lastRun: existing.lastRun
            )
        }

        if let existing = pairs.first(where: { $0.sourceCanonicalPath == sourceCanonical && $0.targetCanonicalPath == targetCanonical }) {
            return BackupPair(
                id: existing.id,
                sourceBookmark: sourceBookmark,
                targetBookmark: targetBookmark,
                sourceCanonicalPath: sourceCanonical,
                targetCanonicalPath: targetCanonical,
                sourceVolume: existing.sourceVolume,
                targetVolume: existing.targetVolume,
                targetCapabilities: currentTargetCapabilities,
                createdAt: existing.createdAt,
                lastRun: existing.lastRun
            )
        }

        return BackupPair(
            id: UUID(),
            sourceBookmark: sourceBookmark,
            targetBookmark: targetBookmark,
            sourceCanonicalPath: sourceCanonical,
            targetCanonicalPath: targetCanonical,
            sourceVolume: try VolumeIdentityResolver.resolve(for: sourceURL),
            targetVolume: try VolumeIdentityResolver.resolve(for: targetURL),
            targetCapabilities: currentTargetCapabilities,
            createdAt: Date(),
            lastRun: nil
        )
    }

    private func upsertPair(_ pair: BackupPair) {
        if let index = pairs.firstIndex(where: { $0.id == pair.id }) {
            pairs[index] = pair
        } else {
            pairs.append(pair)
        }
        pairs.sort(by: sortPairs)
        selectedPairID = pair.id
    }

    private func handle(runState: BackupRunState) {
        switch runState {
        case .completed(let result):
            persistTerminalState(outcome: result.outcome, log: result.log, pairID: result.pairID, summary: result.summary)
        case .failed(let failure):
            if let log = failure.log, let pairID = failure.pairID {
                persistTerminalState(outcome: .failure, log: log, pairID: pairID, summary: failure.reason)
            }
        case .cancelled(let failure):
            if let log = failure.log, let pairID = failure.pairID {
                persistTerminalState(outcome: .cancelled, log: log, pairID: pairID, summary: failure.reason)
            }
        default:
            break
        }
    }

    private func persistTerminalState(outcome: BackupOutcomeStatus, log: RunLog, pairID: UUID, summary: String) {
        do {
            let textURL = try store.storeRunLog(log)
            let historyItem = RunHistoryItem(
                id: log.id,
                pairID: pairID,
                startedAt: log.startedAt,
                finishedAt: log.finishedAt,
                outcome: outcome,
                appliedChangeCount: log.appliedChanges.count,
                deletionCount: log.appliedChanges.filter { $0.operation == .delete }.count,
                warningCount: log.warnings.count,
                summary: summary,
                textLogRelativePath: log.textLogRelativePath
            )

            runHistory.removeAll { $0.id == historyItem.id }
            runHistory.insert(historyItem, at: 0)
            runHistory = try store.pruneRunHistory(runHistory)

            if let index = pairs.firstIndex(where: { $0.id == pairID }) {
                pairs[index].sourceVolume = try VolumeIdentityResolver.resolve(for: BookmarkResolver.resolve(pairs[index].sourceBookmark))
                pairs[index].targetVolume = try VolumeIdentityResolver.resolve(for: BookmarkResolver.resolve(pairs[index].targetBookmark))
                pairs[index].targetCapabilities = try VolumeIdentityResolver.resolveTargetCapabilities(for: BookmarkResolver.resolve(pairs[index].targetBookmark))
                pairs[index].lastRun = BackupPairLastRun(date: historyItem.finishedAt, status: outcome, warningCount: historyItem.warningCount, logID: historyItem.id)
                pairs.sort(by: sortPairs)
            }

            try persistState()

            switch runState {
            case .completed(let result):
                runState = .completed(
                    RunResult(
                        outcome: result.outcome,
                        pairID: result.pairID,
                        startedAt: result.startedAt,
                        finishedAt: result.finishedAt,
                        appliedChangeCount: result.appliedChangeCount,
                        deletionCount: result.deletionCount,
                        warnings: result.warnings,
                        logFileURL: textURL,
                        log: result.log,
                        summary: result.summary
                    )
                )
            case .failed(let failure):
                runState = .failed(
                    RunFailure(
                        pairID: failure.pairID,
                        startedAt: failure.startedAt,
                        finishedAt: failure.finishedAt,
                        reason: failure.reason,
                        warnings: failure.warnings,
                        logFileURL: textURL,
                        log: failure.log
                    )
                )
            case .cancelled(let failure):
                runState = .cancelled(
                    RunFailure(
                        pairID: failure.pairID,
                        startedAt: failure.startedAt,
                        finishedAt: failure.finishedAt,
                        reason: failure.reason,
                        warnings: failure.warnings,
                        logFileURL: textURL,
                        log: failure.log
                    )
                )
            default:
                break
            }
        } catch {
            statusNote = "LocalMirror could not persist the latest run log: \(error.localizedDescription)"
        }
    }

    private func persistState() throws {
        try store.persist(
            state: PersistedState(
                settings: settings,
                pairs: pairs.sorted(by: sortPairs),
                runHistory: runHistory.sorted { $0.finishedAt > $1.finishedAt }
            )
        )
    }

    private func sortPairs(lhs: BackupPair, rhs: BackupPair) -> Bool {
        let lhsDate = lhs.lastRun?.date ?? lhs.createdAt
        let rhsDate = rhs.lastRun?.date ?? rhs.createdAt
        return lhsDate > rhsDate
    }

    private var latestLogURL: URL? {
        switch runState {
        case .completed(let result):
            return result.logFileURL
        case .failed(let failure):
            return failure.logFileURL
        case .cancelled(let failure):
            return failure.logFileURL
        default:
            if let pair = selectedPairID.flatMap({ id in pairs.first(where: { $0.id == id }) }),
               let lastRun = pair.lastRun,
               let history = runHistory.first(where: { $0.id == lastRun.logID }) {
                return AppPaths.logsDirectory.appendingPathComponent(history.textLogRelativePath)
            }
            return nil
        }
    }

    private var selectedPair: BackupPair? {
        guard let selectedPairID else { return nil }
        return pairs.first(where: { $0.id == selectedPairID })
    }

    private func makeSupportDiagnostics() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let targetCapabilities = selectedTargetCapabilities
        let runStateDescription: String
        switch runState {
        case .idle:
            runStateDescription = "idle"
        case .preflighting:
            runStateDescription = "preflighting"
        case .review:
            runStateDescription = "review"
        case .running:
            runStateDescription = "running"
        case .cancelling:
            runStateDescription = "cancelling"
        case .completed:
            runStateDescription = "completed"
        case .failed:
            runStateDescription = "failed"
        case .cancelled:
            runStateDescription = "cancelled"
        }

        let lines = [
            "LocalMirror Diagnostics",
            "App Version: \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "rsync Path: \(installation?.binaryURL.path ?? "Unavailable")",
            "rsync Version: \(installation?.versionDescription ?? "Unavailable")",
            "Source Path: \(sourcePath.isEmpty ? "None" : sourcePath)",
            "Target Path: \(targetPath.isEmpty ? "None" : targetPath)",
            "Target File System: \(targetCapabilities?.fileSystemType ?? "Unknown")",
            "Target Snapshot Readiness: \(targetCapabilities?.historyModeLabel ?? "Unknown")",
            "Logs Directory: \(AppPaths.logsDirectory.path)",
            "Run State: \(runStateDescription)"
        ]
        return lines.joined(separator: "\n")
    }
}
