import Foundation

enum SnapshotPostCloneResult: Hashable {
    case skipped(String)
    case created(String)
}

protocol SnapshotService: AnyObject, Sendable {
    func postCloneSuccess(
        for pair: BackupPair,
        targetURL: URL,
        targetCapabilities: TargetCapabilities
    ) async throws -> SnapshotPostCloneResult
}

final class NoopSnapshotService: SnapshotService, @unchecked Sendable {
    func postCloneSuccess(
        for pair: BackupPair,
        targetURL: URL,
        targetCapabilities: TargetCapabilities
    ) async throws -> SnapshotPostCloneResult {
        .skipped("Snapshot history is not enabled in LocalMirror v1.")
    }
}
