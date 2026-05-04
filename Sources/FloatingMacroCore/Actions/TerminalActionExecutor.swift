import Foundation

public enum TerminalActionExecutor {
    private static let category = "TerminalAction"
    public static var scriptRunner: AppleScriptRunnerProtocol = SystemAppleScriptRunner.shared
    public static var clipboard: ClipboardProtocol = SystemClipboard.shared
    public static var synthesizer: EventSynthesizerProtocol = CGEventSynthesizer.shared
    public static var launcher: WorkspaceLauncherProtocol = SystemWorkspaceLauncher.shared

    public static func execute(app: String, command: String, newWindow: Bool = true,
                               execute: Bool = true, profile: String? = nil) throws {
        let log = LoggerContext.shared
        log.info(category, "Dispatching terminal action", [
            "app":       app,
            "newWindow": String(newWindow),
            "execute":   String(execute),
            "profile":   profile ?? "<none>",
        ])

        let appLower = app.lowercased()

        do {
            switch appLower {
            case "terminal", "terminal.app":
                try executeViaTerminalApp(command: command, newWindow: newWindow)

            case "iterm", "iterm2", "iterm.app", "iterm2.app":
                try executeViaITerm(command: command, newWindow: newWindow, execute: execute, profile: profile)

            default:
                try executeViaGeneric(app: app, command: command, execute: execute)
            }
        } catch {
            log.error(category, "Terminal action failed", [
                "app":   app,
                "error": String(describing: error),
            ])
            throw error
        }
    }

    private static func executeViaTerminalApp(command: String, newWindow: Bool) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        if newWindow {
            script = """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        } else {
            script = """
            tell application "Terminal"
                activate
                if (count of windows) > 0 then
                    do script "\(escaped)" in front window
                else
                    do script "\(escaped)"
                end if
            end tell
            """
        }

        _ = try scriptRunner.run(script)
    }

    private static func executeViaITerm(command: String, newWindow: Bool,
                                        execute: Bool, profile: String?) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let profileClause: String
        if let profile = profile {
            profileClause = "with profile \"\(profile)\""
        } else {
            profileClause = ""
        }

        let writeCommand = execute ? "write text \"\(escaped)\"" : "write text \"\(escaped)\" without newline"

        let script: String
        if newWindow {
            script = """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile \(profileClause))
                tell current session of newWindow
                    \(writeCommand)
                end tell
            end tell
            """
        } else {
            script = """
            tell application "iTerm"
                activate
                tell current window
                    set newTab to (create tab with default profile \(profileClause))
                    tell current session of newTab
                        \(writeCommand)
                    end tell
                end tell
            end tell
            """
        }

        _ = try scriptRunner.run(script)
    }

    private static func executeViaGeneric(app: String, command: String, execute: Bool) throws {
        // Launch the app
        if app.hasPrefix("/") {
            try launcher.open(url: URL(fileURLWithPath: app))
        } else {
            let bundleId = "com.apple.\(app.lowercased())"
            do {
                try launcher.openApplication(bundleIdentifier: bundleId)
            } catch {
                // Try opening by name
                let appPath = "/Applications/\(app).app"
                if FileManager.default.fileExists(atPath: appPath) {
                    try launcher.open(url: URL(fileURLWithPath: appPath))
                } else {
                    throw ActionError.launchTargetNotFound(app)
                }
            }
        }

        // Wait for app to activate
        Thread.sleep(forTimeInterval: 1.0)

        // Paste command via clipboard
        let snapshot = clipboard.save()
        clipboard.setString(command)
        Thread.sleep(forTimeInterval: 0.01)

        let cmdV = try KeyCombo.parse("cmd+v")
        try synthesizer.postKeyEvent(keyCode: cmdV.keyCode, flags: cmdV.modifiers)
        Thread.sleep(forTimeInterval: 0.1)

        if execute {
            let enter = try KeyCombo.parse("enter")
            try synthesizer.postKeyEvent(keyCode: enter.keyCode, flags: enter.modifiers)
        }

        Thread.sleep(forTimeInterval: 0.1)
        clipboard.restore(snapshot)
    }
}
