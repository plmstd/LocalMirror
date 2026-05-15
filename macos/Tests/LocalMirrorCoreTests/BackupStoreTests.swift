import Foundation
import XCTest
@testable import LocalMirrorCore

final class BackupStoreTests: XCTestCase {
    func testPersistAndReloadState() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = BackupStore(defaults: defaults, baseDirectory: tempRoot, maxStoredRunLogs: 5)

        let pair = makePair()
        let state = PersistedState(settings: .init(schemaVersion: 2, lastSelectedPairID: pair.id), pairs: [pair], runHistory: [])
        try store.persist(state: state)

        let loaded = try store.loadState()
        XCTAssertEqual(loaded.settings.lastSelectedPairID, pair.id)
        XCTAssertEqual(loaded.pairs.first?.sourceCanonicalPath, pair.sourceCanonicalPath)
    }

    func testMigratesLegacyCurrentSelection() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let source = try makeDirectory(named: "legacy-source")
        let target = try makeDirectory(named: "legacy-target")
        defaults.set(try BookmarkResolver.makeBookmark(for: source), forKey: "sourceBookmarkData")
        defaults.set(try BookmarkResolver.makeBookmark(for: target), forKey: "targetBookmarkData")

        let store = BackupStore(defaults: defaults, baseDirectory: tempRoot, maxStoredRunLogs: 5)
        let migrated = try store.loadState()

        XCTAssertEqual(migrated.pairs.count, 1)
        XCTAssertEqual(migrated.settings.lastSelectedPairID, migrated.pairs.first?.id)
    }

    func testPrunesExcessLogs() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = BackupStore(defaults: defaults, baseDirectory: tempRoot, maxStoredRunLogs: 1)

        let baseLog = makeLog(relativePath: "first.log")
        let otherLog = makeLog(relativePath: "second.log")
        _ = try store.storeRunLog(baseLog)
        _ = try store.storeRunLog(otherLog)

        let history = [
            RunHistoryItem(id: baseLog.id, pairID: baseLog.pairID, startedAt: baseLog.startedAt, finishedAt: baseLog.finishedAt, outcome: .success, appliedChangeCount: 1, deletionCount: 0, warningCount: 0, summary: "first", textLogRelativePath: baseLog.textLogRelativePath),
            RunHistoryItem(id: otherLog.id, pairID: otherLog.pairID, startedAt: otherLog.startedAt, finishedAt: otherLog.finishedAt.addingTimeInterval(5), outcome: .success, appliedChangeCount: 1, deletionCount: 0, warningCount: 0, summary: "second", textLogRelativePath: otherLog.textLogRelativePath)
        ]

        let pruned = try store.pruneRunHistory(history)
        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned.first?.id, otherLog.id)
    }

    func testTextLogOmitsVerboseItemizedChangeLines() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = BackupStore(defaults: defaults, baseDirectory: tempRoot, maxStoredRunLogs: 5)

        let log = RunLog(
            id: UUID(),
            pairID: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            exitCode: 0,
            wasCancelled: false,
            stdoutLines: [
                "ITEM|>f+++++++|large.mov",
                "*deleting stale.txt",
                "Number of files: 2"
            ],
            stderrLines: ["warning"],
            warnings: ["warning"],
            appliedChanges: [],
            plannedChanges: [],
            textLogRelativePath: "compacted.log"
        )

        let textURL = try store.storeRunLog(log)
        let text = try String(contentsOf: textURL, encoding: .utf8)
        XCTAssertFalse(text.contains("ITEM|>f+++++++|large.mov"))
        XCTAssertFalse(text.contains("*deleting stale.txt"))
        XCTAssertTrue(text.contains("Omitted 2 itemized rsync change line(s)"))
        XCTAssertTrue(text.contains("Number of files: 2"))
        XCTAssertTrue(text.contains("warning"))
    }

    private func makePair() -> BackupPair {
        BackupPair(
            id: UUID(),
            sourceBookmark: Data([0x01]),
            targetBookmark: Data([0x02]),
            sourceCanonicalPath: "/tmp/source",
            targetCanonicalPath: "/tmp/target",
            sourceVolume: .placeholder(for: "/tmp/source"),
            targetVolume: .placeholder(for: "/tmp/target"),
            targetCapabilities: .unknown,
            createdAt: Date(),
            lastRun: nil
        )
    }

    private func makeLog(relativePath: String) -> RunLog {
        RunLog(
            id: UUID(),
            pairID: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            exitCode: 0,
            wasCancelled: false,
            stdoutLines: ["ok"],
            stderrLines: [],
            warnings: [],
            appliedChanges: [],
            plannedChanges: [],
            textLogRelativePath: relativePath
        )
    }

    private func makeDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
