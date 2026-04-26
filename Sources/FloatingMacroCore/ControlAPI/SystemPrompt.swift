import Foundation

/// The "front door" handed to any AI agent that connects to the control API.
/// Think of it as FloatingMacro's equivalent of MCP's `initialize` response:
/// a single JSON payload that explains what the app is, how the agent is
/// expected to behave, which endpoints exist, and what every tool does.
///
/// Prompt text is loaded from `agent_prompts.json` bundled with the target.
/// Edit that file to update prompts without recompiling. Hardcoded strings
/// below serve as compile-time fallbacks only.
///
/// AI clients should hit `GET /manifest` (alias `GET /help`) **before**
/// doing anything else, and call the `help` tool any time they want to
/// re-ground themselves later.
public enum SystemPrompt {

    /// Short machine-readable identity card.
    public static let product = "FloatingMacro"
    public static let version = "0.1"

    // MARK: - Prompt loading

    /// Loads all prompts from `agent_prompts.json` in the module bundle.
    /// Returns nil if the file is missing or malformed.
    private static var bundledPrompts: [String: String]? = {
        guard let url = Bundle.module.url(forResource: "agent_prompts",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        return dict
    }()

    public static var greeting: String {
        bundledPrompts?["normal"] ?? fallbackGreeting
    }

    public static var testGreeting: String {
        bundledPrompts?["test"] ?? fallbackTestGreeting
    }

    public static var claudeCodeGreeting: String {
        bundledPrompts?["claudeCode"] ?? fallbackClaudeCodeGreeting
    }

    // MARK: - Fallbacks (used only when the JSON bundle is unavailable)

    private static let fallbackGreeting = """
    # FloatingMacro 制御 API へようこそ

    あなたは **FloatingMacro** の制御 API に接続しています。
    ユーザーと対話しながら、このAPIを通じてアプリを操作・設定できます。
    まず `GET /state` で現在の状態を把握してから作業を始めてください。
    """

    private static let fallbackTestGreeting = """
    # FloatingMacro テストエージェントモード

    すべての機能が仕様通りに動くことを確認し、仕様バグも発見する。
    まずログを読み、テストケースを生成し、テスト完了レポートを出力する。
    """

    private static let fallbackClaudeCodeGreeting = """
    # FloatingMacro — Claude Code アシスタントモード

    Claude Code のコーディングセッションを補助する。
    ターミナル展開・プロンプト投入・作業シーン切替を担う。
    """

    // MARK: - Shared

    /// Quick-start checklist surfaced separately so a thin client can render
    /// it without parsing the full greeting.
    public static let quickStart: [String] = [
        "GET /manifest  — これを最初に読む (you are reading it now)",
        "GET /state     — 現状スナップショット",
        "GET /tools     — 全ツール定義",
        "POST /tools/call {\"name\":\"<tool>\",\"arguments\":{...}} — ツール実行",
        "GET /log/tail?since=5m  — 実行結果の確認",
        "POST /tools/call {\"name\":\"help\"}  — この案内を再読み込み",
    ]

    /// Top-level endpoints. AI clients use this as a table of contents.
    public static let endpoints: [[String: String]] = [
        ["method": "GET",  "path": "/manifest",    "desc": "This self-introduction (alias: /help)"],
        ["method": "GET",  "path": "/help",        "desc": "Alias of /manifest"],
        ["method": "GET",  "path": "/tools",       "desc": "Tool catalog (?format=mcp|openai|anthropic)"],
        ["method": "POST", "path": "/tools/call",  "desc": "Dispatch any tool by name"],
        ["method": "GET",  "path": "/state",       "desc": "App state snapshot"],
        ["method": "GET",  "path": "/log/tail",    "desc": "Structured log events"],
        ["method": "GET",  "path": "/ping",        "desc": "Liveness probe"],
    ]

    /// The full envelope returned from GET /manifest and GET /help.
    /// Includes the system prompt, quick start, endpoint map, and the entire
    /// tool catalog in MCP dialect so a client only needs ONE round trip to
    /// fully bootstrap.
    ///
    /// - Parameter agentMode: Selects which system prompt to embed.
    public static func manifest(agentMode: AgentMode = .normal) -> [String: Any] {
        let prompt: String
        switch agentMode {
        case .normal:     prompt = greeting
        case .test:       prompt = testGreeting
        case .claudeCode: prompt = claudeCodeGreeting
        }
        return [
            "product":       product,
            "version":       version,
            "agentMode":     agentMode.rawValue,
            "systemPrompt":  prompt,
            "quickStart":    quickStart,
            "endpoints":     endpoints,
            "dialects": [
                "mcp":       "/tools?format=mcp",
                "openai":    "/tools?format=openai",
                "anthropic": "/tools?format=anthropic",
            ] as [String: String],
            "helpTool": [
                "call": [
                    "name": "help",
                    "arguments": [String: Any]()
                ] as [String: Any],
                "description": "Call this tool any time to re-read the manifest.",
            ] as [String: Any],
            "tools": ToolCatalog.render(dialect: .mcp)["tools"] as Any,
        ]
    }
}
