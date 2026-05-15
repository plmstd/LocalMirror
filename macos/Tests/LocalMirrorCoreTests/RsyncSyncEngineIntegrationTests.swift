import Foundation
import XCTest
@testable import LocalMirrorCore

final class RsyncSyncEngineIntegrationTests: XCTestCase {
    func testPreflightDetectsCreateUpdateAndDeleteAgainstTempDirectories() async throws {
        let fixture = try IntegrationFixture()
        defer { fixture.cleanup() }

        try fixture.writeSourceFile("updated.txt", contents: "new content")
        try fixture.writeSourceFile("folder with spaces/\u{00FC}ber.txt", contents: "unicode")
        try fixture.writeTargetFile("updated.txt", contents: "old")
        try fixture.writeTargetFile("stale.txt", contents: "remove me")

        let engine = RsyncSyncEngine(locator: RsyncBinaryLocator(candidatesProvider: { [URL(fileURLWithPath: "/usr/bin/rsync")] }))
        let preflight = try await engine.preflight(pair: fixture.makePair(), exclusions: [])
        let normalizedPaths = preflight.plannedChanges.map { $0.path.precomposedStringWithCanonicalMapping }

        XCTAssertEqual(preflight.statistics.deletionCount, 1)
        XCTAssertGreaterThanOrEqual(preflight.statistics.transferCount, 2)
        XCTAssertTrue(preflight.plannedChanges.contains(where: { $0.operation == .delete && $0.path == "stale.txt" }))
        XCTAssertTrue(normalizedPaths.contains("updated.txt"))
        XCTAssertTrue(normalizedPaths.contains("folder with spaces/\u{00FC}ber.txt"))
    }

    func testRunAppliesChangesAndLeavesTargetMatchingSource() async throws {
        let fixture = try IntegrationFixture()
        defer { fixture.cleanup() }

        try fixture.writeSourceFile("updated.txt", contents: "new content")
        try fixture.writeSourceFile("folder with spaces/\u{00FC}ber.txt", contents: "unicode")
        try fixture.writeTargetFile("updated.txt", contents: "old")
        try fixture.writeTargetFile("stale.txt", contents: "remove me")

        let engine = RsyncSyncEngine(locator: RsyncBinaryLocator(candidatesProvider: { [URL(fileURLWithPath: "/usr/bin/rsync")] }))
        let pair = try fixture.makePair()
        let preflight = try await engine.preflight(pair: pair, exclusions: [])
        let completion = try await engine.run(pair: pair, plannedChanges: preflight.plannedChanges, exclusions: []) { _ in }

        XCTAssertEqual(completion.log.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.targetURL.appendingPathComponent("stale.txt").path))
        XCTAssertEqual(try fixture.readTargetFile("updated.txt"), "new content")
        XCTAssertEqual(try fixture.readTargetFile("folder with spaces/\u{00FC}ber.txt"), "unicode")
        XCTAssertEqual(try fixture.relativeFileList(at: fixture.sourceURL), try fixture.relativeFileList(at: fixture.targetURL))
    }
}

private final class IntegrationFixture {
    let rootURL: URL
    let sourceURL: URL
    let targetURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
        targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
    }

    func makePair() throws -> BackupPair {
        BackupPair(
            id: UUID(),
            sourceBookmark: try BookmarkResolver.makeBookmark(for: sourceURL),
            targetBookmark: try BookmarkResolver.makeBookmark(for: targetURL),
            sourceCanonicalPath: sourceURL.path,
            targetCanonicalPath: targetURL.path,
            sourceVolume: try VolumeIdentityResolver.resolve(for: sourceURL),
            targetVolume: try VolumeIdentityResolver.resolve(for: targetURL),
            targetCapabilities: try VolumeIdentityResolver.resolveTargetCapabilities(for: targetURL),
            createdAt: Date(),
            lastRun: nil
        )
    }

    func writeSourceFile(_ relativePath: String, contents: String) throws {
        try writeFile(relativePath, contents: contents, baseURL: sourceURL)
    }

    func writeTargetFile(_ relativePath: String, contents: String) throws {
        try writeFile(relativePath, contents: contents, baseURL: targetURL)
    }

    func readTargetFile(_ relativePath: String) throws -> String {
        let url = targetURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func relativeFileList(at baseURL: URL) throws -> [String] {
        let normalizedBasePath = baseURL.resolvingSymlinksInPath().path + "/"
        let enumerator = FileManager.default.enumerator(at: baseURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var paths: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                let normalizedPath = fileURL.resolvingSymlinksInPath().path
                paths.append(normalizedPath.replacingOccurrences(of: normalizedBasePath, with: "").precomposedStringWithCanonicalMapping)
            }
        }
        return paths.sorted()
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private func writeFile(_ relativePath: String, contents: String, baseURL: URL) throws {
        let url = baseURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
