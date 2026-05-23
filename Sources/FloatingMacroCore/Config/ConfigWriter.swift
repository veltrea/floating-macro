import Foundation

public final class ConfigWriter {
    private let encoder: JSONEncoder
    private let baseURL: URL
    private let userBaseURL: URL

    public init(baseURL: URL? = nil, userBaseURL: URL? = nil) {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.baseURL = baseURL ?? ConfigLoader.defaultBaseURL
        self.userBaseURL = userBaseURL ?? ConfigLoader.defaultUserBaseURL
    }

    public func saveAppConfig(_ config: AppConfig) throws {
        let url = baseURL.appendingPathComponent("config.json")
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    /// Save a user-edited preset. Writes into the user directory
    /// (`~/Documents/FloatingMacro/presets/`). If the preset previously lived
    /// only in the seed area, this is the copy-on-write boundary — the seed
    /// file is left intact and the user file shadows it from now on.
    public func savePreset(_ preset: Preset) throws {
        let dir = userBaseURL.appendingPathComponent("presets")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(preset.name).json")
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomic)
    }

    /// Save a preset directly into the seed (Application Support) area.
    /// Reserved for `SeedPresetInstaller` and the "Reinstall bundled presets"
    /// flow. Regular edits MUST go through `savePreset(_:)` so the user
    /// directory accumulates the user's customizations.
    public func savePresetToSeed(_ preset: Preset) throws {
        let dir = baseURL.appendingPathComponent("presets")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(preset.name).json")
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Default preset factory

    // Python one-liner template for safely merging updates to settings.json.
    // Passing key and value appends or overwrites existing settings without breaking them.
    private static func settingsPython(
        _ assignments: String,
        message: String
    ) -> String {
        """
        python3 -c "
        import json, os, sys
        p = os.path.expanduser('~/.claude/settings.json')
        os.makedirs(os.path.dirname(p), exist_ok=True)
        try:
            with open(p) as f: d = json.load(f)
        except: d = {}
        \(assignments)
        with open(p, 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
        print('\(message)')
        "
        """
    }

    // Shell for copying AI connection prompt to clipboard
    // Copy token from Keychain to formatted prompt via pbcopy.
    // Assuming multiple lines are passed as a single argument to /bin/sh -c.
    //
    // Note: Always export LC_CTYPE=UTF-8 at the beginning for GUI-launched macOS.
    // The child processes of the app inherit LANG="" and LC_CTYPE="C", and that
    // When you flow multibyte characters to pbcopy in the state, garbled bytes appear on the clipboard.
    // Enter (becomes silent and corrupted when accessed via pbpaste, detection is extremely difficult).
    private static let aiConnectPromptShell: String = #"""
    export LC_CTYPE=UTF-8
    T=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w 2>/dev/null)
    if [ -z "$T" ]; then
      osascript -e 'display alert "FloatingMacro" message "Authentication token not found in Keychain. Please restart the app." as critical'
      exit 1
    fi
    cat <<EOF | pbcopy
    You are an AI that can operate FloatingMacro on macOS.

    Connection target: http://127.0.0.1:17430
    Authentication Token: $T

    First curl -s http:// 127.0.0.1:17430/manifest | Execute jq to obtain the app's self-introduction and all tool definitions (this endpoint does not require authentication). The systemPrompt and tools array in manifest are the true explanation of this API.

    Principles of Operation:
    - All tool calls must be made via POST /tools/call.
    - Do not directly hit individual endpoints (e.g., /group/add).
    - Authentication required for endpoints requires token in Authorization: Bearer header

    Please understand the current situation before starting work:
    - GET /state Get panel state and active preset
    - GET /preset/current Get Current Group Button Configuration

    Please confirm what you want to do before proceeding with the operation of FloatingMacro.
    EOF
    osascript -e 'display notification "AI Copied prompt to clipboard" with title "FloatingMacro"'
    """#

    // Shell to register an MCP entry in the ~/.claude.json file for Claude Code.
    // Append to existing mcpServers without breaking them. Embed Bearer token in headers.
    private static let claudeCodeMCPRegisterShell: String = #"""
    export LC_CTYPE=UTF-8
    T=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w 2>/dev/null)
    if [ -z "$T" ]; then
      osascript -e 'display alert "FloatingMacro" message "Authentication token not found in Keychain." as critical'
      exit 1
    fi
    P="$HOME/.claude.json"
    /usr/bin/env python3 - "$T" "$P" <<'PY'
    import json, os, sys
    token, path = sys.argv[1], sys.argv[2]
    try:
        with open(path) as f: d = json.load(f)
    except FileNotFoundError:
        d = {}
    except json.JSONDecodeError as e:
        print(f"Existing ~/.claude.json is broken: {e}", file=sys.stderr)
        sys.exit(1)
    d.setdefault("mcpServers", {})["floatingmacro"] = {
        "type": "http",
        "url": "http://127.0.0.1:17430/mcp",
        "headers": {"Authorization": f"Bearer {token}"},
    }
    with open(path, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
    print(f"Registered: {path}")
    PY
    osascript -e 'display notification "Claude Code When restarted, floatingmacro will automatically connect." with title "FloatingMacro: Registration Complete"'
    """#

    static func makeDefaultPreset() -> Preset {
        // Paste Text Action (Insert into Claude Code Prompt) -
        func txt(_ content: String) -> Action {
            .text(content: content, pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
        }
        // Terminal Execution Action ---
        func term(_ command: String) -> Action {
            .terminal(app: "Terminal", command: command,
                      newWindow: false, execute: true, profile: nil)
        }
        // Silent shell execution (without opening Terminal)
        func sh(_ command: String) -> Action {
            .launch(target: "shell:" + command)
        }

        return Preset(
            name: "default",
            displayName: "Claude Code",
            groups: [
                // Connect FloatingMacro to AI
                ButtonGroup(
                    id: "group-ai-connect",
                    label: "AI Connect",
                    iconText: "🔗",
                    buttons: [
                        ButtonDefinition(
                            id: "btn-ai-copy-prompt",
                            label: "Copy connection prompt",
                            iconText: "📋",
                            backgroundColor: "#3B6BA5",
                            tooltip: "Claude Code / Cursor / Gemini CLI / ChatGPT Copy prompt with embedded tokens to clipboard (token-filled)",
                            action: sh(aiConnectPromptShell)
                        ),
                        ButtonDefinition(
                            id: "btn-ai-claude-code-mcp",
                            label: "Claude Code Register as MCP",
                            iconText: "⚙",
                            backgroundColor: "#2D7D46",
                            tooltip: "~/.claude.json Write a floatingmacro entry. Claude Code will reconnect automatically upon restarting.",
                            action: sh(claudeCodeMCPRegisterShell)
                        ),
                    ]
                ),

                // Command to be used during the session
                ButtonGroup(
                    id: "group-session",
                    label: "Claude Code",
                    icon: "com.anthropic.claudefordesktop",
                    buttons: [
                        ButtonDefinition(
                            id: "btn-ultrathink",
                            label: "ultrathink",
                            iconText: "🧠",
                            tooltip: "Activate high-quality thinking for that turn (effective only when effort is less than high).",
                            action: txt("ultrathink Please proceed with the next task.")
                        ),
                        ButtonDefinition(
                            id: "btn-stop-loop",
                            label: "Stop",
                            iconText: "⏸",
                            tooltip: "Interrupt loop to provide status report",
                            action: txt("Looping-like, pause for now and report current status and next action.")
                        ),
                        ButtonDefinition(
                            id: "btn-research-first",
                            label: "Priority Check",
                            iconText: "🔍",
                            tooltip: "Do not guess and make the program read files before working (Claude).md Rule Correspondence:",
                            action: txt("Before changing the code, always thoroughly understand the contents of the target file. Do not guess work; prioritize investigation and confirmation.")
                        ),
                        ButtonDefinition(
                            id: "btn-test-after",
                            label: "Run Test",
                            iconText: "✅",
                            tooltip: "Run tests after making changes to verify functionality.",
                            action: txt("After changes are complete, run tests and report the results of the functional verification.")
                        ),
                    ]
                ),

                // Switch Effort ────────────────
                ButtonGroup(
                    id: "group-effort",
                    label: "Effort",
                    icon: "com.anthropic.claudefordesktop",
                    buttons: [
                        ButtonDefinition(
                            id: "btn-effort-high",
                            label: "high",
                            iconText: "⬆",
                            backgroundColor: "#2D7D46",
                            tooltip: "High-quality daily use (recommended)",
                            action: txt("/effort high")
                        ),
                        ButtonDefinition(
                            id: "btn-effort-max",
                            label: "max",
                            iconText: "🔥",
                            backgroundColor: "#C23B22",
                            tooltip: "Full thinking. Hard debugging or design (token consumption large)",
                            action: txt("/effort max")
                        ),
                        ButtonDefinition(
                            id: "btn-effort-low",
                            label: "low",
                            iconText: "⚡",
                            backgroundColor: "#555555",
                            tooltip: "Rapidly process light tasks such as renaming files and adding comments.",
                            action: txt("/effort low")
                        ),
                        ButtonDefinition(
                            id: "btn-effort-auto",
                            label: "auto",
                            iconText: "🤖",
                            backgroundColor: "#3B6BA5",
                            tooltip: "Trust thinking to the model (for API billing side)",
                            action: txt("/effort auto")
                        ),
                    ]
                ),

                // Permanent Settings (Terminal Execution)
                ButtonGroup(
                    id: "group-settings",
                    label: "Settings",
                    icon: "sf:gearshape",
                    buttons: [
                        ButtonDefinition(
                            id: "btn-cfg-quality",
                            label: "Quality-focused settings",
                            iconText: "🛡",
                            backgroundColor: "#2D7D46",
                            tooltip: "effortLevel=high + Adaptive ThinkingDisable + Thought Summary Display",
                            action: term(settingsPython(
                                """
                                d['effortLevel'] = 'high'
                                d.setdefault('env', {})['CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING'] = '1'
                                d['showThinkingSummaries'] = True
                                """,
                                message: "Setup Complete: Effort Level=high, Adaptive ThinkingDisable, Display Thought Summary"
                            ))
                        ),
                        ButtonDefinition(
                            id: "btn-cfg-balanced",
                            label: "Balance Settings",
                            iconText: "⚖",
                            backgroundColor: "#3B6BA5",
                            tooltip: "effortLevel=auto + Adaptive ThinkingDisable (balance speed and cost)",
                            action: term(settingsPython(
                                """
                                d['effortLevel'] = 'auto'
                                d.setdefault('env', {})['CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING'] = '1'
                                d['showThinkingSummaries'] = True
                                """,
                                message: "Setup Complete: Effort Level=auto, Adaptive ThinkingDisable, Display Thought Summary"
                            ))
                        ),
                        ButtonDefinition(
                            id: "btn-cfg-disable-adaptive",
                            label: "Adaptive Thinking Disable",
                            iconText: "🚫",
                            backgroundColor: "#8B4513",
                            tooltip: "Zero-bug inference avoidance. Boris Cherny's highly recommended workaround",
                            action: term(settingsPython(
                                """
                                d.setdefault('env', {})['CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING'] = '1'
                                """,
                                message: "Setting complete: CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1"
                            ))
                        ),
                        ButtonDefinition(
                            id: "btn-cfg-show-thinking",
                            label: "Display Thought Summary",
                            iconText: "💭",
                            tooltip: "ClaudeDisplay summary of thought process on UI again",
                            action: term(settingsPython(
                                """
                                d['showThinkingSummaries'] = True
                                """,
                                message: "Setting complete: showThinkingSummaries=true"
                            ))
                        ),
                    ]
                ),

                // Version management
                ButtonGroup(
                    id: "group-version",
                    label: "Version",
                    icon: "sf:arrow.triangle.2.circlepath",
                    collapsed: true,
                    buttons: [
                        ButtonDefinition(
                            id: "btn-downgrade",
                            label: "v2.1.98 Downgrade",
                            iconText: "⬇",
                            backgroundColor: "#8B0000",
                            tooltip: "Hidden Token Issue (v2).1.100Last stable version to avoid (post-)",
                            action: term("npm uninstall -g @anthropic-ai/claude-code && npm install -g @anthropic-ai/claude-code@2.1.98 && echo 'Downgrade complete: v2.1.98'")
                        ),
                        ButtonDefinition(
                            id: "btn-upgrade-latest",
                            label: "Update to latest version",
                            iconText: "⬆",
                            tooltip: "Claude Code Update to latest version",
                            action: term("npm install -g @anthropic-ai/claude-code@latest && claude --version")
                        ),
                        ButtonDefinition(
                            id: "btn-check-version",
                            label: "Version Check",
                            iconText: "📋",
                            tooltip: "Display Current Claude Code Version",
                            action: term("claude --version")
                        ),
                    ]
                ),
            ]
        )
    }

    public func writeDefaultConfigIfNeeded() throws {
        let fm = FileManager.default
        let loader = ConfigLoader(baseURL: baseURL)
        try loader.ensureDirectories()

        let configURL = baseURL.appendingPathComponent("config.json")
        if !fm.fileExists(atPath: configURL.path) {
            try saveAppConfig(AppConfig())
        }

        // The "default" (Claude Code sample) preset is a bundled showcase,
        // so it belongs in the seed area, not the user-presets directory.
        let defaultPresetURL = baseURL.appendingPathComponent("presets/default.json")
        if !fm.fileExists(atPath: defaultPresetURL.path) {
            let preset = Self.makeDefaultPreset()
            try savePresetToSeed(preset)
        }
    }
}
