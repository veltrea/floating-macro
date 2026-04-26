import Foundation

/// Emits an A2A (Agent-to-Agent) compliant "Agent Card" document.
///
/// The Agent Card is what A2A clients (Google's a2a-sdk, other ADK-based
/// agents) fetch from `/.well-known/agent.json` to discover *who* this
/// server is and *what* it can do.
///
/// Reference: https://a2aproject.github.io/A2A/specification/
///
/// We intentionally map our existing `ToolCatalog` entries onto A2A's
/// `skills[]` array. Since we currently don't support Task streaming or
/// state history, those capability flags are false.
public enum AgentCard {

    public static func card(baseURL: String = "http://127.0.0.1:17430") -> [String: Any] {
        return [
            "name":        SystemPrompt.product,
            "description": "FloatingMacro — a macOS floating macro launcher with an HTTP control surface designed for AI agents to observe, configure, and drive the app as first-class users.",
            "url":         baseURL,
            "version":     SystemPrompt.version,
            "protocolVersion": "0.1",
            "capabilities": [
                "streaming":              false,
                "pushNotifications":      false,
                "stateTransitionHistory": false,
            ] as [String: Any],
            "defaultInputModes":  ["application/json", "text"],
            "defaultOutputModes": ["application/json", "text"],
            "skills":             skills(),
            "provider": [
                "organization": "FloatingMacro",
                "url":          "https://github.com/veltrea/floatingmacro",
            ] as [String: Any],
            "documentationUrl":   "\(baseURL)/manifest",
            // Non-standard extensions that help non-A2A clients discover
            // richer views of the same surface.
            "x-extensions": [
                "openapi":      "\(baseURL)/openapi.json",
                "mcp-endpoint": "\(baseURL)/mcp",
                "manifest":     "\(baseURL)/manifest",
                "toolsCatalog": [
                    "mcp":       "\(baseURL)/tools?format=mcp",
                    "openai":    "\(baseURL)/tools?format=openai",
                    "anthropic": "\(baseURL)/tools?format=anthropic",
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    private static func skills() -> [[String: Any]] {
        return ToolCatalog.tools.map { tool in
            [
                "id":          tool.name,
                "name":        tool.name,
                "description": tool.description,
                "tags":        [tagFor(tool)],
                "inputModes":  ["application/json"],
                "outputModes": ["application/json"],
                "parameters":  tool.inputSchema,
                "examples":    examples(for: tool),
            ]
        }
    }

    private static func tagFor(_ tool: ToolDefinition) -> String {
        if tool.path.hasPrefix("/window") { return "window" }
        if tool.path.hasPrefix("/preset") { return "preset" }
        if tool.path.hasPrefix("/group")  { return "group" }
        if tool.path.hasPrefix("/button") { return "button" }
        if tool.path.hasPrefix("/log")    { return "observability" }
        if tool.path.hasPrefix("/icon")   { return "icon" }
        if tool.path.hasPrefix("/tools")  { return "discovery" }
        if tool.path == "/action"         { return "action" }
        return "misc"
    }

    /// A short natural-language example surfaced in the Agent Card so
    /// prompt-tuned clients can see canonical usage without reading
    /// descriptions.
    private static func examples(for tool: ToolDefinition) -> [String] {
        switch tool.name {
        case "help", "manifest":      return ["Re-read the manifest"]
        case "ping":                  return ["Check that the server is alive"]
        case "get_state":             return ["What preset is active right now?"]
        case "window_show":           return ["Show the floating panel"]
        case "window_hide":           return ["Hide the panel"]
        case "window_move":           return ["Move the panel to (100, 200)"]
        case "window_resize":         return ["Resize the panel to 250×400"]
        case "window_opacity":        return ["Set panel opacity to 0.5"]
        case "preset_switch":         return ["Switch to the 'writing' preset"]
        case "preset_create":         return ["Create a new preset called 'dev'"]
        case "button_add":            return ["Add a Slack launcher button"]
        case "button_update":         return ["Change button color to red"]
        case "run_action":            return ["Paste 'hello world' as text"]
        case "log_tail":              return ["Show warnings from the last 5 minutes"]
        case "icon_for_app":          return ["Fetch Safari's icon as PNG"]
        default:                      return []
        }
    }
}
