import Foundation

/// A single tool exposed by the control API, in the same spirit as MCP's
/// `tools/list` or OpenAI / Anthropic function-calling definitions.
///
/// We model the tool once and emit it in whichever dialect the caller asks
/// for. Each tool records the underlying HTTP method + path so the
/// server's `/tools/call` endpoint can dispatch uniformly.
public struct ToolDefinition: Equatable {
    public let name: String
    public let description: String
    public let method: String
    public let path: String
    /// JSON Schema for inputs. Stored as a JSON-serializable dictionary so
    /// it can be handed verbatim to any dialect.
    public let inputSchema: [String: Any]

    public init(name: String,
                description: String,
                method: String,
                path: String,
                inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.method = method
        self.path = path
        self.inputSchema = inputSchema
    }

    public static func == (lhs: ToolDefinition, rhs: ToolDefinition) -> Bool {
        lhs.name == rhs.name && lhs.method == rhs.method && lhs.path == rhs.path
    }
}

/// Centralized catalog of every tool exposed by the control API.
/// When you add a new endpoint, add it here too so AI clients discover it
/// automatically via GET /tools.
public enum ToolCatalog {

    public static let tools: [ToolDefinition] = [
        // MARK: - Self-introduction
        .init(name: "help",
              description: "Re-read the FloatingMacro manifest: system prompt, endpoint map, quick-start guide, and full tool catalog. Call this any time you are unsure what to do. Alias of GET /manifest.",
              method: "GET", path: "/manifest",
              inputSchema: emptyObject()),

        .init(name: "manifest",
              description: "Same as 'help' — returns the full self-introduction envelope.",
              method: "GET", path: "/manifest",
              inputSchema: emptyObject()),

        // MARK: - Health / state
        .init(name: "ping",
              description: "Health check. Returns {ok: true, product: \"FloatingMacro\"}.",
              method: "GET", path: "/ping",
              inputSchema: emptyObject()),

        .init(name: "get_state",
              description: "Snapshot of the app: panel visibility, active preset, window geometry, and last error message.",
              method: "GET", path: "/state",
              inputSchema: emptyObject()),

        // MARK: - Window
        .init(name: "window_show",
              description: "Bring the floating panel to the front.",
              method: "POST", path: "/window/show",
              inputSchema: emptyObject()),

        .init(name: "window_hide",
              description: "Hide the floating panel (does not quit the app).",
              method: "POST", path: "/window/hide",
              inputSchema: emptyObject()),

        .init(name: "window_toggle",
              description: "Toggle the floating panel's visibility.",
              method: "POST", path: "/window/toggle",
              inputSchema: emptyObject()),

        .init(name: "window_opacity",
              description: "Set panel opacity. Clamped to [0.25, 1.0].",
              method: "POST", path: "/window/opacity",
              inputSchema: object([
                  "value": numberSchema(minimum: 0.25, maximum: 1.0)
              ], required: ["value"])),

        .init(name: "window_move",
              description: "Move the panel to absolute screen coordinates (origin bottom-left per AppKit convention).",
              method: "POST", path: "/window/move",
              inputSchema: object([
                  "x": numberSchema(),
                  "y": numberSchema(),
              ], required: ["x", "y"])),

        .init(name: "window_resize",
              description: "Resize the panel. Width must be >= 120, height >= 80.",
              method: "POST", path: "/window/resize",
              inputSchema: object([
                  "width":  numberSchema(minimum: 120),
                  "height": numberSchema(minimum: 80),
              ], required: ["width", "height"])),

        // MARK: - Preset
        .init(name: "preset_list",
              description: "List all preset names with an active flag.",
              method: "GET", path: "/preset/list",
              inputSchema: emptyObject()),

        .init(name: "preset_current",
              description: "Full JSON of the currently-active preset (including all groups and buttons).",
              method: "GET", path: "/preset/current",
              inputSchema: emptyObject()),

        .init(name: "preset_switch",
              description: "Switch the active preset by name.",
              method: "POST", path: "/preset/switch",
              inputSchema: object([
                  "name": stringSchema()
              ], required: ["name"])),

        .init(name: "preset_reload",
              description: "Re-read preset files from disk (use after editing JSON directly).",
              method: "POST", path: "/preset/reload",
              inputSchema: emptyObject()),

        .init(name: "preset_create",
              description: "Create a new empty preset file.",
              method: "POST", path: "/preset/create",
              inputSchema: object([
                  "name":        stringSchema(description: "File name (no .json). Must be unique."),
                  "displayName": stringSchema(description: "Human-facing label shown in menus."),
              ], required: ["name"])),

        .init(name: "preset_rename",
              description: "Update a preset's displayName. The file name is immutable.",
              method: "POST", path: "/preset/rename",
              inputSchema: object([
                  "name":        stringSchema(),
                  "displayName": stringSchema(),
              ], required: ["name", "displayName"])),

        .init(name: "preset_delete",
              description: "Delete a preset file. If deleted preset was active, the app falls back to 'default'.",
              method: "POST", path: "/preset/delete",
              inputSchema: object([
                  "name": stringSchema()
              ], required: ["name"])),

        // MARK: - Groups
        .init(name: "group_add",
              description: "Append a new button group to the active preset.",
              method: "POST", path: "/group/add",
              inputSchema: object([
                  "id":        stringSchema(description: "Unique id within the preset."),
                  "label":     stringSchema(description: "Visible header text."),
                  "collapsed": boolSchema(description: "Start collapsed. Default false."),
              ], required: ["id", "label"])),

        .init(name: "group_update",
              description: "Patch a group's label, icon, colors, tooltip, and/or collapsed state.",
              method: "POST", path: "/group/update",
              inputSchema: object([
                  "id":              stringSchema(),
                  "label":           stringSchema(),
                  "icon":            stringSchema(),
                  "iconText":        stringSchema(),
                  "backgroundColor": stringSchema(),
                  "textColor":       stringSchema(),
                  "tooltip":         stringSchema(),
                  "collapsed":       boolSchema(),
              ], required: ["id"])),

        .init(name: "group_delete",
              description: "Delete a group and all its buttons from the active preset.",
              method: "POST", path: "/group/delete",
              inputSchema: object([
                  "id": stringSchema()
              ], required: ["id"])),

        // MARK: - Buttons
        .init(name: "button_add",
              description: "Append a button to a group in the active preset. The button field is a full ButtonDefinition JSON.",
              method: "POST", path: "/button/add",
              inputSchema: object([
                  "groupId": stringSchema(),
                  "button":  buttonDefinitionSchema(),
              ], required: ["groupId", "button"])),

        .init(name: "button_update",
              description: "Partial-patch a button. Any omitted field is left unchanged; a field explicitly set to null is cleared.",
              method: "POST", path: "/button/update",
              inputSchema: buttonUpdateSchema()),

        .init(name: "button_delete",
              description: "Delete a button from the active preset by id.",
              method: "POST", path: "/button/delete",
              inputSchema: object([
                  "id": stringSchema()
              ], required: ["id"])),

        .init(name: "button_reorder",
              description: "Reorder buttons within a single group.",
              method: "POST", path: "/button/reorder",
              inputSchema: object([
                  "groupId": stringSchema(),
                  "ids":     ["type": "array", "items": ["type": "string"]] as [String: Any],
              ], required: ["groupId", "ids"])),

        .init(name: "button_move",
              description: "Move a button to another group at an optional position.",
              method: "POST", path: "/button/move",
              inputSchema: object([
                  "id":         stringSchema(),
                  "toGroupId":  stringSchema(),
                  "position":   intSchema(description: "0-based insertion index. If omitted, appended."),
              ], required: ["id", "toGroupId"])),

        // MARK: - Action execution
        .init(name: "run_action",
              description: "Execute an Action immediately (202 accepted, result appears in logs). The body IS a full Action JSON.",
              method: "POST", path: "/action",
              inputSchema: actionSchema()),

        // MARK: - Observation
        .init(name: "log_tail",
              description: "Return recent log events. Query params: level, since, limit, json. All events are structured with category, timestamp, and metadata.",
              method: "GET", path: "/log/tail",
              inputSchema: object([
                  "level":  stringSchema(description: "debug | info | warn | error"),
                  "since":  stringSchema(description: "Duration like '5m', '2h', '1d'"),
                  "limit":  intSchema(description: "Max events to return"),
              ])),

        .init(name: "icon_for_app",
              description: "Fetch the macOS icon for an app as a base64 PNG. Provide either bundleId (preferred) or path.",
              method: "GET", path: "/icon/for-app",
              inputSchema: object([
                  "bundleId": stringSchema(description: "e.g. com.apple.Safari"),
                  "path":     stringSchema(description: "Absolute path to an .app bundle"),
              ])),

        // MARK: - Settings window
        .init(name: "settings_open",
              description: "Open the Settings window.",
              method: "POST", path: "/settings/open",
              inputSchema: emptyObject()),

        .init(name: "settings_close",
              description: "Close the Settings window.",
              method: "POST", path: "/settings/close",
              inputSchema: emptyObject()),

        .init(name: "settings_open_sf_picker",
              description: "Open the Settings window (if not already open) and show the SF Symbol picker sheet. Convenience for AI screenshot workflows.",
              method: "POST", path: "/settings/open-sf-picker",
              inputSchema: emptyObject()),

        // MARK: - Settings window — test automation
        .init(name: "settings_select_button",
              description: "Select a button in the Settings window by id. Opens Settings if not already open.",
              method: "POST", path: "/settings/select-button",
              inputSchema: object(["id": stringSchema()], required: ["id"])),

        .init(name: "settings_select_group",
              description: "Select a group in the Settings window by id, opening the GroupEditor detail pane. Opens Settings if not already open.",
              method: "POST", path: "/settings/select-group",
              inputSchema: object(["id": stringSchema()], required: ["id"])),

        .init(name: "settings_open_app_icon_picker",
              description: "Open the app-icon picker sheet in whichever editor is currently open (ButtonEditor or GroupEditor). Opens Settings if not already open. Use settings_select_button or settings_select_group first.",
              method: "POST", path: "/settings/open-app-icon-picker",
              inputSchema: emptyObject()),

        .init(name: "settings_dismiss_picker",
              description: "Close any open picker sheet (app-icon picker or SF Symbol picker) in the Settings window without making a selection.",
              method: "POST", path: "/settings/dismiss-picker",
              inputSchema: emptyObject()),

        .init(name: "settings_clear_selection",
              description: "Deselect the current button or group in the Settings window, collapsing the ButtonEditor or GroupEditor detail pane back to the empty-state placeholder.",
              method: "POST", path: "/settings/clear-selection",
              inputSchema: emptyObject()),

        .init(name: "settings_commit",
              description: "Trigger the Save button in the currently open ButtonEditor or GroupEditor, writing all pending field changes to disk. The editor must already be open (call settings_select_button or settings_select_group first).",
              method: "POST", path: "/settings/commit",
              inputSchema: emptyObject()),

        .init(name: "settings_set_background_color",
              description: "Enable and set the background color of the selected button or group, bypassing the macOS color picker wheel (which cannot be controlled via API). Send {\"color\":\"#RRGGBB\"} to check the 'enabled' checkbox and apply that color; send {\"enabled\":false} to uncheck it and clear the color. Changes are previewed live on the floating panel. The editor must already be open (call settings_select_button or settings_select_group first).",
              method: "POST", path: "/settings/set-background-color",
              inputSchema: object([
                  "color":   stringSchema(description: "#RRGGBB hex color. Required unless enabled:false."),
                  "enabled": boolSchema(description: "Pass false to disable the background color override."),
              ], required: [])),

        .init(name: "settings_set_text_color",
              description: "Enable and set the text/icon color of the selected button or group, bypassing the macOS color picker wheel (which cannot be controlled via API). Send {\"color\":\"#RRGGBB\"} to check the 'enabled' checkbox and apply that color; send {\"enabled\":false} to uncheck it and revert to automatic color (white when a background color is set, system primary otherwise). Changes are previewed live on the floating panel. The editor must already be open (call settings_select_button or settings_select_group first).",
              method: "POST", path: "/settings/set-text-color",
              inputSchema: object([
                  "color":   stringSchema(description: "#RRGGBB hex color. Required unless enabled:false."),
                  "enabled": boolSchema(description: "Pass false to restore automatic color."),
              ], required: [])),

        .init(name: "settings_move",
              description: "Move the Settings window to the given screen coordinates. The Settings window must already be open (call settings_open first). Coordinates use the macOS AppKit system (origin = bottom-left of screen).",
              method: "POST", path: "/settings/move",
              inputSchema: object([
                  "x": numberSchema(description: "Screen X in points (AppKit: 0 = left edge)"),
                  "y": numberSchema(description: "Screen Y in points (AppKit: 0 = bottom edge)"),
              ], required: ["x", "y"])),

        .init(name: "arrange",
              description: "Position the floating panel and Settings window so they do not overlap — call this at the start of any automated test session. When windows overlap, the user cannot easily intervene without disrupting the test, so this ensures a clean layout before testing begins. On wide screens (≥1440 pt): Settings on the left, panel top-right. On narrow screens: Settings bottom-left, panel top-right. Returns the actual positions applied. Pass open_settings:true to also open Settings before arranging.",
              method: "POST", path: "/arrange",
              inputSchema: object([
                  "open_settings": boolSchema(description: "Open the Settings window before arranging (default false)."),
              ], required: [])),

        .init(name: "settings_set_action_type",
              description: "Switch the action type of the selected button: text = paste text into active app, key = send a keyboard shortcut to active app, launch = open app/URL/file, terminal = run a shell command. ButtonEditor-only — call settings_select_button first. Has no effect when a group is selected.",
              method: "POST", path: "/settings/set-action-type",
              inputSchema: object([
                  "type": stringSchema(description: "text | key | launch | terminal")
              ], required: ["type"])),

        .init(name: "settings_set_key_combo",
              description: "Configure a button to send a keyboard shortcut to the active application when clicked (e.g. cmd+shift+v). Prefer this over button_update when you only want to set a key action — no need to construct a full Action JSON. Automatically switches the action type to 'key'. Provide either a full combo string ({\"combo\":\"cmd+shift+v\"}) or individual modifier booleans + base key ({\"cmd\":true,\"key\":\"v\"}). At least one of combo or key must be non-empty. ButtonEditor-only — call settings_select_button first.",
              method: "POST", path: "/settings/set-key-combo",
              inputSchema: object([
                  "combo":  stringSchema(description: "Full combo string, e.g. cmd+shift+v or f5. If provided, all other fields are ignored."),
                  "cmd":    boolSchema(description: "Command (⌘) modifier"),
                  "shift":  boolSchema(description: "Shift (⇧) modifier"),
                  "option": boolSchema(description: "Option (⌥) modifier"),
                  "ctrl":   boolSchema(description: "Control (⌃) modifier"),
                  "key":    stringSchema(description: "Base key: a-z, 0-9, space, return, esc, tab, f1-f20, left, right, up, down, etc."),
              ], required: [])),

        .init(name: "settings_set_action_value",
              description: "Set the text content, launch target, or terminal command in the ButtonEditor without constructing a full Action JSON. Also switches the action type tab to match. Use settings_set_key_combo instead for key actions. ButtonEditor-only — call settings_select_button first.",
              method: "POST", path: "/settings/set-action-value",
              inputSchema: object([
                  "type":  stringSchema(description: "text | launch | terminal  (not key — use settings_set_key_combo for key actions)"),
                  "value": stringSchema(description: "text: paste content string; launch: app path / URL / bundle-id / shell: prefix; terminal: shell command"),
              ], required: ["type", "value"])),
    ]

    // MARK: - Lookup

    public static func find(_ name: String) -> ToolDefinition? {
        tools.first(where: { $0.name == name })
    }

    // MARK: - Dialect rendering

    public enum Dialect: String {
        /// MCP-style `tools/list` payload (default).
        case mcp
        /// OpenAI Chat Completions / Responses API function-calling format.
        case openai
        /// Anthropic tool-use format.
        case anthropic
    }

    public static func render(dialect: Dialect) -> [String: Any] {
        switch dialect {
        case .mcp:
            return [
                "tools": tools.map { t in [
                    "name":        t.name,
                    "description": t.description,
                    "inputSchema": t.inputSchema,
                    "_transport":  [
                        "method": t.method,
                        "path":   t.path,
                    ],
                ] }
            ]
        case .openai:
            return [
                "tools": tools.map { t in [
                    "type": "function",
                    "function": [
                        "name":        t.name,
                        "description": t.description,
                        "parameters":  t.inputSchema,
                    ] as [String: Any],
                ] }
            ]
        case .anthropic:
            return [
                "tools": tools.map { t in [
                    "name":         t.name,
                    "description":  t.description,
                    "input_schema": t.inputSchema,
                ] }
            ]
        }
    }

    // MARK: - JSON Schema helpers

    private static func emptyObject() -> [String: Any] {
        ["type": "object", "properties": [String: Any]()]
    }

    private static func object(_ properties: [String: Any],
                               required: [String] = []) -> [String: Any] {
        var out: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { out["required"] = required }
        return out
    }

    private static func stringSchema(description: String? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "string"]
        if let d = description { s["description"] = d }
        return s
    }

    private static func numberSchema(description: String? = nil,
                                     minimum: Double? = nil,
                                     maximum: Double? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "number"]
        if let d = description { s["description"] = d }
        if let min = minimum { s["minimum"] = min }
        if let max = maximum { s["maximum"] = max }
        return s
    }

    private static func intSchema(description: String? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "integer"]
        if let d = description { s["description"] = d }
        return s
    }

    private static func boolSchema(description: String? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "boolean"]
        if let d = description { s["description"] = d }
        return s
    }

    /// Reusable schema for a full ButtonDefinition.
    private static func buttonDefinitionSchema() -> [String: Any] {
        object([
            "id":              stringSchema(),
            "label":           stringSchema(),
            "icon":            stringSchema(description: "Path to image file, or bundle id (auto-resolves to app icon)."),
            "iconText":        stringSchema(description: "Emoji or 1-2 char glyph used when no image icon is set."),
            "backgroundColor": stringSchema(description: "#RRGGBB or #RRGGBBAA hex."),
            "textColor":       stringSchema(description: "Text / icon color as #RRGGBB or #RRGGBBAA hex. Omit for automatic (white on colored background, primary otherwise)."),
            "width":           numberSchema(description: "Explicit width in points. Omit for auto."),
            "height":          numberSchema(description: "Explicit height in points. Omit for auto."),
            "action":          actionSchema(),
        ], required: ["id", "label", "action"])
    }

    /// Separate schema for button_update (all fields optional; null = clear).
    private static func buttonUpdateSchema() -> [String: Any] {
        object([
            "id":              stringSchema(),
            "label":           stringSchema(),
            "icon":            ["type": ["string", "null"]] as [String: Any],
            "iconText":        ["type": ["string", "null"]] as [String: Any],
            "backgroundColor": ["type": ["string", "null"]] as [String: Any],
            "textColor":       ["type": ["string", "null"]] as [String: Any],
            "width":           ["type": ["number", "null"]] as [String: Any],
            "height":          ["type": ["number", "null"]] as [String: Any],
            "action":          actionSchema(),
        ], required: ["id"])
    }

    /// oneOf for each action type.
    private static func actionSchema() -> [String: Any] {
        [
            "oneOf": [
                object([
                    "type":    ["const": "key"] as [String: Any],
                    "combo":   stringSchema(description: "e.g. cmd+shift+v, f5, cmd+space"),
                ], required: ["type", "combo"]),
                object([
                    "type":             ["const": "text"] as [String: Any],
                    "content":          stringSchema(),
                    "pasteDelayMs":     intSchema(),
                    "restoreClipboard": boolSchema(),
                ], required: ["type", "content"]),
                object([
                    "type":   ["const": "launch"] as [String: Any],
                    "target": stringSchema(description: "Path, URL, bundle id, or shell: prefix"),
                ], required: ["type", "target"]),
                object([
                    "type":      ["const": "terminal"] as [String: Any],
                    "app":       stringSchema(),
                    "command":   stringSchema(),
                    "newWindow": boolSchema(),
                    "execute":   boolSchema(),
                    "profile":   stringSchema(),
                ], required: ["type", "command"]),
                object([
                    "type": ["const": "delay"] as [String: Any],
                    "ms":   intSchema(),
                ], required: ["type", "ms"]),
                object([
                    "type":        ["const": "macro"] as [String: Any],
                    "actions":     ["type": "array"] as [String: Any],
                    "stopOnError": boolSchema(),
                ], required: ["type", "actions"]),
            ] as [[String: Any]]
        ]
    }
}
