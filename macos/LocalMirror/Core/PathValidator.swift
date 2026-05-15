import Foundation

struct PathValidationResult: Hashable {
    var sourceCanonicalPath: String
    var targetCanonicalPath: String
    var messages: [ValidationMessage]
}

enum BackupPathValidator {
    private static let blockedTargetPaths: Set<String> = [
        "/",
        "/Applications",
        "/Library",
        "/System",
        "/Users",
        "/Volumes",
        "/bin",
        "/cores",
        "/dev",
        "/etc",
        "/opt",
        "/private",
        "/sbin",
        "/usr",
        "/var"
    ]

    static func canonicalPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func validate(source: URL, target: URL) -> PathValidationResult {
        let sourceCanonical = canonicalPath(for: source)
        let targetCanonical = canonicalPath(for: target)
        var messages: [ValidationMessage] = []

        if sourceCanonical == targetCanonical {
            messages.append(.init(severity: .blocking, message: "Source and target resolve to the same folder."))
        }

        if sourceCanonical.hasPrefix(targetCanonical + "/") || targetCanonical.hasPrefix(sourceCanonical + "/") {
            messages.append(.init(severity: .blocking, message: "Source and target cannot contain each other."))
        }

        if blockedTargetPaths.contains(targetCanonical) {
            messages.append(.init(severity: .blocking, message: "The selected target is a protected top-level macOS path. Choose a dedicated backup folder or drive."))
        }

        let homePath = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
        if targetCanonical == homePath {
            messages.append(.init(severity: .blocking, message: "The selected target is your home folder. Choose a dedicated backup folder or drive."))
        }

        if !FileManager.default.fileExists(atPath: sourceCanonical) {
            messages.append(.init(severity: .blocking, message: "The selected source folder is not currently available."))
        }

        if !FileManager.default.fileExists(atPath: targetCanonical) {
            messages.append(.init(severity: .blocking, message: "The selected target folder is not currently available."))
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: sourceCanonical, isDirectory: &isDirectory), !isDirectory.boolValue {
            messages.append(.init(severity: .blocking, message: "The selected source is not a folder."))
        }

        isDirectory = false
        if FileManager.default.fileExists(atPath: targetCanonical, isDirectory: &isDirectory), !isDirectory.boolValue {
            messages.append(.init(severity: .blocking, message: "The selected target is not a folder."))
        }

        if source.path != sourceCanonical {
            messages.append(.init(severity: .info, message: "The source path resolves through a symbolic link to \(sourceCanonical)."))
        }

        if target.path != targetCanonical {
            messages.append(.init(severity: .info, message: "The target path resolves through a symbolic link to \(targetCanonical)."))
        }

        return PathValidationResult(
            sourceCanonicalPath: sourceCanonical,
            targetCanonicalPath: targetCanonical,
            messages: messages
        )
    }
}
