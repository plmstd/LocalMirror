import XCTest
@testable import LocalMirrorCore

final class RsyncOutputParserTests: XCTestCase {
    func testParseMixedPreflightFixture() throws {
        let fixture = try FixtureLoader.text("mixed-preflight.txt")
        let lines = fixture.split(whereSeparator: \.isNewline).map(String.init)

        let result = RsyncOutputParser.parsePreflight(stdout: lines, stderr: [])

        XCTAssertEqual(result.statistics.totalSourceItems, 12)
        XCTAssertEqual(result.statistics.transferCount, 3)
        XCTAssertEqual(result.statistics.deletionCount, 2)
        XCTAssertEqual(result.statistics.estimatedTransferBytes, 10240)
        XCTAssertEqual(result.plannedChanges.filter { $0.operation == .delete }.count, 2)
        XCTAssertTrue(result.plannedChanges.contains(where: { $0.path == "Documents/new.txt" && $0.operation == .create }))
    }

    func testParseWarningsIgnoredWhenCancelled() {
        let warnings = RsyncOutputParser.parseWarnings(stderr: ["Permission denied"], exitCode: 20, wasCancelled: true)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testParseByteCountSupportsUnits() {
        XCTAssertEqual(RsyncOutputParser.parseByteCount("10 KB"), 10 * 1_024)
        XCTAssertEqual(RsyncOutputParser.parseByteCount("2 MB"), 2 * 1_024 * 1_024)
        XCTAssertEqual(RsyncOutputParser.parseByteCount("1 GB"), 1_024 * 1_024 * 1_024)
    }

    func testParseTransferProgressParsesCarriageReturnStyleProgressLine() {
        let progress = RsyncOutputParser.parseTransferProgress(
            from: "         163840  16%   64.12KB/s   00:00:12",
            currentPath: "large.bin"
        )

        XCTAssertEqual(progress?.path, "large.bin")
        XCTAssertEqual(progress?.bytesTransferred, 163_840)
        XCTAssertEqual(progress?.estimatedFileBytes, 1_024_000)
        XCTAssertEqual(progress?.percentComplete, 0.16)
        XCTAssertEqual(progress?.isCompleted, false)
    }

    func testParseTransferProgressMarksFinalTransferLineAsCompleted() {
        let progress = RsyncOutputParser.parseTransferProgress(
            from: "        8000000 100% 304.59MB/s   00:00:00 (xfer#1, to-check=1/2)",
            currentPath: "large.bin"
        )

        XCTAssertEqual(progress?.path, "large.bin")
        XCTAssertEqual(progress?.percentComplete, 1)
        XCTAssertEqual(progress?.isCompleted, true)
    }

    func testParseTransferProgressDoesNotTreatIntermediateFullPercentAsComplete() {
        let progress = RsyncOutputParser.parseTransferProgress(
            from: "        8388608 100% 480.01KB/s   00:00:00",
            currentPath: "large.bin"
        )

        XCTAssertEqual(progress?.path, "large.bin")
        XCTAssertEqual(progress?.percentComplete, 1)
        XCTAssertEqual(progress?.isCompleted, false)
    }
}
