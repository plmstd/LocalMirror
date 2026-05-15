import Foundation

enum RsyncOutputParser {
    static func parsePreflight(stdout: [String], stderr: [String]) -> SyncPreflightResult {
        let changes = parseChanges(from: stdout)
        let statistics = parseStatistics(from: stdout, changes: changes)
        return SyncPreflightResult(
            plannedChanges: changes,
            statistics: statistics,
            stdoutLines: stdout,
            stderrLines: stderr
        )
    }

    static func parseRun(stdout: [String], stderr: [String], pairID: UUID, startedAt: Date, finishedAt: Date, exitCode: Int32, wasCancelled: Bool, textLogRelativePath: String, plannedChanges: [ChangeRecord]) -> SyncRunCompletion {
        let appliedChanges = parseChanges(from: stdout)
        let warnings = parseWarnings(stderr: stderr, exitCode: exitCode, wasCancelled: wasCancelled)
        return SyncRunCompletion(
            log: RunLog(
                id: UUID(),
                pairID: pairID,
                startedAt: startedAt,
                finishedAt: finishedAt,
                exitCode: exitCode,
                wasCancelled: wasCancelled,
                stdoutLines: stdout,
                stderrLines: stderr,
                warnings: warnings,
                appliedChanges: appliedChanges,
                plannedChanges: plannedChanges,
                textLogRelativePath: textLogRelativePath
            )
        )
    }

    static func parseWarnings(stderr: [String], exitCode: Int32, wasCancelled: Bool) -> [String] {
        if wasCancelled {
            return []
        }
        return stderr
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.contains("warning: some files vanished before they could be transferred") || exitCode == 0 }
    }

    static func parseChanges(from lines: [String]) -> [ChangeRecord] {
        lines.compactMap { line in
            if line.hasPrefix("*deleting ") {
                let path = String(line.dropFirst("*deleting ".count)).trimmingCharacters(in: .whitespaces)
                return ChangeRecord(operation: .delete, itemizedCode: "*deleting", path: path)
            }

            guard line.hasPrefix("ITEM|") else { return nil }
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let itemized = String(parts[1])
            let path = String(parts[2])
            return ChangeRecord(operation: operation(for: itemized), itemizedCode: itemized, path: path)
        }
    }

    static func parseStatistics(from lines: [String], changes: [ChangeRecord]) -> SyncStatistics {
        var totalSourceItems = 0
        var transferCount = changes.filter { $0.operation == .create || $0.operation == .update || $0.operation == .metadata }.count
        var deletionCount = changes.filter { $0.operation == .delete }.count
        var estimatedTransferBytes: Int64 = 0

        for line in lines {
            if line.hasPrefix("Number of files:") {
                totalSourceItems = parseIntValue(afterColonIn: line) ?? totalSourceItems
            } else if line.hasPrefix("Number of files transferred:") {
                transferCount = parseIntValue(afterColonIn: line) ?? transferCount
            } else if line.hasPrefix("Number of deleted files:") || line.hasPrefix("Number of deletions:") {
                deletionCount = parseIntValue(afterColonIn: line) ?? deletionCount
            } else if line.hasPrefix("Total transferred file size:") {
                estimatedTransferBytes = parseByteCount(afterColonIn: line) ?? estimatedTransferBytes
            }
        }

        return SyncStatistics(
            totalSourceItems: totalSourceItems,
            transferCount: transferCount,
            deletionCount: deletionCount,
            estimatedTransferBytes: estimatedTransferBytes
        )
    }

    private static func operation(for itemized: String) -> ChangeOperation {
        if itemized.hasPrefix(">") {
            return itemized.contains("+") ? .create : .update
        }
        if itemized.hasPrefix("c") {
            return itemized.contains("d") ? .directory : .update
        }
        if itemized.hasPrefix(".") {
            return .metadata
        }
        if itemized.hasPrefix("d") {
            return .directory
        }
        return .unknown
    }

    private static func parseIntValue(afterColonIn line: String) -> Int? {
        guard let valuePart = line.split(separator: ":", maxSplits: 1).last else { return nil }
        let trimmed = valuePart
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first?
            .replacingOccurrences(of: ",", with: "")
        guard let trimmed else { return nil }
        return Int(trimmed)
    }

    private static func parseByteCount(afterColonIn line: String) -> Int64? {
        guard let valuePart = line.split(separator: ":", maxSplits: 1).last else { return nil }
        let trimmed = valuePart.trimmingCharacters(in: .whitespaces)
        return parseByteCount(trimmed)
    }

    static func parseByteCount(_ string: String) -> Int64? {
        let sanitized = string.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        let components = sanitized.split(separator: " ")
        guard let numberComponent = components.first else { return nil }
        let unit = components.count > 1 ? String(components[1]).uppercased() : "B"
        guard let number = Double(numberComponent) else { return nil }

        let multiplier: Double
        switch unit {
        case "B":
            multiplier = 1
        case "KB", "K":
            multiplier = 1_024
        case "MB", "M":
            multiplier = 1_024 * 1_024
        case "GB", "G":
            multiplier = 1_024 * 1_024 * 1_024
        case "TB", "T":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024
        default:
            multiplier = 1
        }
        return Int64(number * multiplier)
    }

    static func parseTransferProgress(from line: String, currentPath: String?) -> TransferProgress? {
        guard let currentPath else { return nil }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(whereSeparator: \.isWhitespace)
        guard components.count >= 2 else { return nil }

        let byteToken = String(components[0]).replacingOccurrences(of: ",", with: "")
        let percentToken = String(components[1])

        guard let bytesTransferred = Int64(byteToken), percentToken.hasSuffix("%") else {
            return nil
        }

        let percentValue = String(percentToken.dropLast())
        guard let percentComplete = Double(percentValue) else {
            return nil
        }

        let normalizedPercent = percentComplete / 100
        let estimatedFileBytes = normalizedPercent > 0
            ? Int64((Double(bytesTransferred) / normalizedPercent).rounded())
            : nil

        return TransferProgress(
            path: currentPath,
            bytesTransferred: bytesTransferred,
            estimatedFileBytes: estimatedFileBytes,
            percentComplete: normalizedPercent,
            isCompleted: trimmed.contains("(xfer#")
        )
    }
}
