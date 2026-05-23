import Foundation
import FloatingMacroCore

// MARK: - Usage

func printUsage() {
    let usage = """
    FloatingMacro CLI (fmcli)

    Usage:
      fmcli action key <combo>              Key Combo Dispatch (Example: "cmd+shift+4")
      fmcli action text <content>           Text injection
      fmcli action launch <target>          Launch App/URL/File
      fmcli action terminal [options]       Terminal launch + command injection
        --app <name>                          Terminal app (default: Terminal)
        --command <cmd>                       Execution Command
        --no-execute                          Press Enter
      fmcli preset list                     Preset List
      fmcli preset run <preset> <button-id> Run Button
      fmcli token show                      Display Control API Token
      fmcli token reset                     Regenerate Token
      fmcli permissions check               Permission Check
      fmcli config path                     Display configuration file path
      fmcli config init                     Initialize configuration file
      fmcli log path                        Display log file path
      fmcli log tail [--level LEVEL] [--since DURATION] [--limit N] [--json]
                                            View recent logs

    Global options (action/preset Anywhere:
      --log-level <debug|info|warn|error>   Log minimum level (default: info)
      Can also specify via environment variable FLOATINGMACRO_LOG_LEVEL

    Environment Variables:
      FLOATINGMACRO_CONFIG_DIR  Overwrite settings directory
      FLOATINGMACRO_LOG_LEVEL   --log-level equivalent to
    """
    print(usage)
}

// MARK: - Logging setup

/// Parse --log-level from args (consuming them) and set up the global logger.
/// Also returns the resolved log file URL.
@discardableResult
func configureLogging(args: inout [String]) -> URL {
    // Extraction and removal from args
    var level: LogLevel = .info
    if let env = ProcessInfo.processInfo.environment["FLOATINGMACRO_LOG_LEVEL"],
       let parsed = LogLevel.parse(env) {
        level = parsed
    }

    var filtered: [String] = []
    var iter = args.makeIterator()
    while let a = iter.next() {
        if a == "--log-level" {
            if let v = iter.next(), let parsed = LogLevel.parse(v) {
                level = parsed
            }
        } else {
            filtered.append(a)
        }
    }
    args = filtered

    // Determine log file path
    // Write to the workspace (current directory) in debug mode.
    // To allow direct reference, it is written in the Library for normal mode.
    let logsDir: URL
    if level == .debug {
        logsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("logs")
    } else {
        logsDir = ConfigLoader.defaultBaseURL.appendingPathComponent("logs")
    }
    let logURL = logsDir.appendingPathComponent("floatingmacro.log")

    // Composite of File and Console
    let file: FMLogger
    do {
        file = try FileLogWriter(url: logURL, minimumLevel: level)
    } catch {
        // When a file cannot be opened, only output to the console.
        FileHandle.standardError.write(
            Data("fmcli: log file init failed: \(error)\n".utf8))
        file = NullLogger()
    }
    let console = ConsoleLogWriter(minimumLevel: level)
    LoggerContext.shared = ComposedLogger([file, console])

    return logURL
}

// MARK: - Action Execution

func executeAction(_ action: Action) async throws {
    switch action {
    case .key(let combo):
        let kc = try KeyCombo.parse(combo)
        try KeyActionExecutor.execute(kc)

    case .text(let content, let pasteDelayMs, let restoreClipboard, let appendMode):
        try TextActionExecutor.execute(
            content: content,
            pasteDelayMs: pasteDelayMs,
            restoreClipboard: restoreClipboard,
            appendMode: appendMode
        )

    case .launch(let target):
        try LaunchActionExecutor.execute(target: target)

    case .terminal(let app, let command, let newWindow, let execute, let profile):
        try TerminalActionExecutor.execute(
            app: app, command: command, newWindow: newWindow,
            execute: execute, profile: profile
        )

    case .delay(let ms):
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)

    case .macro(let actions, let stopOnError):
        try await MacroRunner.run(actions: actions, stopOnError: stopOnError)
    }
}

// MARK: - `log tail` helpers

/// Parse duration strings like "30s", "5m", "2h", "1d" into TimeInterval seconds.
func parseDuration(_ s: String) -> TimeInterval? {
    guard !s.isEmpty else { return nil }
    let suffix = s.last!
    let body = s.dropLast()
    guard let n = Double(body) else { return nil }
    switch suffix {
    case "s": return n
    case "m": return n * 60
    case "h": return n * 3600
    case "d": return n * 86400
    default:
        // Bare number = seconds
        if let all = Double(s) { return all }
        return nil
    }
}

func handleLogTail(args: [String], logURL: URL) -> Int32 {
    var level: LogLevel? = nil
    var since: TimeInterval? = nil
    var limit: Int? = nil
    var json = false

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--level":
            if i + 1 < args.count, let parsed = LogLevel.parse(args[i+1]) {
                level = parsed; i += 2
            } else {
                print("Error: --level with debug|info|warn|error Specify")
                return 1
            }
        case "--since":
            if i + 1 < args.count, let secs = parseDuration(args[i+1]) {
                since = secs; i += 2
            } else {
                print("Error: --since Specify time like 30s / 5m / 2h / 1d etc.")
                return 1
            }
        case "--limit":
            if i + 1 < args.count, let n = Int(args[i+1]), n > 0 {
                limit = n; i += 2
            } else {
                print("Error: --limit Please specify a positive integer")
                return 1
            }
        case "--json":
            json = true; i += 1
        default:
            print("Error: Unknown option: \(args[i])")
            return 1
        }
    }

    guard FileManager.default.fileExists(atPath: logURL.path) else {
        print("No log file: \(logURL.path)")
        return 0
    }

    // Read the entire file line by line. For very large files, use the SPEC 10MB rotation.
    // Practical upper limit is several thousand to tens of thousands lines due to being protected.
    guard let raw = try? String(contentsOf: logURL, encoding: .utf8) else {
        print("Error: Cannot read log file: \(logURL.path)")
        return 1
    }

    let lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

    let cutoff = since.map { Date().addingTimeInterval(-$0) }

    var matched: [(line: String, event: LogEvent)] = []
    for line in lines {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder.fmLogDecoder.decode(LogEvent.self, from: data)
        else { continue }

        if let level = level, event.level < level { continue }
        if let cutoff = cutoff, event.timestamp < cutoff { continue }
        matched.append((line, event))
    }

    if let limit = limit, matched.count > limit {
        matched = Array(matched.suffix(limit))
    }

    for (rawLine, event) in matched {
        if json {
            print(rawLine)
        } else {
            print(ConsoleLogWriter.formatLine(event))
        }
    }

    return 0
}

// MARK: - Main

var cliArgs = Array(CommandLine.arguments.dropFirst())

// Log level / logger destination to confirm (LoggerContext.shared will be enabled for all subsequent calls thereafter).
let resolvedLogURL = configureLogging(args: &cliArgs)

guard !cliArgs.isEmpty else {
    printUsage()
    exit(0)
}

switch cliArgs[0] {
case "action":
    guard cliArgs.count >= 2 else {
        print("Error: Please specify an action type.")
        printUsage()
        exit(1)
    }

    let actionType = cliArgs[1]
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    Task {
        do {
            switch actionType {
            case "key":
                guard cliArgs.count >= 3 else {
                    print("Error: Please specify a combo string (e.g., cmd+v)")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.key(combo: cliArgs[2]))
                print("✓ Key Press:
``` \(cliArgs[2])")

            case "text":
                guard cliArgs.count >= 3 else {
                    print("Error: Please specify text.")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.text(content: cliArgs[2], pasteDelayMs: 120, restoreClipboard: true, appendMode: false))
                print("✓ Text injection complete")

            case "launch":
                guard cliArgs.count >= 3 else {
                    print("Error: Please specify a target to launch.")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.launch(target: cliArgs[2]))
                print("✓ Launch: \(cliArgs[2])")

            case "terminal":
                var app = "Terminal"
                var command = ""
                var execute = true
                var i = 2
                while i < cliArgs.count {
                    switch cliArgs[i] {
                    case "--app":
                        i += 1; if i < cliArgs.count { app = cliArgs[i] }
                    case "--command":
                        i += 1; if i < cliArgs.count { command = cliArgs[i] }
                    case "--no-execute":
                        execute = false
                    default:
                        if command.isEmpty { command = cliArgs[i] }
                    }
                    i += 1
                }
                guard !command.isEmpty else {
                    print("Error: --command Please specify: Please specify:")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.terminal(app: app, command: command, newWindow: true, execute: execute, profile: nil))
                print("✓ Terminal: \(app) → \(command)")

            default:
                print("Error: Unknown action type: \(actionType)")
                printUsage()
                exitCode = 1
            }
        } catch {
            print("Error: \(error)")
            exitCode = 1
        }
        LoggerContext.shared.flush()
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)

case "preset":
    guard cliArgs.count >= 2 else {
        print("Error: Please specify a subcommand (list/run).")
        exit(1)
    }

    switch cliArgs[1] {
    case "list":
        do {
            let loader = ConfigLoader()
            let presets = try loader.listPresets()
            if presets.isEmpty {
                print("Preset not found.")
                print("Settings Directory: \(ConfigLoader.defaultBaseURL.path)")
            } else {
                let config = try? loader.loadAppConfig()
                for name in presets {
                    let active = (config?.activePreset == name) ? " (Active" : ""
                    print("  \(name)\(active)")
                }
            }
        } catch {
            print("Error: \(error)")
            exit(1)
        }

    case "run":
        guard cliArgs.count >= 4 else {
            print("Error: fmcli preset run <preset> <button-id>")
            exit(1)
        }
        let presetName = cliArgs[2]
        let buttonId = cliArgs[3]
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0
        Task {
            do {
                let loader = ConfigLoader()
                guard let button = try loader.findButton(presetName: presetName, buttonId: buttonId) else {
                    print("Error: Button '\(buttonId)' Preset not found \(presetName))")
                    exitCode = 1
                    semaphore.signal()
                    return
                }
                try await executeAction(button.action)
                print("✓ Execution Complete: \(button.label)")
            } catch {
                print("Error: \(error)")
                exitCode = 1
            }
            LoggerContext.shared.flush()
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)

    default:
        print("Error: Unknown subcommand: \(cliArgs[1])")
        exit(1)
    }

case "permissions":
    if cliArgs.count >= 2 && cliArgs[1] == "check" {
        let accessible = AccessibilityChecker.isTrusted()
        if accessible {
            print("✓ Accessibility Permission: Granted")
        } else {
            print("✗ Accessibility Permission: Not Granted")
            print("  Allow in System Settings → Privacy and Security → Accessibility")
        }
    } else {
        print("Error: fmcli permissions check")
        exit(1)
    }

case "config":
    if cliArgs.count >= 2 && cliArgs[1] == "path" {
        print(ConfigLoader.defaultBaseURL.path)
    } else if cliArgs.count >= 2 && cliArgs[1] == "init" {
        do {
            let writer = ConfigWriter()
            try writer.writeDefaultConfigIfNeeded()
            print("✓ Initialized configuration file: \(ConfigLoader.defaultBaseURL.path)")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    } else {
        print("Error: fmcli config path / fmcli config init")
        exit(1)
    }

case "token":
    guard cliArgs.count >= 2 else {
        print("Error: fmcli token (show) | reset)")
        exit(1)
    }
    switch cliArgs[1] {
    case "show":
        do {
            let token = try TokenStore.loadOrCreate()
            print(token)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    case "reset":
        do {
            try TokenStore.delete()
            let token = try TokenStore.loadOrCreate()
            print("New token: \(token)")
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    default:
        print("Error: Unknown subcommand: \(cliArgs[1])")
        exit(1)
    }

case "log":
    guard cliArgs.count >= 2 else {
        print("Error: fmcli log (path) | tail [options])")
        exit(1)
    }
    switch cliArgs[1] {
    case "path":
        print(resolvedLogURL.path)
    case "tail":
        let tailArgs = Array(cliArgs.dropFirst(2))
        let code = handleLogTail(args: tailArgs, logURL: resolvedLogURL)
        exit(code)
    default:
        print("Error: Unknown subcommand: \(cliArgs[1])")
        exit(1)
    }

case "help", "--help", "-h":
    printUsage()

default:
    print("Error: Unknown command: \(cliArgs[0])")
    printUsage()
    exit(1)
}
