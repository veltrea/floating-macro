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

    // MARK: - Localized description loader

    private struct DescBundle: Decodable {
        let tools: [String: String]
        let params: [String: String]
    }

    private static let descBundle: DescBundle? = {
        guard let url = Bundle.module.url(forResource: "tool_descriptions",
                                           withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(DescBundle.self, from: data)
        else { return nil }
        return bundle
    }()

    private static func desc(_ toolName: String, fallback: String) -> String {
        descBundle?.tools[toolName] ?? fallback
    }

    private static func paramDesc(_ key: String, fallback: String) -> String {
        descBundle?.params[key] ?? fallback
    }

    public static let tools: [ToolDefinition] = [
        // MARK: - Self-introduction
        .init(name: "help",
              description: desc("help", fallback: "Re-read the FloatingMacro manifest."),
              method: "GET", path: "/manifest",
              inputSchema: emptyObject()),

        .init(name: "manifest",
              description: desc("manifest", fallback: "Same as 'help'."),
              method: "GET", path: "/manifest",
              inputSchema: emptyObject()),

        // MARK: - Health / state
        .init(name: "ping",
              description: desc("ping", fallback: "Health check."),
              method: "GET", path: "/ping",
              inputSchema: emptyObject()),

        .init(name: "get_state",
              description: desc("get_state", fallback: "Snapshot of the app."),
              method: "GET", path: "/state",
              inputSchema: emptyObject()),

        // MARK: - Panel (Phase 3: multi-panel)
        // Introduced in Phase 3 (v0.12). FloatingMacro allows multiple floating panels to be created and managed simultaneously.
        // Can be simultaneously resident. Each panel has an independent position, size, transparency, and
        // Has presets. New AI integration code uses this.
        .init(name: "panel_list",
              description: desc("panel_list", fallback: "List all floating panels."),
              method: "GET", path: "/panel/list",
              inputSchema: emptyObject()),

        .init(name: "panel_create",
              description: desc("panel_create", fallback: "Create a new floating panel."),
              method: "POST", path: "/panel/create",
              inputSchema: object([
                  "presetName": stringSchema(description: paramDesc("panel_create.presetName", fallback: "Name of the preset this panel will display. Must exist.")),
                  "x":          numberSchema(),
                  "y":          numberSchema(),
                  "width":      numberSchema(minimum: 120),
                  "height":     numberSchema(minimum: 80),
                  "opacity":         numberSchema(minimum: 0.25, maximum: 1.0),
                  "backgroundColor": stringSchema(description: paramDesc("panel_create.backgroundColor", fallback: "#RRGGBB hex for the panel background.")),
              ], required: ["presetName"])),

        .init(name: "panel_close",
              description: desc("panel_close", fallback: "Close (delete) a panel by id."),
              method: "POST", path: "/panel/close",
              inputSchema: object([
                  "id": stringSchema(description: paramDesc("panel_close.id", fallback: "Panel id from panel_list."))
              ], required: ["id"])),

        .init(name: "panel_show",
              description: desc("panel_show", fallback: "Show the floating panel."),
              method: "POST", path: "/panel/show",
              inputSchema: object([
                  "id": stringSchema(description: paramDesc("panel_show.id", fallback: "Panel id from panel_list."))
              ], required: ["id"])),

        .init(name: "panel_hide",
              description: desc("panel_hide", fallback: "Hide the floating panel."),
              method: "POST", path: "/panel/hide",
              inputSchema: object([
                  "id": stringSchema(description: paramDesc("panel_hide.id", fallback: "Panel id from panel_list."))
              ], required: ["id"])),

        // Phase 3.6: Tool group for operating individual panels by ID. Mouse and trackpad operations.
        // Dragging is difficult for users, so they use voice input and AI to "move the panel in the upper right corner to the lower left".
        // To make it possible to complete with instructions such as "Expand the Claude Code panel to the right half of the screen."
        .init(name: "panel_move",
              description: desc("panel_move", fallback: "Move the panel to absolute screen coordinates."),
              method: "POST", path: "/panel/move",
              inputSchema: object([
                  "id": stringSchema(description: paramDesc("panel_move.id", fallback: "Panel id from panel_list.")),
                  "x":  numberSchema(description: paramDesc("panel_move.x", fallback: "Screen X in points")),
                  "y":  numberSchema(description: paramDesc("panel_move.y", fallback: "Screen Y in points")),
              ], required: ["id", "x", "y"])),

        .init(name: "panel_resize",
              description: desc("panel_resize", fallback: "Resize the panel."),
              method: "POST", path: "/panel/resize",
              inputSchema: object([
                  "id":     stringSchema(description: paramDesc("panel_resize.id", fallback: "Panel id from panel_list.")),
                  "width":  numberSchema(minimum: 120),
                  "height": numberSchema(minimum: 80),
              ], required: ["id", "width", "height"])),

        .init(name: "panel_opacity",
              description: desc("panel_opacity", fallback: "Set the opacity of the panel."),
              method: "POST", path: "/panel/opacity",
              inputSchema: object([
                  "id":      stringSchema(description: paramDesc("panel_opacity.id", fallback: "Panel id from panel_list.")),
                  "opacity": numberSchema(minimum: 0.25, maximum: 1.0),
              ], required: ["id", "opacity"])),

        .init(name: "panel_background_color",
              description: desc("panel_background_color", fallback: "Set the background color of the panel."),
              method: "POST", path: "/panel/background-color",
              inputSchema: object([
                  "id":    stringSchema(description: paramDesc("panel_background_color.id", fallback: "Panel id from panel_list.")),
                  "color": stringSchema(description: paramDesc("panel_background_color.color", fallback: "#RRGGBB hex string.")),
              ], required: ["id"])),

        .init(name: "panel_set_preset",
              description: desc("panel_set_preset", fallback: "Switch the preset displayed by the panel."),
              method: "POST", path: "/panel/set-preset",
              inputSchema: object([
                  "id":         stringSchema(description: paramDesc("panel_set_preset.id", fallback: "Panel id from panel_list.")),
                  "presetName": stringSchema(description: paramDesc("panel_set_preset.presetName", fallback: "Preset internal id from preset_list.")),
              ], required: ["id", "presetName"])),

        // Dock to Phase 3.5
        .init(name: "panel_dock",
              description: desc("panel_dock", fallback: "Dock a panel to a screen edge."),
              method: "POST", path: "/panel/dock",
              inputSchema: object([
                  "id":   stringSchema(description: paramDesc("panel_dock.id", fallback: "Panel id from panel_list.")),
                  "edge": stringSchema(description: paramDesc("panel_dock.edge", fallback: "Screen edge: left, right, top, or bottom.")),
              ], required: ["id"])),

        .init(name: "panel_undock",
              description: desc("panel_undock", fallback: "Expand a docked panel back to floating state."),
              method: "POST", path: "/panel/undock",
              inputSchema: object([
                  "id": stringSchema(description: paramDesc("panel_undock.id", fallback: "Panel id from panel_list.")),
              ], required: ["id"])),

        .init(name: "panel_reset_dock_position",
              description: desc("panel_reset_dock_position", fallback: "Reset a dock bar's position to auto-layout."),
              method: "POST", path: "/panel/reset-dock-position",
              inputSchema: object([
                  "id": stringSchema(description: paramDesc("panel_reset_dock_position.id", fallback: "Panel id from panel_list.")),
              ], required: ["id"])),

        .init(name: "panel_gather_dock_bars",
              description: desc("panel_gather_dock_bars", fallback: "Reset ALL dock bars to auto-layout."),
              method: "POST", path: "/panel/gather-dock-bars",
              inputSchema: emptyObject()),

        // MARK: - Window (Phase 3: deprecated — operates on the primary panel)
        // In Phase 3, since the panels are multi-panelized, these tools correspond to panels[0].
        // (Primary panel) backward-compatible API that acts on. New development should use panel_*.
        .init(name: "window_show",
              description: desc("window_show", fallback: "DEPRECATED: prefer panel_show."),
              method: "POST", path: "/window/show",
              inputSchema: emptyObject()),

        .init(name: "window_hide",
              description: desc("window_hide", fallback: "DEPRECATED: prefer panel_hide."),
              method: "POST", path: "/window/hide",
              inputSchema: emptyObject()),

        .init(name: "window_toggle",
              description: desc("window_toggle", fallback: "DEPRECATED: prefer panel_show / panel_hide."),
              method: "POST", path: "/window/toggle",
              inputSchema: emptyObject()),

        .init(name: "window_opacity",
              description: desc("window_opacity", fallback: "DEPRECATED: prefer panel_opacity."),
              method: "POST", path: "/window/opacity",
              inputSchema: object([
                  "value": numberSchema(minimum: 0.25, maximum: 1.0)
              ], required: ["value"])),

        .init(name: "window_move",
              description: desc("window_move", fallback: "DEPRECATED: prefer panel_move."),
              method: "POST", path: "/window/move",
              inputSchema: object([
                  "x": numberSchema(),
                  "y": numberSchema(),
              ], required: ["x", "y"])),

        .init(name: "window_resize",
              description: desc("window_resize", fallback: "DEPRECATED: prefer panel_resize."),
              method: "POST", path: "/window/resize",
              inputSchema: object([
                  "width":  numberSchema(minimum: 120),
                  "height": numberSchema(minimum: 80),
              ], required: ["width", "height"])),

        // MARK: - Preset
        .init(name: "preset_list",
              description: desc("preset_list", fallback: "List all preset names."),
              method: "GET", path: "/preset/list",
              inputSchema: emptyObject()),

        .init(name: "preset_current",
              description: desc("preset_current", fallback: "Full JSON of the currently-active preset."),
              method: "GET", path: "/preset/current",
              inputSchema: emptyObject()),

        .init(name: "preset_get",
              description: desc("preset_get", fallback: "Full JSON of an arbitrary preset by name."),
              method: "GET", path: "/preset/get",
              inputSchema: object([
                  "name": stringSchema(description: paramDesc("preset_get.name", fallback: "Preset internal id from preset_list.")),
              ], required: ["name"])),

        .init(name: "preset_switch",
              description: desc("preset_switch", fallback: "Switch the active preset by name."),
              method: "POST", path: "/preset/switch",
              inputSchema: object([
                  "name": stringSchema()
              ], required: ["name"])),

        .init(name: "preset_reload",
              description: desc("preset_reload", fallback: "Re-read preset files from disk."),
              method: "POST", path: "/preset/reload",
              inputSchema: emptyObject()),

        .init(name: "preset_create",
              description: desc("preset_create", fallback: "Create a new empty preset file."),
              method: "POST", path: "/preset/create",
              inputSchema: object([
                  "name":        stringSchema(description: paramDesc("preset_create.name", fallback: "File name (no .json).")),
                  "displayName": stringSchema(description: paramDesc("preset_create.displayName", fallback: "Human-facing label shown in menus.")),
                  "memo":        stringSchema(description: paramDesc("preset_create.memo", fallback: "Multi-line usage note.")),
              ], required: [])),

        .init(name: "preset_rename",
              description: desc("preset_rename", fallback: "Update preset-level metadata."),
              method: "POST", path: "/preset/rename",
              inputSchema: object([
                  "name":        stringSchema(description: paramDesc("preset_rename.name", fallback: "Internal id of the preset to update.")),
                  "displayName": stringSchema(description: paramDesc("preset_rename.displayName", fallback: "New human-facing label.")),
                  "memo":        stringSchema(description: paramDesc("preset_rename.memo", fallback: "New usage note.")),
              ], required: ["name"])),

        .init(name: "preset_delete",
              description: desc("preset_delete", fallback: "Delete a preset file."),
              method: "POST", path: "/preset/delete",
              inputSchema: object([
                  "name": stringSchema()
              ], required: ["name"])),

        .init(name: "preset_export",
              description: desc("preset_export", fallback: "Return one preset as a JSON object."),
              method: "POST", path: "/preset/export",
              inputSchema: object([
                  "name": stringSchema(description: paramDesc("preset_export.name", fallback: "Internal id of the preset to export."))
              ], required: ["name"])),

        .init(name: "preset_export_bundle",
              description: desc("preset_export_bundle", fallback: "Return every preset packed into a single JSON."),
              method: "POST", path: "/preset/export-bundle",
              inputSchema: object([:], required: [])),

        .init(name: "preset_import",
              description: desc("preset_import", fallback: "Import one or more presets."),
              method: "POST", path: "/preset/import",
              inputSchema: object([
                  "preset": object([:], required: []),
                  "bundle": object([:], required: []),
              ], required: [])),

        .init(name: "preset_install_seeds",
              description: desc("preset_install_seeds", fallback: "Re-install bundled seed presets."),
              method: "POST", path: "/preset/install-seeds",
              inputSchema: object([
                  "force": boolSchema(description: paramDesc("preset_install_seeds.force", fallback: "When true, overwrite existing files.")),
              ], required: [])),

        .init(name: "preset_reorder",
              description: desc("preset_reorder", fallback: "Reorder the preset list."),
              method: "POST", path: "/preset/reorder",
              inputSchema: object([
                  "ids": ["type": "array", "items": ["type": "string"],
                          "description": paramDesc("preset_reorder.ids", fallback: "Preset internal ids in the desired display order.")] as [String: Any],
              ], required: ["ids"])),

        // MARK: - Groups
        .init(name: "group_add",
              description: desc("group_add", fallback: "Append a new button group to the active preset."),
              method: "POST", path: "/group/add",
              inputSchema: object([
                  "id":          stringSchema(description: paramDesc("group_add.id", fallback: "Unique id within the preset.")),
                  "label":       stringSchema(description: paramDesc("group_add.label", fallback: "Visible header text.")),
                  "collapsed":   boolSchema(description: paramDesc("group_add.collapsed", fallback: "Start collapsed. Default false.")),
                  "displayType": stringSchema(description: paramDesc("group_add.displayType", fallback: "icon | wide | card | grid. Default icon.")),
                  "columns":     stringSchema(description: paramDesc("group_add.columns", fallback: "Card grid columns.")),
                  "iconSize":    stringSchema(description: paramDesc("group_add.iconSize", fallback: "Icon display size.")),
              ], required: ["id", "label"])),

        .init(name: "group_update",
              description: desc("group_update", fallback: "Patch a group's label, icon, colors, etc."),
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
                  "displayType":     stringSchema(description: paramDesc("group_update.displayType", fallback: "icon | wide | card | grid.")),
                  "columns":         stringSchema(description: paramDesc("group_update.columns", fallback: "auto | 1 | 2 | 3.")),
                  "iconSize":        stringSchema(description: paramDesc("group_update.iconSize", fallback: "small | medium | large | xlarge.")),
              ], required: ["id"])),

        .init(name: "group_delete",
              description: desc("group_delete", fallback: "Delete a group and all its buttons."),
              method: "POST", path: "/group/delete",
              inputSchema: object([
                  "id": stringSchema()
              ], required: ["id"])),

        // MARK: - Buttons
        .init(name: "button_add",
              description: desc("button_add", fallback: "Append a button to a group."),
              method: "POST", path: "/button/add",
              inputSchema: object([
                  "groupId": stringSchema(),
                  "button":  buttonDefinitionSchema(),
              ], required: ["groupId", "button"])),

        .init(name: "button_update",
              description: desc("button_update", fallback: "Partial-patch a button."),
              method: "POST", path: "/button/update",
              inputSchema: buttonUpdateSchema()),

        .init(name: "button_delete",
              description: desc("button_delete", fallback: "Delete a button by id."),
              method: "POST", path: "/button/delete",
              inputSchema: object([
                  "id": stringSchema()
              ], required: ["id"])),

        .init(name: "button_reorder",
              description: desc("button_reorder", fallback: "Reorder buttons within a group."),
              method: "POST", path: "/button/reorder",
              inputSchema: object([
                  "groupId": stringSchema(),
                  "ids":     ["type": "array", "items": ["type": "string"]] as [String: Any],
              ], required: ["groupId", "ids"])),

        .init(name: "button_move",
              description: desc("button_move", fallback: "Move a button to another group."),
              method: "POST", path: "/button/move",
              inputSchema: object([
                  "id":         stringSchema(),
                  "toGroupId":  stringSchema(),
                  "position":   intSchema(description: paramDesc("button_move.position", fallback: "0-based insertion index.")),
              ], required: ["id", "toGroupId"])),

        // MARK: - Action execution
        .init(name: "run_action",
              description: desc("run_action", fallback: "Execute an Action immediately."),
              method: "POST", path: "/action",
              inputSchema: actionSchema()),

        .init(name: "button_press",
              description: desc("button_press", fallback: "Press a button by synthesizing a real mouse click."),
              method: "POST", path: "/button/press",
              inputSchema: object([
                  "id": stringSchema(description: paramDesc("button_press.id", fallback: "Button id within the active preset.")),
              ], required: ["id"])),

        // MARK: - Observation
        .init(name: "log_tail",
              description: desc("log_tail", fallback: "Return recent log events."),
              method: "GET", path: "/log/tail",
              inputSchema: object([
                  "level":  stringSchema(description: paramDesc("log_tail.level", fallback: "debug | info | warn | error")),
                  "since":  stringSchema(description: paramDesc("log_tail.since", fallback: "Duration like '5m', '2h', '1d'")),
                  "limit":  intSchema(description: paramDesc("log_tail.limit", fallback: "Max events to return")),
              ])),

        .init(name: "icon_for_app",
              description: desc("icon_for_app", fallback: "Fetch the macOS icon for an app as base64 PNG."),
              method: "GET", path: "/icon/for-app",
              inputSchema: object([
                  "bundleId": stringSchema(description: paramDesc("icon_for_app.bundleId", fallback: "e.g. com.apple.Safari")),
                  "path":     stringSchema(description: paramDesc("icon_for_app.path", fallback: "Absolute path to an .app bundle")),
              ])),

        // MARK: - Settings window
        .init(name: "settings_open",
              description: desc("settings_open", fallback: "Open the Settings window."),
              method: "POST", path: "/settings/open",
              inputSchema: emptyObject()),

        .init(name: "settings_close",
              description: desc("settings_close", fallback: "Close the Settings window."),
              method: "POST", path: "/settings/close",
              inputSchema: emptyObject()),

        .init(name: "ai_integration_open",
              description: desc("ai_integration_open", fallback: "Open the AI Integration window."),
              method: "POST", path: "/ai-integration/open",
              inputSchema: emptyObject()),

        .init(name: "ai_integration_close",
              description: desc("ai_integration_close", fallback: "Close the AI Integration window."),
              method: "POST", path: "/ai-integration/close",
              inputSchema: emptyObject()),

        .init(name: "settings_open_sf_picker",
              description: desc("settings_open_sf_picker", fallback: "Open the SF Symbol picker sheet."),
              method: "POST", path: "/settings/open-sf-picker",
              inputSchema: emptyObject()),

        // MARK: - Settings window — test automation
        .init(name: "settings_select_button",
              description: desc("settings_select_button", fallback: "Select a button in the Settings window by id."),
              method: "POST", path: "/settings/select-button",
              inputSchema: object(["id": stringSchema()], required: ["id"])),

        .init(name: "settings_select_group",
              description: desc("settings_select_group", fallback: "Select a group in the Settings window by id."),
              method: "POST", path: "/settings/select-group",
              inputSchema: object(["id": stringSchema()], required: ["id"])),

        .init(name: "settings_open_app_icon_picker",
              description: desc("settings_open_app_icon_picker", fallback: "Open the app-icon picker sheet."),
              method: "POST", path: "/settings/open-app-icon-picker",
              inputSchema: emptyObject()),

        .init(name: "settings_dismiss_picker",
              description: desc("settings_dismiss_picker", fallback: "Close any open picker sheet."),
              method: "POST", path: "/settings/dismiss-picker",
              inputSchema: emptyObject()),

        .init(name: "settings_clear_selection",
              description: desc("settings_clear_selection", fallback: "Deselect the current button or group."),
              method: "POST", path: "/settings/clear-selection",
              inputSchema: emptyObject()),

        .init(name: "settings_commit",
              description: desc("settings_commit", fallback: "Trigger the Save button."),
              method: "POST", path: "/settings/commit",
              inputSchema: emptyObject()),

        .init(name: "settings_set_background_color",
              description: desc("settings_set_background_color", fallback: "Set the background color of the selected button or group."),
              method: "POST", path: "/settings/set-background-color",
              inputSchema: object([
                  "color":   stringSchema(description: paramDesc("settings_set_background_color.color", fallback: "#RRGGBB hex color.")),
                  "enabled": boolSchema(description: paramDesc("settings_set_background_color.enabled", fallback: "Pass false to disable.")),
              ], required: [])),

        .init(name: "settings_set_text_color",
              description: desc("settings_set_text_color", fallback: "Set the text/icon color of the selected button or group."),
              method: "POST", path: "/settings/set-text-color",
              inputSchema: object([
                  "color":   stringSchema(description: paramDesc("settings_set_text_color.color", fallback: "#RRGGBB hex color.")),
                  "enabled": boolSchema(description: paramDesc("settings_set_text_color.enabled", fallback: "Pass false to restore automatic color.")),
              ], required: [])),

        .init(name: "settings_move",
              description: desc("settings_move", fallback: "Move the Settings window."),
              method: "POST", path: "/settings/move",
              inputSchema: object([
                  "x": numberSchema(description: paramDesc("settings_move.x", fallback: "Screen X in points")),
                  "y": numberSchema(description: paramDesc("settings_move.y", fallback: "Screen Y in points")),
              ], required: ["x", "y"])),

        .init(name: "arrange",
              description: desc("arrange", fallback: "Position panel and Settings so they do not overlap."),
              method: "POST", path: "/arrange",
              inputSchema: object([
                  "open_settings": boolSchema(description: paramDesc("arrange.open_settings", fallback: "Open Settings before arranging (default false).")),
              ], required: [])),

        .init(name: "settings_set_action_type",
              description: desc("settings_set_action_type", fallback: "Switch the action type of the selected button."),
              method: "POST", path: "/settings/set-action-type",
              inputSchema: object([
                  "type": stringSchema(description: paramDesc("settings_set_action_type.type", fallback: "text | key | launch | terminal"))
              ], required: ["type"])),

        .init(name: "settings_set_key_combo",
              description: desc("settings_set_key_combo", fallback: "Configure a button to send a keyboard shortcut."),
              method: "POST", path: "/settings/set-key-combo",
              inputSchema: object([
                  "combo":  stringSchema(description: paramDesc("settings_set_key_combo.combo", fallback: "Full combo string, e.g. cmd+shift+v.")),
                  "cmd":    boolSchema(description: paramDesc("settings_set_key_combo.cmd", fallback: "Command (⌘) modifier")),
                  "shift":  boolSchema(description: paramDesc("settings_set_key_combo.shift", fallback: "Shift (⇧) modifier")),
                  "option": boolSchema(description: paramDesc("settings_set_key_combo.option", fallback: "Option (⌥) modifier")),
                  "ctrl":   boolSchema(description: paramDesc("settings_set_key_combo.ctrl", fallback: "Control (⌃) modifier")),
                  "key":    stringSchema(description: paramDesc("settings_set_key_combo.key", fallback: "Base key.")),
              ], required: [])),

        .init(name: "list_key_codes",
              description: desc("list_key_codes", fallback: "Return the catalog of key names for key combos."),
              method: "GET", path: "/key-codes",
              inputSchema: emptyObject()),

        .init(name: "settings_set_action_value",
              description: desc("settings_set_action_value", fallback: "Set text content, launch target, or terminal command."),
              method: "POST", path: "/settings/set-action-value",
              inputSchema: object([
                  "type":  stringSchema(description: paramDesc("settings_set_action_value.type", fallback: "text | launch | terminal")),
                  "value": stringSchema(description: paramDesc("settings_set_action_value.value", fallback: "text: content; launch: target; terminal: command")),
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
            "id":                 stringSchema(),
            "label":              stringSchema(),
            "icon":               stringSchema(description: paramDesc("button_definition.icon", fallback: "Path to image file, or bundle id.")),
            "iconText":           stringSchema(description: paramDesc("button_definition.iconText", fallback: "Emoji or 1-2 char glyph.")),
            "backgroundColor":    stringSchema(description: paramDesc("button_definition.backgroundColor", fallback: "#RRGGBB or #RRGGBBAA hex.")),
            "textColor":          stringSchema(description: paramDesc("button_definition.textColor", fallback: "Text / icon color as #RRGGBB hex.")),
            "width":              numberSchema(description: paramDesc("button_definition.width", fallback: "Explicit width in points.")),
            "height":             numberSchema(description: paramDesc("button_definition.height", fallback: "Explicit height in points.")),
            "confirm":            boolSchema(description: paramDesc("button_definition.confirm", fallback: "Show a confirmation dialog. Default false.")),
            "confirmMessage":     stringSchema(description: paramDesc("button_definition.confirmMessage", fallback: "Custom dialog body.")),
            "confirmDestructive": boolSchema(description: paramDesc("button_definition.confirmDestructive", fallback: "Red destructive style. Default false.")),
            "cardThumbnailMode":  stringSchema(description: paramDesc("button_definition.cardThumbnailMode", fallback: "fill | fit.")),
            "action":             actionSchema(),
        ], required: ["id", "label", "action"])
    }

    /// Separate schema for button_update (all fields optional; null = clear).
    private static func buttonUpdateSchema() -> [String: Any] {
        object([
            "id":                 stringSchema(),
            "label":              stringSchema(),
            "icon":               ["type": ["string", "null"]] as [String: Any],
            "iconText":           ["type": ["string", "null"]] as [String: Any],
            "backgroundColor":    ["type": ["string", "null"]] as [String: Any],
            "textColor":          ["type": ["string", "null"]] as [String: Any],
            "width":              ["type": ["number", "null"]] as [String: Any],
            "height":             ["type": ["number", "null"]] as [String: Any],
            "confirm":            boolSchema(description: paramDesc("button_update.confirm", fallback: "Toggle the confirmation dialog.")),
            "confirmMessage":     ["type": ["string", "null"], "description": paramDesc("button_update.confirmMessage", fallback: "Custom dialog body. Pass null to clear.")] as [String: Any],
            "confirmDestructive": boolSchema(description: paramDesc("button_update.confirmDestructive", fallback: "Toggle the red destructive style.")),
            "cardThumbnailMode":  stringSchema(description: paramDesc("button_update.cardThumbnailMode", fallback: "fill | fit.")),
            "action":             actionSchema(),
        ], required: ["id"])
    }

    /// oneOf for each action type. Top-level `type: "object"` is required by
    /// strict MCP clients (Gemini CLI rejects schemas without it). Each variant
    /// inside `oneOf` already declares its own `type: "object"`.
    private static func actionSchema() -> [String: Any] {
        [
            "type": "object",
            "oneOf": [
                object([
                    "type":    ["const": "key"] as [String: Any],
                    "combo":   stringSchema(description: paramDesc("action.combo", fallback: "e.g. cmd+shift+v, f5, cmd+space")),
                ], required: ["type", "combo"]),
                object([
                    "type":             ["const": "text"] as [String: Any],
                    "content":          stringSchema(),
                    "pasteDelayMs":     intSchema(),
                    "restoreClipboard": boolSchema(),
                    "appendMode":       boolSchema(description: paramDesc("action.appendMode", fallback: "Append content to clipboard without pasting. Default false.")),
                ], required: ["type", "content"]),
                object([
                    "type":   ["const": "launch"] as [String: Any],
                    "target": stringSchema(description: paramDesc("action.target", fallback: "Path, URL, bundle id, or shell: prefix")),
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
