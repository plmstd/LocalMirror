import Foundation
import XCTest
@testable import YeOldBackupCore

final class PathValidatorTests: XCTestCase {
    func testBlocksSameSourceAndTarget() throws {
        let temp = try makeDirectory(named: "same")
        let result = BackupPathValidator.validate(source: temp, target: temp)
        XCTAssertTrue(result.messages.contains(where: { $0.message.contains("same folder") }))
    }

    func testBlocksNestedTarget() throws {
        let source = try makeDirectory(named: "nested-source")
        let target = source.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = BackupPathValidator.validate(source: source, target: target)
        XCTAssertTrue(result.messages.contains(where: { $0.message.contains("contain each other") }))
    }

    func testBlocksProtectedTopLevelTarget() throws {
        let source = try makeDirectory(named: "safe-source")
        let target = URL(fileURLWithPath: "/Users", isDirectory: true)
        let result = BackupPathValidator.validate(source: source, target: target)
        XCTAssertTrue(result.messages.contains(where: { $0.message.contains("protected top-level") }))
    }

    private func makeDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
