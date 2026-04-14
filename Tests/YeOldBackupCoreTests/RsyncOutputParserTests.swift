import XCTest
@testable import YeOldBackupCore

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
}
