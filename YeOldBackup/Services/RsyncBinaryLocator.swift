import Foundation

final class RsyncBinaryLocator {
    func locate() throws -> SyncInstallation {
        let candidates = bundledCandidates() + [debugSourceTreeCandidate(), URL(fileURLWithPath: "/usr/bin/rsync")]
        for candidate in candidates where fileExistsAndExecutable(candidate) {
            let version = try versionDescription(for: candidate)
            let bundled = candidate.path != "/usr/bin/rsync"
            return SyncInstallation(binaryURL: candidate, versionDescription: version, isBundled: bundled)
        }
        throw BackupError.helperMissing("No usable rsync helper was found. Reinstall YeOldBackup to restore the bundled helper.")
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
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        let versionLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Unknown rsync version"
        return versionLine
    }
}
