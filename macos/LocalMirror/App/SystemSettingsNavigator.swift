import AppKit
import Foundation

enum SystemSettingsNavigator {
    static func openFullDiskAccess() {
        let modernURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        if let modernURL {
            NSWorkspace.shared.open(modernURL)
            return
        }

        let source = """
        tell application "System Settings"
            activate
            reveal anchor "Privacy_AllFiles" of pane id "com.apple.settings.PrivacySecurity.extension"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
