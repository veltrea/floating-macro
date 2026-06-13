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
    public static let version = "0.16.7"

    // MARK: - Prompt loading

    /// Loads all prompts from `agent_prompts.json` in the module bundle.
    /// Returns nil if the file is missing or malformed.
    private static var bundledJSON: [String: Any]? = {
        guard let url = Bundle.module.url(forResource: "agent_prompts",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict
    }()

    public static var greeting: String {
        bundledJSON?["normal"] as? String ?? fallbackGreeting
    }

    public static var testGreeting: String {
        bundledJSON?["test"] as? String ?? fallbackTestGreeting
    }

    public static var claudeCodeGreeting: String {
        bundledJSON?["claudeCode"] as? String ?? fallbackClaudeCodeGreeting
    }

    /// Connection prompt with placeholders replaced.
    public static func connectionPrompt(endpoint: String, token: String) -> String {
        let template = bundledJSON?["connectionPrompt"] as? String ?? fallbackConnectionPrompt
        return template
            .replacingOccurrences(of: "{{endpoint}}", with: endpoint)
            .replacingOccurrences(of: "{{token}}", with: token)
    }

    // MARK: - Fallbacks (used only when the JSON bundle is unavailable)

    private static let fallbackGreeting = """
    # FloatingMacro Welcome to the Control API

    You are **FloatingMacro** Connecting to control API...
    Bearer authentication required for operation endpoints. Token can be obtained from either of the following:
        cat ~/Library/Application\\ Support/FloatingMacro/control_api_token
        security find-generic-password -s FloatingMacro -a ControlAPIToken -w
    Make sure to attach that token to the Authorization: Bearer header always `/tools/call`
    Call the tool via the endpoint (direct calls to individual endpoints are deprecated).
    First `GET /state` and `GET /preset/current` Please understand the current situation before starting the work.
    """

    private static let fallbackTestGreeting = """
    # FloatingMacro Test Agent Mode

    Verify that all features work as specified and find any specification bugs.
    First read the log, generate test cases, and output the test completion report.
    """

    private static let fallbackClaudeCodeGreeting = """
    # FloatingMacro — Claude Code Assistant Mode

    Claude Code Assists with coding sessions.
    Switches between terminal expansion, prompt injection, and work scene scenarios.
    """

    private static let fallbackConnectionPrompt = """
    You are an AI that can control FloatingMacro running on macOS.

    Endpoint: {{endpoint}}
    Auth token: {{token}}

    First, run `curl -s {{endpoint}}/manifest | jq` to fetch the app's \
    self-introduction and full tool definitions (this endpoint requires no auth).

    Principles:
    - All tool calls go through POST /tools/call
    - Do not hit individual endpoints directly
    - Attach Authorization: Bearer header with the token

    Before starting work, get the current state:
    - GET /state
    - GET /preset/current
    """

    // MARK: - Shared

    private static let fallbackQuickStart: [String] = [
        "GET /manifest  — read this first (you are reading it now)",
        "GET /state     — current state snapshot",
        "GET /tools     — full tool catalog",
        "POST /tools/call {\"name\":\"<tool>\",\"arguments\":{...}} — execute a tool",
        "GET /log/tail?since=5m  — check execution results",
        "POST /tools/call {\"name\":\"help\"}  — reload this guide",
    ]

    /// Quick-start checklist surfaced separately so a thin client can render
    /// it without parsing the full greeting.
    public static var quickStart: [String] {
        (bundledJSON?["quickStart"] as? [String]) ?? fallbackQuickStart
    }

    /// Top-level endpoints. AI clients use this as a table of contents.
    public static let endpoints: [[String: String]] = [
        ["method": "GET",  "path": "/manifest",    "desc": "This self-introduction (alias: /help)\nThis introduction (/help alias)"],
        ["method": "GET",  "path": "/help",        "desc": "Alias of /manifest\n/manifest Alias"],
        ["method": "GET",  "path": "/tools",       "desc": "Tool catalog (?format=mcp|openai|anthropic)\nTool Catalog (?format=mcp|openai|anthropic)"],
        ["method": "POST", "path": "/tools/call",  "desc": "Dispatch any tool by name\nRun tool with name specification"],
        ["method": "GET",  "path": "/state",       "desc": "App state snapshot\nApp State Snapshot"],
        ["method": "GET",  "path": "/log/tail",    "desc": "Structured log events\nStructured Log Event"],
        ["method": "GET",  "path": "/ping",        "desc": "Liveness probe\nSurvival Check"],
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
                "description": "Call this tool any time to re-read the manifest.\nYou can call this tool anytime to reload the manifest.",
            ] as [String: Any],
            "tools": ToolCatalog.render(dialect: .mcp)["tools"] as Any,
        ]
    }
}
