import Foundation
import FloatingMacroCore

// MARK: - Usage

func printUsage() {
    let usage = """
    FloatingMacro CLI (fmcli)

    Usage:
      fmcli action key <combo>              キーコンボ送出 (例: "cmd+shift+4")
      fmcli action text <content>           テキスト注入
      fmcli action launch <target>          アプリ/URL/ファイル起動
      fmcli action terminal [options]       ターミナル起動 + コマンド投入
        --app <name>                          ターミナルアプリ (既定: Terminal)
        --command <cmd>                       実行コマンド
        --no-execute                          入力のみ (Enter しない)
      fmcli preset list                     プリセット一覧
      fmcli preset run <preset> <button-id> ボタン実行
      fmcli token show                      制御 API トークンを表示
      fmcli token reset                     トークンを再生成
      fmcli permissions check               権限チェック
      fmcli config path                     設定ファイルパス表示
      fmcli config init                     設定ファイルを初期化
      fmcli log path                        ログファイルパス表示
      fmcli log tail [--level LEVEL] [--since DURATION] [--limit N] [--json]
                                            最近のログを閲覧

    Global options (action/preset のどこでも指定可):
      --log-level <debug|info|warn|error>   ログ最低レベル (既定: info)
      環境変数 FLOATINGMACRO_LOG_LEVEL でも指定可

    環境変数:
      FLOATINGMACRO_CONFIG_DIR  設定ディレクトリを上書き
      FLOATINGMACRO_LOG_LEVEL   --log-level と同等
    """
    print(usage)
}

// MARK: - Logging setup

/// Parse --log-level from args (consuming them) and set up the global logger.
/// Also returns the resolved log file URL.
@discardableResult
func configureLogging(args: inout [String]) -> URL {
    // --log-level OPTION の抽出と args からの除去
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

    // ログファイルパスを決定
    // デバッグモード時はワークスペース (カレントディレクトリ) に書く。
    // AI が直接参照できるようにするため。通常モードは Library に書く。
    let logsDir: URL
    if level == .debug {
        logsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("logs")
    } else {
        logsDir = ConfigLoader.defaultBaseURL.appendingPathComponent("logs")
    }
    let logURL = logsDir.appendingPathComponent("floatingmacro.log")

    // File + Console のコンポジット
    let file: FMLogger
    do {
        file = try FileLogWriter(url: logURL, minimumLevel: level)
    } catch {
        // ファイルが開けないときはコンソールだけに退行
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

    case .text(let content, let pasteDelayMs, let restoreClipboard):
        try TextActionExecutor.execute(
            content: content,
            pasteDelayMs: pasteDelayMs,
            restoreClipboard: restoreClipboard
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
                print("エラー: --level には debug|info|warn|error を指定")
                return 1
            }
        case "--since":
            if i + 1 < args.count, let secs = parseDuration(args[i+1]) {
                since = secs; i += 2
            } else {
                print("エラー: --since には 30s / 5m / 2h / 1d などを指定")
                return 1
            }
        case "--limit":
            if i + 1 < args.count, let n = Int(args[i+1]), n > 0 {
                limit = n; i += 2
            } else {
                print("エラー: --limit には正の整数を指定")
                return 1
            }
        case "--json":
            json = true; i += 1
        default:
            print("エラー: 不明なオプション: \(args[i])")
            return 1
        }
    }

    guard FileManager.default.fileExists(atPath: logURL.path) else {
        print("ログファイルがありません: \(logURL.path)")
        return 0
    }

    // ファイル全体を行単位で読む。巨大な場合は SPEC の 10MB ローテーションに
    // 守られているため現実的な上限は数千〜数万行程度。
    guard let raw = try? String(contentsOf: logURL, encoding: .utf8) else {
        print("エラー: ログファイルが読めません: \(logURL.path)")
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

// 1. ログレベル/ロガー先に確定(これ以降のあらゆる呼び出しで LoggerContext.shared が有効になる)
let resolvedLogURL = configureLogging(args: &cliArgs)

guard !cliArgs.isEmpty else {
    printUsage()
    exit(0)
}

switch cliArgs[0] {
case "action":
    guard cliArgs.count >= 2 else {
        print("エラー: アクション種別を指定してください")
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
                    print("エラー: コンボ文字列を指定してください (例: cmd+v)")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.key(combo: cliArgs[2]))
                print("✓ キー送出: \(cliArgs[2])")

            case "text":
                guard cliArgs.count >= 3 else {
                    print("エラー: テキストを指定してください")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.text(content: cliArgs[2], pasteDelayMs: 120, restoreClipboard: true))
                print("✓ テキスト注入完了")

            case "launch":
                guard cliArgs.count >= 3 else {
                    print("エラー: 起動対象を指定してください")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.launch(target: cliArgs[2]))
                print("✓ 起動: \(cliArgs[2])")

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
                    print("エラー: --command を指定してください")
                    exitCode = 1; semaphore.signal(); return
                }
                try await executeAction(.terminal(app: app, command: command, newWindow: true, execute: execute, profile: nil))
                print("✓ ターミナル: \(app) → \(command)")

            default:
                print("エラー: 不明なアクション種別: \(actionType)")
                printUsage()
                exitCode = 1
            }
        } catch {
            print("エラー: \(error)")
            exitCode = 1
        }
        LoggerContext.shared.flush()
        semaphore.signal()
    }
    semaphore.wait()
    exit(exitCode)

case "preset":
    guard cliArgs.count >= 2 else {
        print("エラー: サブコマンドを指定してください (list / run)")
        exit(1)
    }

    switch cliArgs[1] {
    case "list":
        do {
            let loader = ConfigLoader()
            let presets = try loader.listPresets()
            if presets.isEmpty {
                print("プリセットが見つかりません。")
                print("設定ディレクトリ: \(ConfigLoader.defaultBaseURL.path)")
            } else {
                let config = try? loader.loadAppConfig()
                for name in presets {
                    let active = (config?.activePreset == name) ? " (アクティブ)" : ""
                    print("  \(name)\(active)")
                }
            }
        } catch {
            print("エラー: \(error)")
            exit(1)
        }

    case "run":
        guard cliArgs.count >= 4 else {
            print("エラー: fmcli preset run <preset> <button-id>")
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
                    print("エラー: ボタン '\(buttonId)' が見つかりません (プリセット: \(presetName))")
                    exitCode = 1
                    semaphore.signal()
                    return
                }
                try await executeAction(button.action)
                print("✓ 実行完了: \(button.label)")
            } catch {
                print("エラー: \(error)")
                exitCode = 1
            }
            LoggerContext.shared.flush()
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)

    default:
        print("エラー: 不明なサブコマンド: \(cliArgs[1])")
        exit(1)
    }

case "permissions":
    if cliArgs.count >= 2 && cliArgs[1] == "check" {
        let accessible = AccessibilityChecker.isTrusted()
        if accessible {
            print("✓ Accessibility 権限: 許可済み")
        } else {
            print("✗ Accessibility 権限: 未許可")
            print("  システム設定 → プライバシーとセキュリティ → アクセシビリティ で許可してください")
        }
    } else {
        print("エラー: fmcli permissions check")
        exit(1)
    }

case "config":
    if cliArgs.count >= 2 && cliArgs[1] == "path" {
        print(ConfigLoader.defaultBaseURL.path)
    } else if cliArgs.count >= 2 && cliArgs[1] == "init" {
        do {
            let writer = ConfigWriter()
            try writer.writeDefaultConfigIfNeeded()
            print("✓ 設定ファイルを初期化しました: \(ConfigLoader.defaultBaseURL.path)")
        } catch {
            print("エラー: \(error)")
            exit(1)
        }
    } else {
        print("エラー: fmcli config path / fmcli config init")
        exit(1)
    }

case "token":
    guard cliArgs.count >= 2 else {
        print("エラー: fmcli token (show | reset)")
        exit(1)
    }
    switch cliArgs[1] {
    case "show":
        do {
            let token = try TokenStore.loadOrCreate()
            print(token)
        } catch {
            fputs("エラー: \(error)\n", stderr)
            exit(1)
        }
    case "reset":
        do {
            try TokenStore.delete()
            let token = try TokenStore.loadOrCreate()
            print("New token: \(token)")
        } catch {
            fputs("エラー: \(error)\n", stderr)
            exit(1)
        }
    default:
        print("エラー: 不明なサブコマンド: \(cliArgs[1])")
        exit(1)
    }

case "log":
    guard cliArgs.count >= 2 else {
        print("エラー: fmcli log (path | tail [options])")
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
        print("エラー: 不明なサブコマンド: \(cliArgs[1])")
        exit(1)
    }

case "help", "--help", "-h":
    printUsage()

default:
    print("エラー: 不明なコマンド: \(cliArgs[0])")
    printUsage()
    exit(1)
}
