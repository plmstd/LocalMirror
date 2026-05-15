import Foundation

enum AppPaths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LocalMirror", isDirectory: true)
    }

    static var logsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    static var settingsURL: URL {
        applicationSupportDirectory.appendingPathComponent("settings.json")
    }

    static var pairsURL: URL {
        applicationSupportDirectory.appendingPathComponent("backup-pairs.json")
    }

    static var runHistoryURL: URL {
        applicationSupportDirectory.appendingPathComponent("run-history.json")
    }
}
