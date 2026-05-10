import Foundation

enum SyncInstallationKind: String, Hashable {
    case systemProvided
    case custom
}

struct SyncInstallation: Hashable {
    let binaryURL: URL
    let versionDescription: String
    let kind: SyncInstallationKind

    var displayTitle: String {
        switch kind {
        case .systemProvided:
            return "System rsync"
        case .custom:
            return "Custom rsync"
        }
    }
}

struct VolumeIdentity: Codable, Hashable {
    var uuid: String?
    var displayName: String
    var mountPath: String
    var isRemovable: Bool

    static func placeholder(for path: String) -> VolumeIdentity {
        VolumeIdentity(
            uuid: nil,
            displayName: URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent,
            mountPath: path,
            isRemovable: false
        )
    }
}

enum BackupOutcomeStatus: String, Codable, Hashable {
    case success
    case failure
    case cancelled
}

struct BackupPairLastRun: Codable, Hashable {
    var date: Date
    var status: BackupOutcomeStatus
    var warningCount: Int
    var logID: UUID
}

struct TargetCapabilities: Codable, Hashable {
    var fileSystemType: String
    var isAPFS: Bool
    var supportsSnapshots: Bool
    var isReadOnly: Bool

    static let unknown = TargetCapabilities(
        fileSystemType: "Unknown",
        isAPFS: false,
        supportsSnapshots: false,
        isReadOnly: false
    )

    var historyModeLabel: String {
        supportsSnapshots ? "APFS-ready" : "Clone-only"
    }
}

struct BackupPair: Codable, Identifiable, Hashable {
    var id: UUID
    var sourceBookmark: Data
    var targetBookmark: Data
    var sourceCanonicalPath: String
    var targetCanonicalPath: String
    var sourceVolume: VolumeIdentity
    var targetVolume: VolumeIdentity
    var targetCapabilities: TargetCapabilities
    var createdAt: Date
    var lastRun: BackupPairLastRun?

    var sourceName: String {
        URL(fileURLWithPath: sourceCanonicalPath).lastPathComponent
    }

    var targetName: String {
        URL(fileURLWithPath: targetCanonicalPath).lastPathComponent
    }

    init(
        id: UUID,
        sourceBookmark: Data,
        targetBookmark: Data,
        sourceCanonicalPath: String,
        targetCanonicalPath: String,
        sourceVolume: VolumeIdentity,
        targetVolume: VolumeIdentity,
        targetCapabilities: TargetCapabilities,
        createdAt: Date,
        lastRun: BackupPairLastRun?
    ) {
        self.id = id
        self.sourceBookmark = sourceBookmark
        self.targetBookmark = targetBookmark
        self.sourceCanonicalPath = sourceCanonicalPath
        self.targetCanonicalPath = targetCanonicalPath
        self.sourceVolume = sourceVolume
        self.targetVolume = targetVolume
        self.targetCapabilities = targetCapabilities
        self.createdAt = createdAt
        self.lastRun = lastRun
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceBookmark
        case targetBookmark
        case sourceCanonicalPath
        case targetCanonicalPath
        case sourceVolume
        case targetVolume
        case targetCapabilities
        case createdAt
        case lastRun
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceBookmark = try container.decode(Data.self, forKey: .sourceBookmark)
        targetBookmark = try container.decode(Data.self, forKey: .targetBookmark)
        sourceCanonicalPath = try container.decode(String.self, forKey: .sourceCanonicalPath)
        targetCanonicalPath = try container.decode(String.self, forKey: .targetCanonicalPath)
        sourceVolume = try container.decode(VolumeIdentity.self, forKey: .sourceVolume)
        targetVolume = try container.decode(VolumeIdentity.self, forKey: .targetVolume)
        targetCapabilities = try container.decodeIfPresent(TargetCapabilities.self, forKey: .targetCapabilities) ?? .unknown
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastRun = try container.decodeIfPresent(BackupPairLastRun.self, forKey: .lastRun)
    }
}

enum ChangeOperation: String, Codable, Hashable {
    case create
    case update
    case delete
    case metadata
    case directory
    case unknown
}

struct ChangeRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var operation: ChangeOperation
    var itemizedCode: String
    var path: String

    init(id: UUID = UUID(), operation: ChangeOperation, itemizedCode: String, path: String) {
        self.id = id
        self.operation = operation
        self.itemizedCode = itemizedCode
        self.path = path
    }
}

struct SyncStatistics: Codable, Hashable {
    var totalSourceItems: Int
    var transferCount: Int
    var deletionCount: Int
    var estimatedTransferBytes: Int64

    var totalChangeCount: Int {
        transferCount + deletionCount
    }
}

struct SyncPreflightResult: Hashable {
    var plannedChanges: [ChangeRecord]
    var statistics: SyncStatistics
    var stdoutLines: [String]
    var stderrLines: [String]
}

struct RunLog: Codable, Hashable, Identifiable {
    var id: UUID
    var pairID: UUID
    var startedAt: Date
    var finishedAt: Date
    var exitCode: Int32
    var wasCancelled: Bool
    var stdoutLines: [String]
    var stderrLines: [String]
    var warnings: [String]
    var appliedChanges: [ChangeRecord]
    var plannedChanges: [ChangeRecord]
    var textLogRelativePath: String
}

struct SyncRunCompletion: Hashable {
    var log: RunLog
}

struct RunResult: Hashable {
    var pairID: UUID
    var startedAt: Date
    var finishedAt: Date
    var appliedChangeCount: Int
    var deletionCount: Int
    var warnings: [String]
    var logFileURL: URL
    var log: RunLog
    var summary: String
}

struct RunFailure: Hashable {
    var pairID: UUID?
    var startedAt: Date?
    var finishedAt: Date
    var reason: String
    var warnings: [String]
    var logFileURL: URL?
    var log: RunLog?
}

struct RunProgress: Hashable {
    var phase: String
    var totalPlannedChanges: Int
    var appliedChangeCount: Int
    var currentPath: String?
    var lastAppliedChange: ChangeRecord?
    var warningCount: Int
    var estimatedTransferBytes: Int64
    var completedTransferBytes: Int64
    var currentChangeProgress: Double
    var currentFilePercent: Double?
    var currentFileBytesTransferred: Int64?
    var currentFileEstimatedBytes: Int64?

    var totalTransferredBytes: Int64 {
        let currentBytes = currentFilePercent.map { $0 < 1 ? (currentFileBytesTransferred ?? 0) : 0 } ?? 0
        return completedTransferBytes + currentBytes
    }

    var fractionCompleted: Double {
        guard totalPlannedChanges > 0 else { return 0 }
        let completedUnits = Double(appliedChangeCount) + min(max(currentChangeProgress, 0), 0.99)
        let changeFraction = completedUnits / Double(totalPlannedChanges)
        let byteFraction: Double
        if estimatedTransferBytes > 0, totalTransferredBytes > 0 {
            byteFraction = Double(totalTransferredBytes) / Double(estimatedTransferBytes)
        } else {
            byteFraction = 0
        }
        return min(1, max(0, max(changeFraction, byteFraction)))
    }
}

struct TransferProgress: Hashable {
    var path: String
    var bytesTransferred: Int64
    var estimatedFileBytes: Int64?
    var percentComplete: Double
    var isCompleted: Bool
}

struct PreflightProgress: Hashable {
    var phase: String
    var plannedChangeCount: Int
    var currentPath: String?
    var warningCount: Int
}

enum ValidationSeverity: String, Codable, Hashable {
    case info
    case warning
    case blocking
}

struct ValidationMessage: Codable, Hashable, Identifiable {
    var id: UUID
    var severity: ValidationSeverity
    var message: String

    init(id: UUID = UUID(), severity: ValidationSeverity, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

enum RiskLevel: String, Codable, Hashable {
    case low
    case medium
    case high
    case critical
}

struct PreflightReport: Hashable {
    var pair: BackupPair
    var currentSourceVolume: VolumeIdentity
    var currentTargetVolume: VolumeIdentity
    var currentTargetCapabilities: TargetCapabilities
    var statistics: SyncStatistics
    var plannedChanges: [ChangeRecord]
    var exclusions: [String]
    var availableFreeBytes: Int64?
    var validationMessages: [ValidationMessage]
    var warnings: [String]
    var riskLevel: RiskLevel
    var requiresTypedConfirmation: Bool
    var confirmationToken: String?
    var isFirstRun: Bool

    var blockingMessages: [String] {
        validationMessages.filter { $0.severity == .blocking }.map(\.message)
    }

    var warningMessages: [String] {
        validationMessages.filter { $0.severity == .warning }.map(\.message) + warnings
    }

    var canProceed: Bool {
        blockingMessages.isEmpty
    }

    var summaryLine: String {
        if statistics.totalChangeCount == 0 {
            return "Source and target are already aligned."
        }
        return "\(statistics.totalChangeCount) planned change(s), including \(statistics.deletionCount) deletion(s)."
    }

    var targetIsDedicatedVolume: Bool {
        pair.targetCanonicalPath == currentTargetVolume.mountPath
    }

    var snapshotReadinessSummary: String {
        if currentTargetCapabilities.supportsSnapshots {
            if targetIsDedicatedVolume {
                return "The target is an APFS volume root. Clone history can be added here in a later release."
            }
            return "The target volume is APFS, but future clone history would require using a dedicated APFS target volume instead of a folder inside it."
        }

        return "The target file system (\(currentTargetCapabilities.fileSystemType)) supports live clone mode only in v1."
    }
}

enum BackupRunState {
    case idle
    case preflighting
    case review(PreflightReport)
    case running(RunProgress)
    case cancelling(String)
    case completed(RunResult)
    case failed(RunFailure)
    case cancelled(RunFailure)
}

struct RunHistoryItem: Codable, Identifiable, Hashable {
    var id: UUID
    var pairID: UUID
    var startedAt: Date
    var finishedAt: Date
    var outcome: BackupOutcomeStatus
    var appliedChangeCount: Int
    var deletionCount: Int
    var warningCount: Int
    var summary: String
    var textLogRelativePath: String
}

struct AppSettings: Codable, Hashable {
    var schemaVersion: Int
    var lastSelectedPairID: UUID?

    static let current = AppSettings(schemaVersion: 2, lastSelectedPairID: nil)
}

struct PersistedState: Hashable {
    var settings: AppSettings
    var pairs: [BackupPair]
    var runHistory: [RunHistoryItem]
}

enum CommandTerminationReason: String, Hashable {
    case exit
    case signal
}

struct CommandDiagnostics: Hashable {
    var phase: String
    var binaryPath: String
    var arguments: [String]
    var startedAt: Date
    var finishedAt: Date
    var terminationStatus: Int32
    var terminationReason: CommandTerminationReason
    var stdoutLines: [String]
    var stderrLines: [String]
}

enum SyncRunEvent: Hashable {
    case started(Date)
    case changeDetected(ChangeRecord)
    case appliedChange(ChangeRecord)
    case transferProgress(TransferProgress)
    case warning(String)
    case info(String)
}

enum SyncPreflightEvent: Hashable {
    case started(Date)
    case plannedChange(ChangeRecord)
    case warning(String)
    case info(String)
}

enum BackupError: LocalizedError, Hashable {
    case invalidSelection(String)
    case helperMissing(String)
    case rsyncLaunchFailed(String)
    case rsyncFailed(String)
    case preflightFailed(String, CommandDiagnostics?)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSelection(let message),
             .helperMissing(let message),
             .rsyncLaunchFailed(let message),
             .rsyncFailed(let message),
             .preflightFailed(let message, _),
             .persistenceFailed(let message):
            return message
        }
    }

    var diagnostics: CommandDiagnostics? {
        switch self {
        case .preflightFailed(_, let diagnostics):
            return diagnostics
        default:
            return nil
        }
    }
}

enum BackupExclusions {
    static let defaults = [
        ".Spotlight-V100/",
        ".fseventsd/",
        ".Trashes",
        ".TemporaryItems/",
        ".DS_Store",
        ".DocumentRevisions-V100/"
    ]
}

protocol SyncEngine: AnyObject, Sendable {
    var isRunning: Bool { get }
    func validateInstallation() throws -> SyncInstallation
    func preflight(
        pair: BackupPair,
        exclusions: [String],
        eventHandler: (@Sendable (SyncPreflightEvent) async -> Void)?
    ) async throws -> SyncPreflightResult
    func run(
        pair: BackupPair,
        plannedChanges: [ChangeRecord],
        exclusions: [String],
        eventHandler: @escaping @Sendable (SyncRunEvent) async -> Void
    ) async throws -> SyncRunCompletion
    func requestCancellation() async
}

extension SyncEngine {
    func preflight(pair: BackupPair, exclusions: [String]) async throws -> SyncPreflightResult {
        try await preflight(pair: pair, exclusions: exclusions, eventHandler: nil)
    }
}
