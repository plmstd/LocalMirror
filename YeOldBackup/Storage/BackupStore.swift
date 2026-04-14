import Foundation

final class BackupStore {
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maxStoredRunLogs: Int
    private let baseDirectory: URL

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        baseDirectory: URL = AppPaths.applicationSupportDirectory,
        maxStoredRunLogs: Int = 100
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.baseDirectory = baseDirectory
        self.maxStoredRunLogs = maxStoredRunLogs
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    func loadState() throws -> PersistedState {
        try ensureDirectories()

        if !fileManager.fileExists(atPath: settingsURL.path),
           !fileManager.fileExists(atPath: pairsURL.path),
           hasLegacyDefaults {
            let migrated = try migrateLegacyState()
            try persist(state: migrated)
            return migrated
        }

        let settings = try loadOptional(AppSettings.self, from: settingsURL) ?? .current
        let pairs = try loadOptional([BackupPair].self, from: pairsURL) ?? []
        let runHistory = try loadOptional([RunHistoryItem].self, from: runHistoryURL) ?? []
        return PersistedState(settings: settings, pairs: pairs, runHistory: runHistory)
    }

    func persist(state: PersistedState) throws {
        try ensureDirectories()
        try write(state.settings, to: settingsURL)
        try write(state.pairs, to: pairsURL)
        try write(state.runHistory, to: runHistoryURL)
    }

    func storeRunLog(_ log: RunLog) throws -> URL {
        try ensureDirectories()
        let textURL = logsDirectory.appendingPathComponent(log.textLogRelativePath)
        let jsonURL = logsDirectory.appendingPathComponent("\(log.id.uuidString).json")

        let text = format(log: log)
        try text.write(to: textURL, atomically: true, encoding: .utf8)
        try write(log, to: jsonURL)
        return textURL
    }

    func pruneRunHistory(_ runHistory: [RunHistoryItem]) throws -> [RunHistoryItem] {
        let sorted = runHistory.sorted { $0.finishedAt > $1.finishedAt }
        guard sorted.count > maxStoredRunLogs else { return sorted }

        let kept = Array(sorted.prefix(maxStoredRunLogs))
        let removed = sorted.dropFirst(maxStoredRunLogs)
        for item in removed {
            let textURL = logsDirectory.appendingPathComponent(item.textLogRelativePath)
            let jsonURL = logsDirectory.appendingPathComponent("\(item.id.uuidString).json")
            try? fileManager.removeItem(at: textURL)
            try? fileManager.removeItem(at: jsonURL)
        }
        return kept
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func loadOptional<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    private var hasLegacyDefaults: Bool {
        defaults.data(forKey: "backupHistoryData") != nil ||
        (defaults.data(forKey: "sourceBookmarkData") != nil && defaults.data(forKey: "targetBookmarkData") != nil)
    }

    private var settingsURL: URL {
        baseDirectory.appendingPathComponent("settings.json")
    }

    private var pairsURL: URL {
        baseDirectory.appendingPathComponent("backup-pairs.json")
    }

    private var runHistoryURL: URL {
        baseDirectory.appendingPathComponent("run-history.json")
    }

    private var logsDirectory: URL {
        baseDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    private func migrateLegacyState() throws -> PersistedState {
        var pairs: [BackupPair] = []

        if let historyData = defaults.data(forKey: "backupHistoryData") {
            if let decoded = try? decoder.decode([LegacyHistoryEntry].self, from: historyData) {
                pairs = decoded.map(makePair(from:))
            } else if let decoded = try? decoder.decode([LegacyHistoryEntryV0].self, from: historyData) {
                pairs = decoded.map { legacy in
                    makePair(
                        from: LegacyHistoryEntry(
                            id: legacy.id,
                            sourceBookmark: legacy.sourceBookmark,
                            targetBookmark: legacy.targetBookmark,
                            sourcePath: legacy.sourcePath,
                            targetPath: legacy.targetPath,
                            lastSync: legacy.lastSync,
                            status: .success,
                            lastSuccessDate: legacy.lastSync
                        )
                    )
                }
            }
        }

        if let sourceBookmark = defaults.data(forKey: "sourceBookmarkData"),
           let targetBookmark = defaults.data(forKey: "targetBookmarkData"),
           !pairs.contains(where: { $0.sourceBookmark == sourceBookmark && $0.targetBookmark == targetBookmark }) {
            let sourceURL = try? BookmarkResolver.resolve(sourceBookmark)
            let targetURL = try? BookmarkResolver.resolve(targetBookmark)
            let sourcePath = sourceURL?.path ?? ""
            let targetPath = targetURL?.path ?? ""
            pairs.append(
                BackupPair(
                    id: UUID(),
                    sourceBookmark: sourceBookmark,
                    targetBookmark: targetBookmark,
                    sourceCanonicalPath: sourceURL.map(BackupPathValidator.canonicalPath(for:)) ?? sourcePath,
                    targetCanonicalPath: targetURL.map(BackupPathValidator.canonicalPath(for:)) ?? targetPath,
                    sourceVolume: sourceURL.flatMap { try? VolumeIdentityResolver.resolve(for: $0) } ?? .placeholder(for: sourcePath),
                    targetVolume: targetURL.flatMap { try? VolumeIdentityResolver.resolve(for: $0) } ?? .placeholder(for: targetPath),
                    createdAt: Date(),
                    lastRun: nil
                )
            )
        }

        let currentSource = defaults.data(forKey: "sourceBookmarkData")
        let currentTarget = defaults.data(forKey: "targetBookmarkData")
        let selectedPairID = pairs.first(where: { $0.sourceBookmark == currentSource && $0.targetBookmark == currentTarget })?.id

        return PersistedState(
            settings: AppSettings(schemaVersion: AppSettings.current.schemaVersion, lastSelectedPairID: selectedPairID),
            pairs: pairs.sorted(by: sortPairs),
            runHistory: []
        )
    }

    private func makePair(from legacy: LegacyHistoryEntry) -> BackupPair {
        let sourceURL = try? BookmarkResolver.resolve(legacy.sourceBookmark)
        let targetURL = try? BookmarkResolver.resolve(legacy.targetBookmark)
        let sourceCanonical = sourceURL.map(BackupPathValidator.canonicalPath(for:)) ?? legacy.sourcePath
        let targetCanonical = targetURL.map(BackupPathValidator.canonicalPath(for:)) ?? legacy.targetPath
        return BackupPair(
            id: legacy.id,
            sourceBookmark: legacy.sourceBookmark,
            targetBookmark: legacy.targetBookmark,
            sourceCanonicalPath: sourceCanonical,
            targetCanonicalPath: targetCanonical,
            sourceVolume: sourceURL.flatMap { try? VolumeIdentityResolver.resolve(for: $0) } ?? .placeholder(for: legacy.sourcePath),
            targetVolume: targetURL.flatMap { try? VolumeIdentityResolver.resolve(for: $0) } ?? .placeholder(for: legacy.targetPath),
            createdAt: legacy.lastSuccessDate ?? legacy.lastSync,
            lastRun: legacy.lastSuccessDate.map {
                BackupPairLastRun(date: $0, status: legacy.status, warningCount: 0, logID: UUID())
            }
        )
    }

    private func sortPairs(lhs: BackupPair, rhs: BackupPair) -> Bool {
        let lhsDate = lhs.lastRun?.date ?? lhs.createdAt
        let rhsDate = rhs.lastRun?.date ?? rhs.createdAt
        return lhsDate > rhsDate
    }

    private func format(log: RunLog) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "YeOldBackup Run Log",
            "Run ID: \(log.id.uuidString)",
            "Started: \(formatter.string(from: log.startedAt))",
            "Finished: \(formatter.string(from: log.finishedAt))",
            "Exit Code: \(log.exitCode)",
            "Cancelled: \(log.wasCancelled ? "yes" : "no")",
            ""
        ]

        if !log.warnings.isEmpty {
            lines.append("Warnings:")
            lines.append(contentsOf: log.warnings)
            lines.append("")
        }

        lines.append("STDOUT:")
        lines.append(contentsOf: log.stdoutLines)
        lines.append("")
        lines.append("STDERR:")
        lines.append(contentsOf: log.stderrLines)
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

private struct LegacyHistoryEntry: Codable {
    var id: UUID
    var sourceBookmark: Data
    var targetBookmark: Data
    var sourcePath: String
    var targetPath: String
    var lastSync: Date
    var status: BackupOutcomeStatus
    var lastSuccessDate: Date?
}

private struct LegacyHistoryEntryV0: Codable {
    var id: UUID
    var sourceBookmark: Data
    var targetBookmark: Data
    var sourcePath: String
    var targetPath: String
    var lastSync: Date
}
