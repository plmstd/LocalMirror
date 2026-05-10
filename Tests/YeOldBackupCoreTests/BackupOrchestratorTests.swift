import Foundation
import XCTest
@testable import YeOldBackupCore

@MainActor
final class BackupOrchestratorTests: XCTestCase {
    func testFirstRunDeletionHeavyPreflightRequiresTypedConfirmation() async throws {
        let engine = FakeSyncEngine()
        engine.preflightResult = SyncPreflightResult(
            plannedChanges: [
                ChangeRecord(operation: .delete, itemizedCode: "*deleting", path: "old-1"),
                ChangeRecord(operation: .delete, itemizedCode: "*deleting", path: "old-2"),
                ChangeRecord(operation: .delete, itemizedCode: "*deleting", path: "old-3"),
                ChangeRecord(operation: .delete, itemizedCode: "*deleting", path: "old-4"),
                ChangeRecord(operation: .delete, itemizedCode: "*deleting", path: "old-5")
            ],
            statistics: SyncStatistics(totalSourceItems: 10, transferCount: 0, deletionCount: 5, estimatedTransferBytes: 0),
            stdoutLines: [],
            stderrLines: []
        )

        let orchestrator = BackupOrchestrator(engine: engine)
        orchestrator.beginPreflight(for: try makePair())
        let report = try await waitForReview(orchestrator)

        XCTAssertTrue(report.requiresTypedConfirmation)
        XCTAssertEqual(report.riskLevel, .high)
    }

    func testCancellationTransitionsToCancelled() async throws {
        let engine = FakeSyncEngine()
        let pair = try makePair()
        engine.preflightResult = SyncPreflightResult(
            plannedChanges: [ChangeRecord(operation: .update, itemizedCode: ">f.st....", path: "file.txt")],
            statistics: SyncStatistics(totalSourceItems: 1, transferCount: 1, deletionCount: 0, estimatedTransferBytes: 1_024),
            stdoutLines: [],
            stderrLines: []
        )
        engine.runFactory = {
            try await Task.sleep(for: .milliseconds(50))
            while !engine.cancelWasRequested {
                try await Task.sleep(for: .milliseconds(10))
            }
            return SyncRunCompletion(
                log: RunLog(
                    id: UUID(),
                    pairID: pair.id,
                    startedAt: Date(),
                    finishedAt: Date(),
                    exitCode: 2,
                    wasCancelled: true,
                    stdoutLines: [],
                    stderrLines: [],
                    warnings: [],
                    appliedChanges: [],
                    plannedChanges: [],
                    textLogRelativePath: "cancelled.log"
                )
            )
        }

        let orchestrator = BackupOrchestrator(engine: engine)
        orchestrator.beginPreflight(for: pair)
        _ = try await waitForReview(orchestrator)
        orchestrator.startApprovedRun()
        try await Task.sleep(for: .milliseconds(50))
        orchestrator.requestCancellation()

        let failure = try await waitForCancelled(orchestrator)
        XCTAssertTrue(failure.reason.contains("partially synced"))
    }

    func testPreflightPublishesProgressBeforeReviewCompletes() async throws {
        let engine = FakeSyncEngine()
        let change = ChangeRecord(operation: .update, itemizedCode: ">f.st....", path: "large.bin")
        engine.preflightResult = SyncPreflightResult(
            plannedChanges: [change],
            statistics: SyncStatistics(totalSourceItems: 1, transferCount: 1, deletionCount: 0, estimatedTransferBytes: 1_024),
            stdoutLines: [],
            stderrLines: []
        )
        engine.preflightFactory = { eventHandler in
            await eventHandler?(.started(Date()))
            await eventHandler?(.plannedChange(change))
            try await Task.sleep(for: .milliseconds(80))
            return engine.preflightResult
        }

        let orchestrator = BackupOrchestrator(engine: engine)
        orchestrator.beginPreflight(for: try makePair())

        let progress = try await waitForPreflightProgress(orchestrator)
        XCTAssertEqual(progress.plannedChangeCount, 1)
        XCTAssertEqual(progress.currentPath, "large.bin")

        _ = try await waitForReview(orchestrator)
    }

    private func waitForPreflightProgress(_ orchestrator: BackupOrchestrator) async throws -> PreflightProgress {
        for _ in 0..<100 {
            if let progress = orchestrator.preflightProgress, progress.plannedChangeCount > 0 {
                return progress
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for preflight progress")
        throw CancellationError()
    }

    private func waitForReview(_ orchestrator: BackupOrchestrator) async throws -> PreflightReport {
        for _ in 0..<100 {
            if case .review(let report) = orchestrator.state {
                return report
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for review state")
        throw CancellationError()
    }

    private func waitForCancelled(_ orchestrator: BackupOrchestrator) async throws -> RunFailure {
        for _ in 0..<200 {
            if case .cancelled(let failure) = orchestrator.state {
                return failure
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for cancelled state")
        throw CancellationError()
    }

    private func makePair() throws -> BackupPair {
        let source = try makeDirectory(named: "source")
        let target = try makeDirectory(named: "target")
        return BackupPair(
            id: UUID(),
            sourceBookmark: try BookmarkResolver.makeBookmark(for: source),
            targetBookmark: try BookmarkResolver.makeBookmark(for: target),
            sourceCanonicalPath: source.path,
            targetCanonicalPath: target.path,
            sourceVolume: try VolumeIdentityResolver.resolve(for: source),
            targetVolume: try VolumeIdentityResolver.resolve(for: target),
            targetCapabilities: try VolumeIdentityResolver.resolveTargetCapabilities(for: target),
            createdAt: Date(),
            lastRun: nil
        )
    }

    private func makeDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class FakeSyncEngine: SyncEngine, @unchecked Sendable {
    var preflightResult = SyncPreflightResult(plannedChanges: [], statistics: .init(totalSourceItems: 0, transferCount: 0, deletionCount: 0, estimatedTransferBytes: 0), stdoutLines: [], stderrLines: [])
    var preflightFactory: (((@Sendable (SyncPreflightEvent) async -> Void)?) async throws -> SyncPreflightResult)?
    var runFactory: (() async throws -> SyncRunCompletion)?
    var cancelWasRequested = false
    var isRunning = false

    func validateInstallation() throws -> SyncInstallation {
        SyncInstallation(binaryURL: URL(fileURLWithPath: "/tmp/rsync"), versionDescription: "test", kind: .custom)
    }

    func preflight(
        pair: BackupPair,
        exclusions: [String],
        eventHandler: (@Sendable (SyncPreflightEvent) async -> Void)?
    ) async throws -> SyncPreflightResult {
        if let preflightFactory {
            return try await preflightFactory(eventHandler)
        }
        return preflightResult
    }

    func run(pair: BackupPair, plannedChanges: [ChangeRecord], exclusions: [String], eventHandler: @escaping @Sendable (SyncRunEvent) async -> Void) async throws -> SyncRunCompletion {
        isRunning = true
        await eventHandler(.started(Date()))
        defer { isRunning = false }
        if let runFactory {
            return try await runFactory()
        }
        return SyncRunCompletion(
            log: RunLog(
                id: UUID(),
                pairID: pair.id,
                startedAt: Date(),
                finishedAt: Date(),
                exitCode: 0,
                wasCancelled: false,
                stdoutLines: [],
                stderrLines: [],
                warnings: [],
                appliedChanges: plannedChanges,
                plannedChanges: plannedChanges,
                textLogRelativePath: "test.log"
            )
        )
    }

    func requestCancellation() async {
        cancelWasRequested = true
    }
}
