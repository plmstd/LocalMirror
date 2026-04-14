import Foundation

struct SyncInstallation: Hashable {
    let binaryURL: URL
    let versionDescription: String
    let isBundled: Bool
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

struct BackupPair: Codable, Identifiable, Hashable {
    var id: UUID
    var sourceBookmark: Data
    var targetBookmark: Data
    var sourceCanonicalPath: String
    var targetCanonicalPath: String
    var sourceVolume: VolumeIdentity
    var targetVolume: VolumeIdentity
    var createdAt: Date
    var lastRun: BackupPairLastRun?

    var sourceName: String {
        URL(fileURLWithPath: sourceCanonicalPath).lastPathComponent
    }

    var targetName: String {
        URL(fileURLWithPath: targetCanonicalPath).lastPathComponent
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

    var fractionCompleted: Double {
        guard totalPlannedChanges > 0 else { return 0 }
        return min(1, max(0, Double(appliedChangeCount) / Double(totalPlannedChanges)))
    }
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

    static let current = AppSettings(schemaVersion: 1, lastSelectedPairID: nil)
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
    case appliedChange(ChangeRecord)
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

protocol SyncEngine: AnyObject {
    var isRunning: Bool { get }
    func validateInstallation() throws -> SyncInstallation
    func preflight(pair: BackupPair, exclusions: [String]) async throws -> SyncPreflightResult
    func run(
        pair: BackupPair,
        plannedChanges: [ChangeRecord],
        exclusions: [String],
        eventHandler: @escaping @Sendable (SyncRunEvent) -> Void
    ) async throws -> SyncRunCompletion
    func requestCancellation() async
}
