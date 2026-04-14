import Foundation
import XCTest
@testable import YeOldBackupCore

final class RsyncBinaryLocatorTests: XCTestCase {
    func testLocateSkipsUnhealthyCandidateAndFallsBackToHealthyBinary() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let unhealthy = tempDirectory.appendingPathComponent("bad-rsync")
        let healthy = tempDirectory.appendingPathComponent("good-rsync")

        try writeExecutable(
            """
            #!/bin/zsh
            kill -11 $$
            """,
            to: unhealthy
        )

        try writeExecutable(
            """
            #!/bin/zsh
            echo "rsync version test"
            """,
            to: healthy
        )

        let locator = RsyncBinaryLocator(candidatesProvider: { [unhealthy, healthy] })
        let installation = try locator.locate()

        XCTAssertEqual(installation.binaryURL, healthy)
        XCTAssertEqual(installation.versionDescription, "rsync version test")
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
