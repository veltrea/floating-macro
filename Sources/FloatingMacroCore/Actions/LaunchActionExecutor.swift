import Foundation

public enum LaunchActionExecutor {
    private static let category = "LaunchAction"
    public static var launcher: WorkspaceLauncherProtocol = SystemWorkspaceLauncher.shared
    public static var scriptRunner: AppleScriptRunnerProtocol = SystemAppleScriptRunner.shared

    public static func execute(target: String) throws {
        let log = LoggerContext.shared
        log.debug(category, "Resolving target", ["target": target])

        // 1. shell: prefix → run via /bin/sh
        if target.hasPrefix("shell:") {
            let command = String(target.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            log.info(category, "Running shell command", ["command": command])
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                log.error(category, "Shell command failed", [
                    "exitCode": String(process.terminationStatus),
                    "stderr":   stderr,
                ])
                throw ActionError.shellCommandFailed(exitCode: process.terminationStatus, stderr: stderr)
            }
            log.debug(category, "Shell command succeeded")
            return
        }

        // 2. URL schemes (http, https, custom schemes)
        if target.contains("://") {
            guard let url = URL(string: target) else {
                log.error(category, "Malformed URL", ["target": target])
                throw ActionError.urlSchemeUnhandled(target)
            }
            log.info(category, "Opening URL", ["scheme": url.scheme ?? "?"])
            do {
                try launcher.open(url: url)
            } catch {
                log.error(category, "URL open failed", [
                    "target": target,
                    "error":  String(describing: error),
                ])
                throw error
            }
            return
        }

        // 3. Bundle identifier (com.xxx.xxx)
        let bundleIdPattern = target.split(separator: ".").count >= 3
            && target.first?.isLetter == true
            && !target.hasPrefix("/")
            && !target.hasPrefix("~")
        if bundleIdPattern {
            log.info(category, "Launching bundle id", ["bundleId": target])
            do {
                try launcher.openApplication(bundleIdentifier: target)
            } catch {
                log.error(category, "Bundle launch failed", [
                    "bundleId": target,
                    "error":    String(describing: error),
                ])
                throw error
            }
            return
        }

        // 4. File path (absolute or ~/)
        let expandedPath: String
        if target.hasPrefix("~/") {
            expandedPath = NSString(string: target).expandingTildeInPath
        } else if target.hasPrefix("/") {
            expandedPath = target
        } else {
            log.error(category, "Unresolvable target", ["target": target])
            throw ActionError.launchTargetNotFound(target)
        }

        let url = URL(fileURLWithPath: expandedPath)
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            log.error(category, "Path does not exist", ["path": expandedPath])
            throw ActionError.launchTargetNotFound(target)
        }
        log.info(category, "Opening file path", ["path": expandedPath])
        do {
            try launcher.open(url: url)
        } catch {
            log.error(category, "File open failed", [
                "path":  expandedPath,
                "error": String(describing: error),
            ])
            throw error
        }
    }
}
