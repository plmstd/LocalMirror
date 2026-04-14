import Foundation

final class RsyncBinaryLocator {
    private let candidatesProvider: () -> [URL]

    init(candidatesProvider: (() -> [URL])? = nil) {
        self.candidatesProvider = candidatesProvider ?? {
            RsyncBinaryLocator.defaultCandidates()
        }
    }

    func locate() throws -> SyncInstallation {
        let candidates = candidatesProvider()
        for candidate in candidates where fileExistsAndExecutable(candidate) {
            do {
                let version = try versionDescription(for: candidate)
                let bundled = candidate.path != "/usr/bin/rsync"
                return SyncInstallation(binaryURL: candidate, versionDescription: version, isBundled: bundled)
            } catch {
                continue
            }
        }
        throw BackupError.helperMissing("No usable rsync helper was found. Reinstall YeOldBackup to restore the bundled helper.")
    }

    private static func defaultCandidates() -> [URL] {
        let locator = RsyncBinaryLocator(candidatesProvider: { [] })
        return locator.bundledCandidates() + [locator.debugSourceTreeCandidate(), URL(fileURLWithPath: "/usr/bin/rsync")]
    }

    private func bundledCandidates() -> [URL] {
        let bundle = Bundle.main.bundleURL
        let resource = Bundle.main.resourceURL
        return [
            bundle.appendingPathComponent("Contents/Helpers/rsync"),
            bundle.appendingPathComponent("Contents/Resources/Helpers/rsync"),
            bundle.appendingPathComponent("Contents/Resources/rsync"),
            resource?.appendingPathComponent("Helpers/rsync"),
            resource?.appendingPathComponent("rsync")
        ].compactMap { $0 }
    }

    private func debugSourceTreeCandidate() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/rsync")
    }

    private func fileExistsAndExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private func versionDescription(for binaryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw BackupError.helperMissing("The rsync helper at \(binaryURL.path) failed its health check.")
        }
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        let versionLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Unknown rsync version"
        guard !versionLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackupError.helperMissing("The rsync helper at \(binaryURL.path) produced no version output.")
        }
        return versionLine
    }
}
