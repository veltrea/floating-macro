import SwiftUI
import AppKit
import FloatingMacroCore

/// Independent view for AI integration window. FloatingMacro is an AI (Claude Code /
/// Initial setup to allow Cursor, Gemini CLI, ChatGPT, etc. to perform actions
/// One-click operation.
///
/// Design decision: The Settings window is made into a separate window instead of a tab in the Settings window.
/// Settings is a tool for editing objects individually, while "button editing" refers to a specific type of edit operation.
/// This view is for "initial setup across the entire app", with a different granularity of UI.
/// When placed in the same window, there is a mix of per-button operation and app-wide operation.
/// To avoid confusion, treat it as a separate window called from `AIIntegrationWindowController`.
///
/// Provided Operations:
/// Copy connection prompt to clipboard for AI attachment
/// Embedding Bearer token — Paste directly for AI to read via /manifest
/// Understand the introduction and subsequent operation methods)
/// 2. Claude Code ( ~/.claude.json ) One-click Register MCP Entry
/// FloatingMacro will automatically connect the next time Claude Code is launched.
struct AIIntegrationView: View {
    @ObservedObject var presetManager: PresetManager
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @State private var promptPreview: String = ""

    private var port: Int {
        presetManager.appConfig?.controlAPI.port ?? 17430
    }

    private var endpoint: String {
        "http://127.0.0.1:\(port)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Overview - Summary
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("AI_To operate _FloatingMacro_ with 943488"))
                        .font(.title3).fontWeight(.semibold)
                    Text(L_("ai_integration_intro", endpoint))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Action 1: Copy Prompt
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                        Text(L("Copy prompt for connection _b93ac4")).font(.headline)
                    }

                    Text(L("Claude_Code_Cursor_ChatGPT_Paste prompt to _AI_ clipboar_6e9f0f"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(action: copyConnectionPrompt) {
                            Label(L("Copy Prompt 2e89f7"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: { promptPreview = makeConnectionPrompt(token: tokenForPreview()) }) {
                            Text(L("Update Preview 87a7d8"))
                        }
                        .buttonStyle(.bordered)
                    }

                    if !promptPreview.isEmpty {
                        ScrollView(.vertical) {
                            Text(promptPreview)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(maxHeight: 180)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

                // Action 2: Register each AI client with MCP
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2")
                        Text(L("AI_Register _MCP_ with Client 824251")).font(.headline)
                    }

                    Text(L("Adds a _floatingmacro_ entry to the configuration file of the corresponding AI client. c9c660"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        registerRow(
                            icon: "checkmark.shield",
                            title: "Claude Code",
                            subtitle: "~/.claude.json",
                            httpAction: registerClaudeCodeMCP,
                            stdioAction: registerClaudeCodeStdio
                        )
                        registerRow(
                            icon: "cursorarrow.rays",
                            title: "Cursor",
                            subtitle: "~/.cursor/mcp.json",
                            httpAction: registerCursorMCP,
                            stdioAction: registerCursorStdio
                        )
                        registerRow(
                            icon: "terminal",
                            title: "Gemini CLI",
                            subtitle: "~/.gemini/settings.json",
                            httpAction: registerGeminiCLIMCP,
                            stdioAction: registerGeminiCLIStdio
                        )
                        registerRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            title: "VS Code",
                            subtitle: "~/Library/Application Support/Code/User/mcp.json",
                            httpAction: registerVSCodeMCP,
                            stdioAction: registerVSCodeStdio
                        )
                        registerRow(
                            icon: "wind",
                            title: "Windsurf",
                            subtitle: "~/.codeium/windsurf/mcp_config.json",
                            httpAction: registerWindsurfMCP,
                            stdioAction: registerWindsurfStdio
                        )
                    }

                    Text(L("CLI_Register Blue via fmcli command line tool Recommended HTTP Registration f02e39"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L("Claude_Desktop_Trae_Antigravity_Registration button not provided"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

                // Connection information (reference)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Connection info_4b0c51")).font(.headline)
                    HStack(spacing: 6) {
                        Text(L("Endpoint 5b5897")).foregroundColor(.secondary)
                        Text(endpoint).font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        CopyInlineButton(text: endpoint)
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Text(L("Token acquisition_5a8f8c")).foregroundColor(.secondary)
                        Text("security find-generic-password -s FloatingMacro -a ControlAPIToken -w")
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        CopyInlineButton(text: "security find-generic-password -s FloatingMacro -a ControlAPIToken -w")
                    }
                    Text(L("Authentication Required Discovery GET Manifest Help Well Known Agent JS 23e1fc"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Result message -------------------------------------------
                if !statusMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(statusIsError ? .orange : .green)
                        Text(statusMessage)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background((statusIsError ? Color.orange : Color.green).opacity(0.12))
                    .cornerRadius(6)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func copyConnectionPrompt() {
        guard let token = loadToken() else {
            setStatus(L("Keychain_Failed to retrieve token from .965772"), isError: true)
            return
        }
        let prompt = makeConnectionPrompt(token: token)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        setStatus(L_("copied_to_clipboard_chars", prompt.count), isError: false)
    }

    private func registerClaudeCodeMCP() {
        registerHTTPMCP(
            clientName: "Claude Code",
            relativePath: "~/.claude.json",
            rootKey: "mcpServers",
            entry: { token in [
                "type": "http",
                "url":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerCursorMCP() {
        // Write the URL and headers to the mcpServers in ~/.cursor/mcp.json.
        // The latest Cursor determines the type based on the presence of URL (no need for explicit type).
        registerHTTPMCP(
            clientName: "Cursor",
            relativePath: "~/.cursor/mcp.json",
            rootKey: "mcpServers",
            entry: { token in [
                "url":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerGeminiCLIMCP() {
        // Gemini CLI: The mcpServers in ~/.gemini/settings.json
        // Write {httpUrl, headers}. The Gemini CLI writes the httpUrl field.
        // Map to StreamableHTTPClientTransport (URL is for SSE, separate).
        registerHTTPMCP(
            clientName: "Gemini CLI",
            relativePath: "~/.gemini/settings.json",
            rootKey: "mcpServers",
            entry: { token in [
                "httpUrl":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerVSCodeMCP() {
        // VS Code: New specification's ~/Library/Application Support/Code/User/mcp.json
        // Use it. The root key is "servers" (different from other clients' "mcpServers").
        // "type" is "http".
        registerHTTPMCP(
            clientName: "VS Code",
            relativePath: "~/Library/Application Support/Code/User/mcp.json",
            rootKey: "servers",
            entry: { token in [
                "type": "http",
                "url":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    private func registerWindsurfMCP() {
        // Windsurf: The mcpServers in the mcpConfig.json file located at ~/.codeium/windsurf/mcp_config.json.
        // Write {serverUrl, headers} (URL field name differs from others).
        registerHTTPMCP(
            clientName: "Windsurf",
            relativePath: "~/.codeium/windsurf/mcp_config.json",
            rootKey: "mcpServers",
            entry: { token in [
                "serverUrl":  "\(endpoint)/mcp",
                "headers": ["Authorization": "Bearer \(token)"],
            ] }
        )
    }

    /// Common implementation to append a floatingmacro entry to each client's configuration file (HTTP version).
    /// If the file exists, load it as JSON without breaking existing settings.
    /// Insert the key "floatingmacro" under the specified rootKey with overwrite.
    /// Create the parent directory if it does not exist (e.g., ~/.cursor/, ~/.gemini/).
    private func registerHTTPMCP(
        clientName: String,
        relativePath: String,
        rootKey: String,
        entry: (String) -> [String: Any]
    ) {
        guard let token = loadToken() else {
            setStatus(L("Keychain_Failed to retrieve token from .965772"), isError: true)
            return
        }
        writeServerEntry(
            clientName: clientName,
            mode: "HTTP",
            relativePath: relativePath,
            rootKey: rootKey,
            serverName: "floatingmacro",
            entryDict: entry(token)
        )
    }

    /// Common implementation for registering via Node.js-based MCP server (stdio version).
    /// Use "floatingmacro-stdio" fixed to avoid collision with HTTP version.
    ///
    /// System:
    /// Packed in the app bundle (Contents/Resources/npm/)
    /// Node.js-based MCP server (npm package) for user environment
    /// Launch from local file path via npx.
    /// 2. Authentication token is passed via args (no need for Keychain access).
    /// The absolute path of npx is read from ~/.zshrc and ~/.bash_profile in a login shell.
    /// Solved via (each AI client does not inherit PATH).
    private func registerStdioMCP(
        clientName: String,
        relativePath: String,
        rootKey: String,
        entry: (_ shellPath: String, _ packageRef: String, _ token: String) -> [String: Any]
    ) {
        guard let token = loadToken() else {
            setStatus(L("Keychain_Failed to retrieve token from .965772"), isError: true)
            return
        }
        guard let bundleNpmPath = bundledNpmPackagePath() else {
            setStatus(L("No npm package found in the bundle Contents/Resources/2fa8e7"), isError: true)
            return
        }
        // Launch npx via the user's login shell.
        // All installation methods for fnm, nvm, and Homebrew require that the login shell be
        // Reads ~/.zshrc and ~/.bash_profile to assemble the PATH.
        // No need to directly write the absolute path of npx in the configuration file (session of fnm)
        // The unique shim path becomes invalid after the shell exits, making absolute paths vulnerable).
        let loginShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let packageRef = "file:\(bundleNpmPath)"
        writeServerEntry(
            clientName: clientName,
            mode: "CLI",
            relativePath: relativePath,
            rootKey: rootKey,
            serverName: "floatingmacro-stdio",
            entryDict: entry(loginShell, packageRef, token)
        )
    }

    /// Absolute path to the npm package bundled with the app bundle.
    /// Assumes build-app.sh copies to Contents/Resources/npm/.
    /// Returns nil during development (such as swift run directly), and the caller throws an error.
    private func bundledNpmPackagePath() -> String? {
        guard let res = Bundle.main.resourcePath else { return nil }
        let path = res + "/npm"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        // Check if package.json exists briefly
        if !FileManager.default.fileExists(atPath: path + "/package.json") {
            return nil
        }
        return path
    }


    /// Common write logic for HTTP version and stdio version.
    /// Overwrite the serverName entry under rootKey by loading an existing file as JSON.
    /// Save atomically with parent directory automatically created if needed.
    private func writeServerEntry(
        clientName: String,
        mode: String,
        relativePath: String,
        rootKey: String,
        serverName: String,
        entryDict: [String: Any]
    ) {
        let url = URL(fileURLWithPath: NSString(string: relativePath).expandingTildeInPath)
        var dict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                if !data.isEmpty,
                   let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    dict = parsed
                }
            } catch {
                setStatus(L_("cannot_read_existing_file", relativePath, error.localizedDescription), isError: true)
                return
            }
        }
        var servers = dict[rootKey] as? [String: Any] ?? [:]
        servers[serverName] = entryDict
        dict[rootKey] = servers
        do {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true)
            let out = try JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys])
            try out.write(to: url, options: .atomic)
            setStatus(L_("registered_to_client", clientName, mode, serverName, clientName), isError: false)
        } catch {
            setStatus(L_("write_to_client_failed", clientName, error.localizedDescription), isError: true)
        }
    }

    /// Each client's registration button line. Icon + client name + path +
    /// "CLI Registration" (primary, blue) + "HTTP Registration" (auxiliary, frame) side by side.
    @ViewBuilder
    private func registerRow(
        icon: String,
        title: String,
        subtitle: String,
        httpAction: @escaping () -> Void,
        stdioAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: stdioAction) {
                Text(L("CLI_register_d04aa3"))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(L("fmcli_CLI_Connect via Tool General Recommendation db8e1f"))
            Button(action: httpAction) {
                Text(L("HTTP_Register 441eee"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L("HTTP_Direct connection protocol for intermediate users e72f2b"))
        }
    }

    // MARK: - Stdio Version (Node.js-based NPM Package via) Per Client Registration
    //
    // Each function takes (shellPath, packageRef, token) and returns the corresponding client.
    // Returns a JSON entry conforming to the configuration file format.
    //
    // shellPath is the user's $SHELL (usually /bin/zsh). As a login shell,
    // Launch and load ~/.zshrc and ~/.bash_profile to load fnm/nvm/
    // How to install Node.js for users who already have it on their PATH and access npx via Homebrew:
    // Findable.

    /// Create common args: `<shell> -lc "exec npx -y <pkg> --token <token>"`
    private func stdioArgs(packageRef: String, token: String) -> [String] {
        // Enclose single-quote to protect token / pkg from shell metacharacters.
        // The token is a 64-character hex string with no dangerous characters, just in case.
        // Single quotes do not need to be used within strings (neither token nor pkg).
        let inner = "exec npx -y '\(packageRef)' --token '\(token)'"
        return ["-lc", inner]
    }

    private func registerClaudeCodeStdio() {
        registerStdioMCP(
            clientName: "Claude Code",
            relativePath: "~/.claude.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerCursorStdio() {
        registerStdioMCP(
            clientName: "Cursor",
            relativePath: "~/.cursor/mcp.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerGeminiCLIStdio() {
        registerStdioMCP(
            clientName: "Gemini CLI",
            relativePath: "~/.gemini/settings.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerVSCodeStdio() {
        // VS Code requires type: "stdio" for stdio cases (type: "http" is needed for the HTTP version).
        registerStdioMCP(
            clientName: "VS Code",
            relativePath: "~/Library/Application Support/Code/User/mcp.json",
            rootKey: "servers",
            entry: { shell, pkg, token in [
                "type": "stdio",
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    private func registerWindsurfStdio() {
        registerStdioMCP(
            clientName: "Windsurf",
            relativePath: "~/.codeium/windsurf/mcp_config.json",
            rootKey: "mcpServers",
            entry: { shell, pkg, token in [
                "command": shell,
                "args": self.stdioArgs(packageRef: pkg, token: token),
            ] }
        )
    }

    // MARK: - Helpers

    private func loadToken() -> String? {
        try? TokenStore.loadOrCreate()
    }

    private func tokenForPreview() -> String {
        loadToken() ?? L("Could not retrieve token from _Keychain_: b5eb4b")
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    /// Copy button placed on the right side of a string. Clicking copies to clipboard.
    /// Copy and change icon to ✓ in about 1.5 seconds for completion feedback.
    private struct CopyInlineButton: View {
        let text: String
        @State private var copied: Bool = false

        var body: some View {
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(copied ? .green : .secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L("Copy to Clipboard 8b7fd6"))
        }
    }

    private func makeConnectionPrompt(token: String) -> String {
        SystemPrompt.connectionPrompt(endpoint: endpoint, token: token)
    }
}
