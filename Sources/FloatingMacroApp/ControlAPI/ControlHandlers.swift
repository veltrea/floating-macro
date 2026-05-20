import Foundation
import AppKit
import FloatingMacroCore

/// Endpoints served by the FloatingMacroApp control API.
///
/// All endpoints are JSON-in / JSON-out, bound to 127.0.0.1 only, no auth.
/// Intended audience: this user's own tooling (CLI, AI assistant, scripts).
/// Not intended for exposure to other hosts.
///
/// The registered handler runs on the ControlServer's own queue, which is
/// explicitly NOT the main queue. Any AppKit interaction must hop to the
/// main queue. We use a helper `onMainSync` that blocks until the main-queue
/// work completes so the response reflects the post-operation state.
final class ControlHandlers {

    let presetManager: PresetManager
    weak var panel: NSPanel?
    /// Phase 3 で導入。複数パネル制御 (panel_* ツール) のために PanelManager を
    /// 持つ。weak に保持して循環参照を避ける（PanelManager は AppDelegate が所有）。
    weak var panelManager: PanelManager?
    let logURL: URL

    init(presetManager: PresetManager, panel: NSPanel?,
         panelManager: PanelManager?, logURL: URL) {
        self.presetManager = presetManager
        self.panel = panel
        self.panelManager = panelManager
        self.logURL = logURL
    }

    /// Build a handler closure suitable for `ControlServer.Handler`. All AppKit
    /// / presetManager work is explicitly hopped to the main queue inside.
    ///
    /// **Phase 5 Fast path**: Web Panel の read-only ルート (HTML/CSS/JS/icon)
    /// は main を経由せず接続キューで直接処理する。これがないと iPhone から
    /// の並列画像リクエストが main 1 本に直列化されて遅い。読み取り対象は
    /// すべて thread-safe なヘルパで覆われている (WebPanelAssets,
    /// EphemeralLANTokenStore, WebPanelIconRenderer)。
    func makeHandler() -> ControlServer.Handler {
        return { [self] request in
            if Self.isWebPanelReadOnlyRoute(request) {
                return self.dispatchWebPanelReadOnly(request)
            }
            return onMainSync { self.dispatch(request) }
        }
    }

    private static func isWebPanelReadOnlyRoute(_ req: HTTPRequest) -> Bool {
        guard req.method == .GET else { return false }
        switch req.path {
        case "/webpanel",
             "/webpanel/style.css",
             "/webpanel/app.js",
             "/webpanel/icon":
            return true
        default:
            return false
        }
    }

    /// main を経由しない高速 dispatch。ここで呼ぶ非 MainActor ハンドラ
    /// は AppKit や presetManager の可変状態に触らない。
    private func dispatchWebPanelReadOnly(_ req: HTTPRequest) -> HTTPResponse {
        switch req.path {
        case "/webpanel":           return handleWebPanelHTML_nonMain(req)
        case "/webpanel/style.css": return handleWebPanelAsset_nonMain(.css)
        case "/webpanel/app.js":    return handleWebPanelAsset_nonMain(.js)
        case "/webpanel/icon":      return handleWebPanelIcon_nonMain(req)
        default: return HTTPResponse.notFound(req.path)
        }
    }

    /// `appConfig.controlAPI.lanExposureEnabled` のスレッドセーフ読み取り。
    /// PresetManager の `@Published var appConfig` は main で更新されるが、
    /// プロパティ読み取りは原子的なので "ほぼ最新" を取れる。LAN トグルは
    /// 頻繁に切り替わらないのでこの程度の整合性で十分。
    var lanExposureEnabledSnapshot: Bool {
        return presetManager.appConfig?.controlAPI.lanExposureEnabled ?? false
    }

    // MARK: - Routing

    @MainActor
    private func dispatch(_ req: HTTPRequest) -> HTTPResponse {
        switch (req.method, req.path) {
        case (.GET,  "/manifest"):              return handleManifest()
        case (.GET,  "/help"):                  return handleManifest()
        case (.GET,  "/openapi.json"):          return handleOpenAPI()
        case (.GET,  "/.well-known/agent.json"):return handleAgentCard()
        case (.POST, "/mcp"):                   return handleMCP(req)
        case (.GET,  "/ping"):                  return handlePing()
        case (.GET,  "/state"):           return handleState()
        case (.GET,  "/key-codes"):       return handleKeyCodes()
        case (.POST, "/window/show"):     return handleWindowShow()
        case (.POST, "/window/hide"):     return handleWindowHide()
        case (.POST, "/window/toggle"):   return handleWindowToggle()
        case (.POST, "/window/opacity"):  return handleWindowOpacity(req)
        case (.POST, "/window/move"):     return handleWindowMove(req)
        case (.POST, "/window/resize"):   return handleWindowResize(req)
        // Phase 3: multi-panel controls
        case (.GET,  "/panel/list"):      return handlePanelList()
        case (.POST, "/panel/create"):    return handlePanelCreate(req)
        case (.POST, "/panel/close"):     return handlePanelClose(req)
        case (.POST, "/panel/show"):      return handlePanelShow(req)
        case (.POST, "/panel/hide"):      return handlePanelHide(req)
        // Phase 3.6: id 指定の per-panel 操作
        case (.POST, "/panel/move"):       return handlePanelMove(req)
        case (.POST, "/panel/resize"):     return handlePanelResize(req)
        case (.POST, "/panel/opacity"):          return handlePanelOpacity(req)
        case (.POST, "/panel/background-color"): return handlePanelBackgroundColor(req)
        case (.POST, "/panel/set-preset"):       return handlePanelSetPreset(req)
        // Phase 3.5: edge dock
        case (.POST, "/panel/dock"):      return handlePanelDock(req)
        case (.POST, "/panel/undock"):    return handlePanelUndock(req)
        case (.POST, "/panel/reset-dock-position"): return handlePanelResetDockPosition(req)
        case (.POST, "/panel/gather-dock-bars"):    return handlePanelGatherDockBars()
        case (.GET,  "/panel/snapshot"):  return handlePanelSnapshot(req)
        case (.POST, "/settings/open"):              return handleSettingsOpen()
        case (.GET,  "/settings/snapshot"):           return handleSettingsSnapshot()
        case (.POST, "/settings/close"):             return handleSettingsClose()
        case (.POST, "/ai-integration/open"):        return handleAIIntegrationOpen()
        case (.POST, "/ai-integration/close"):       return handleAIIntegrationClose()
        case (.POST, "/settings/open-sf-picker"):   return handleSettingsOpenSFPicker()
        case (.POST, "/settings/select-button"):    return handleSettingsSelectButton(req)
        case (.POST, "/settings/select-group"):     return handleSettingsSelectGroup(req)
        case (.POST, "/settings/open-app-icon-picker"): return handleSettingsOpenAppIconPicker()
        case (.POST, "/settings/dismiss-picker"):    return handleSettingsDismissPicker()
        case (.POST, "/settings/clear-selection"):  return handleSettingsClearSelection()
        case (.POST, "/settings/move"):                    return handleSettingsMove(req)
        case (.POST, "/settings/commit"):               return handleSettingsCommit()
        case (.POST, "/settings/set-background-color"): return handleSettingsSetBackgroundColor(req)
        case (.POST, "/settings/set-text-color"):       return handleSettingsSetTextColor(req)
        case (.POST, "/arrange"):                        return handleArrange(req)
        case (.POST, "/settings/set-action-type"):  return handleSettingsSetActionType(req)
        case (.POST, "/settings/set-key-combo"):    return handleSettingsSetKeyCombo(req)
        case (.POST, "/settings/set-action-value"): return handleSettingsSetActionValue(req)
        case (.POST, "/preset/reload"):   return handlePresetReload()
        case (.POST, "/preset/switch"):   return handlePresetSwitch(req)
        case (.GET,  "/preset/list"):     return handlePresetList()
        case (.POST, "/preset/create"):   return handlePresetCreate(req)
        case (.POST, "/preset/rename"):   return handlePresetRename(req)
        case (.POST, "/preset/delete"):   return handlePresetDelete(req)
        case (.GET,  "/preset/current"):  return handlePresetCurrent()
        case (.GET,  "/preset/get"):      return handlePresetGet(req)
        case (.POST, "/preset/export"):        return handlePresetExport(req)
        case (.POST, "/preset/export-bundle"): return handlePresetExportBundle()
        case (.POST, "/preset/import"):        return handlePresetImport(req)
        case (.POST, "/preset/install-seeds"): return handlePresetInstallSeeds(req)
        case (.POST, "/preset/reorder"):  return handlePresetReorder(req)
        case (.POST, "/group/add"):       return handleGroupAdd(req)
        case (.POST, "/group/update"):    return handleGroupUpdate(req)
        case (.POST, "/group/delete"):    return handleGroupDelete(req)
        case (.POST, "/button/add"):      return handleButtonAdd(req)
        case (.POST, "/button/update"):   return handleButtonUpdate(req)
        case (.POST, "/button/delete"):   return handleButtonDelete(req)
        case (.POST, "/button/reorder"):  return handleButtonReorder(req)
        case (.POST, "/button/move"):     return handleButtonMove(req)
        case (.POST, "/button/press"):    return handleButtonPress(req)
        case (.POST, "/action"):          return handleAction(req)
        case (.GET,  "/log/tail"):        return handleLogTail(req)
        case (.GET,  "/icon/for-app"):    return handleIconForApp(req)
        case (.GET,  "/tools"):           return handleToolsList(req)
        case (.POST, "/tools/call"):      return handleToolsCall(req)
        // Phase 5: Web Panel (LAN 公開モード時にスマホ/タブレットから到達)
        case (.GET,  "/webpanel"):           return handleWebPanelHTML(req)
        case (.GET,  "/webpanel/style.css"): return handleWebPanelAsset(.css)
        case (.GET,  "/webpanel/app.js"):    return handleWebPanelAsset(.js)
        case (.POST, "/webpanel/tools/call"):return handleWebPanelToolsCall(req)
        case (.GET,  "/webpanel/icon"):      return handleWebPanelIcon(req)
        // Phase 5: Mac 側 (Bearer 認証経由) から ephemeral LAN token を取得する
        // 管理用エンドポイント。Block 3 で QR 生成 UI が利用する。Web Panel
        // 経由 (/webpanel/*) からは到達できないので外部漏洩は loopback の
        // Bearer トークン経由のみ。
        case (.GET,  "/lan-token"):     return handleLANTokenInfo()
        case (.POST, "/lan-token/rotate"): return handleLANTokenRotate()
        // ACP (Agent Communication Protocol) — stateless / sync subset.
        case (.GET,  "/agents"):                  return handleACPAgentsList()
        case (.GET,  "/agents/floatingmacro"):    return handleACPAgentManifest()
        case (.POST, "/runs"):                    return handleACPRunsCreate(req)
        case (_, let p) where p.hasPrefix("/runs/") || p.hasPrefix("/sessions"):
            return HTTPResponse.json(
                ["error": "not implemented",
                 "detail": "this agent is stateless / sync-only; no run lifecycle, sessions, events, resume, or cancel"],
                status: 501
            )
        case (_,     let path):           return HTTPResponse.notFound(path)
        }
    }

    /// Build a synthetic HTTPRequest targeting `tool`'s real endpoint, then
    /// re-enter the dispatcher. Shared by /tools/call, /mcp, and /runs.
    @MainActor
    func invokeToolByDispatch(tool: ToolDefinition,
                                      arguments: [String: Any],
                                      headers: [String: String] = [:]) -> HTTPResponse {
        var newPath = tool.path
        var body = Data()
        if tool.method == "GET" && !arguments.isEmpty {
            let pairs = arguments.compactMap { (k, v) -> String? in
                guard let enc = "\(v)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
                return "\(k)=\(enc)"
            }
            if !pairs.isEmpty {
                newPath += newPath.contains("?") ? "&" : "?"
                newPath += pairs.joined(separator: "&")
            }
        } else if tool.method != "GET" {
            body = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data()
        }

        let (innerPath, innerQuery) = HTTPParser.splitPathAndQuery(newPath)
        let synthetic = HTTPRequest(
            method: HTTPMethod(rawValue: tool.method) ?? .POST,
            rawTarget: newPath,
            path: innerPath,
            query: innerQuery,
            headers: headers,
            body: body
        )
        return dispatch(synthetic)
    }
    @MainActor
    private func handlePing() -> HTTPResponse {
        HTTPResponse.json(["ok": true, "product": "FloatingMacro"])
    }

    /// 正規キー名カタログ。`settings_set_key_combo` や `button_add` 等の `combo`
    /// 文字列にそのまま使える名前を、AI が discoverable にするためのエンドポイント。
    @MainActor
    private func handleKeyCodes() -> HTTPResponse {
        func encode(_ entries: [KeyCombo.KeyEntry]) -> [[String: String]] {
            entries.map { ["name": $0.name, "label": $0.label] }
        }
        let body: [String: Any] = [
            "modifiers": KeyCombo.modifierNames,
            "modifierAliases": KeyCombo.modifierAliases,
            "specialKeys": encode(KeyCombo.specialKeys),
            "functionKeys": encode(KeyCombo.functionKeys),
            "keyAliases": KeyCombo.keyAliases,
            "examples": [
                "cmd+shift+v",
                "f5",
                "cmd+left",
                "delete",
                "option+forwarddelete",
                "ctrl+pageup",
            ],
            "notes": "Compose with '+'. Modifier order is normalized internally. Letters/digits and US-layout symbols (a-z, 0-9, =, -, [, ], ;, ', \\, comma, period, slash, backtick) are also accepted as base keys."
        ]
        return HTTPResponse.json(body)
    }

    @MainActor
    private func handleState() -> HTTPResponse {
        var body: [String: Any] = [
            "visible": panel?.isVisible ?? false,
            "activePreset": presetManager.currentPreset?.name as Any? ?? NSNull(),
            "displayName":  presetManager.currentPreset?.displayName as Any? ?? NSNull(),
            "memo":         presetManager.currentPreset?.memo as Any? ?? NSNull(),
            "errorMessage": presetManager.errorMessage as Any? ?? NSNull(),
        ]
        if let w = presetManager.appConfig?.window {
            body["window"] = [
                "x": w.x, "y": w.y,
                "width": w.width, "height": w.height,
                "opacity": w.opacity,
                "orientation": w.orientation,
                "alwaysOnTop": w.alwaysOnTop,
            ]
        }
        if let f = panel?.frame {
            body["actualFrame"] = [
                "x": Double(f.origin.x),
                "y": Double(f.origin.y),
                "width": Double(f.size.width),
                "height": Double(f.size.height),
            ]
        }
        return HTTPResponse.json(body)
    }

    @MainActor
    private func handleWindowShow() -> HTTPResponse {
        panel?.orderFront(nil)
        return HTTPResponse.json(["visible": panel?.isVisible ?? false])
    }

    @MainActor
    private func handleWindowHide() -> HTTPResponse {
        panel?.orderOut(nil)
        return HTTPResponse.json(["visible": panel?.isVisible ?? false])
    }

    @MainActor
    private func handleWindowToggle() -> HTTPResponse {
        guard let p = panel else {
            return HTTPResponse.internalError("panel not initialized")
        }
        if p.isVisible { p.orderOut(nil) } else { p.orderFront(nil) }
        return HTTPResponse.json(["visible": p.isVisible])
    }

    @MainActor
    private func handleWindowOpacity(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let value = (dict["value"] as? NSNumber)?.doubleValue else {
            return HTTPResponse.badRequest("body must be {\"value\": Double}")
        }
        presetManager.setOpacity(value)
        let clamped = presetManager.appConfig?.window.opacity ?? value
        panel?.alphaValue = CGFloat(clamped)
        return HTTPResponse.json(["opacity": clamped])
    }

    @MainActor
    private func handlePresetReload() -> HTTPResponse {
        presetManager.loadInitialConfig()
        return HTTPResponse.json([
            "activePreset": presetManager.currentPreset?.name as Any? ?? NSNull(),
        ])
    }

    @MainActor
    private func handlePresetSwitch(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must be {\"name\": String}")
        }
        presetManager.switchPreset(to: name)
        return HTTPResponse.json([
            "activePreset": presetManager.currentPreset?.name as Any? ?? NSNull(),
            "loaded": presetManager.currentPreset?.name == name,
        ])
    }

    @MainActor
    private func handlePresetList() -> HTTPResponse {
        let active = presetManager.appConfig?.activePreset
        // Iterate over presetEntries so the response reflects the user's
        // chosen display order (see preset_reorder), not the raw filesystem
        // alphabetical sort.
        let list: [[String: Any]] = presetManager.presetEntries.map { entry in
            ["name": entry.name,
             "displayName": entry.displayName,
             "active": entry.name == active]
        }
        return HTTPResponse.json(["presets": list])
    }

    @MainActor
    private func handleAction(_ req: HTTPRequest) -> HTTPResponse {
        guard let action = req.jsonBody(as: Action.self) else {
            return HTTPResponse.badRequest("body must be a valid Action JSON")
        }
        // Capture blacklist at dispatch time (presetManager is main-actor bound,
        // but we're already on the main queue here via onMainSync).
        let blacklist = presetManager.appConfig?.commandBlacklist
        // Fire the action asynchronously; respond immediately with 202.
        Task.detached {
            do {
                let onBlocked: MacroRunner.BlockedCommandHandler = { pattern, text in
                    await MainActor.run {
                        CommandConfirmation.askProceed(pattern: pattern, text: text)
                    }
                }
                try await Self.runAction(action, blacklist: blacklist, onBlocked: onBlocked)
            } catch {
                LoggerContext.shared.error("ControlAPI", "Action failed", [
                    "error": String(describing: error),
                ])
            }
        }
        return HTTPResponse.json(["accepted": true], status: 202)
    }

    // MARK: - Window move / resize

    @MainActor
    private func handleWindowMove(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let x = (dict["x"] as? NSNumber)?.doubleValue,
              let y = (dict["y"] as? NSNumber)?.doubleValue else {
            return HTTPResponse.badRequest("body must be {\"x\": Double, \"y\": Double}")
        }
        guard let p = panel else {
            return HTTPResponse.internalError("panel not initialized")
        }
        var frame = p.frame
        frame.origin.x = CGFloat(x)
        frame.origin.y = CGFloat(y)
        p.setFrame(frame, display: true, animate: false)
        presetManager.setPanelFrame(
            x: Double(frame.origin.x), y: Double(frame.origin.y),
            width: Double(frame.size.width), height: Double(frame.size.height)
        )
        return HTTPResponse.json([
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
        ])
    }

    @MainActor
    private func handleWindowResize(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let w = (dict["width"]  as? NSNumber)?.doubleValue,
              let h = (dict["height"] as? NSNumber)?.doubleValue else {
            return HTTPResponse.badRequest("body must be {\"width\": Double, \"height\": Double}")
        }
        guard let p = panel else {
            return HTTPResponse.internalError("panel not initialized")
        }
        var frame = p.frame
        frame.size.width = max(120, CGFloat(w))
        frame.size.height = max(80, CGFloat(h))
        p.setFrame(frame, display: true, animate: false)
        presetManager.setPanelFrame(
            x: Double(frame.origin.x), y: Double(frame.origin.y),
            width: Double(frame.size.width), height: Double(frame.size.height)
        )
        return HTTPResponse.json([
            "width":  Double(frame.size.width),
            "height": Double(frame.size.height),
        ])
    }

    // MARK: - Icon

    @MainActor
    private func handleIconForApp(_ req: HTTPRequest) -> HTTPResponse {
        let bid = req.query["bundleId"]
        let path = req.query["path"]
        guard bid != nil || path != nil else {
            return HTTPResponse.badRequest("provide ?bundleId= or ?path=")
        }
        guard let data = IconLoader.pngForApp(bundleIdentifier: bid, path: path) else {
            return HTTPResponse.json(["error": "icon not found"], status: 404)
        }
        let base64 = data.base64EncodedString()
        let body: [String: Any] = [
            "bundleId":   bid as Any? ?? NSNull(),
            "path":       path as Any? ?? NSNull(),
            "bytes":      data.count,
            "png_base64": base64,
        ]
        return HTTPResponse.json(body)
    }

    // MARK: - Log tail (existing)

    @MainActor
    private func handleLogTail(_ req: HTTPRequest) -> HTTPResponse {
        let level = req.query["level"].flatMap(LogLevel.parse)
        let since = req.query["since"].flatMap(Self.parseDuration)
        let limit = req.query["limit"].flatMap(Int.init)

        guard FileManager.default.fileExists(atPath: logURL.path),
              let raw = try? String(contentsOf: logURL, encoding: .utf8) else {
            return HTTPResponse.json(["events": [String]()])
        }

        let cutoff = since.map { Date().addingTimeInterval(-$0) }
        var events: [[String: Any]] = []
        let decoder = JSONDecoder.fmLogDecoder

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(LogEvent.self, from: data) else { continue }
            if let level = level, event.level < level { continue }
            if let cutoff = cutoff, event.timestamp < cutoff { continue }
            // Re-emit as a plain dict (matches the on-disk JSON shape).
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                events.append(obj)
            }
        }
        if let limit = limit, events.count > limit {
            events = Array(events.suffix(limit))
        }
        return HTTPResponse.json(["events": events])
    }

    // MARK: - Helpers

    nonisolated private static func parseDuration(_ s: String) -> TimeInterval? {
        guard !s.isEmpty, let last = s.last else { return nil }
        let body = s.dropLast()
        guard let n = Double(body) else {
            return Double(s)
        }
        switch last {
        case "s": return n
        case "m": return n * 60
        case "h": return n * 3600
        case "d": return n * 86400
        default:  return Double(s)
        }
    }

    nonisolated private static func runAction(_ action: Action,
                                              blacklist: CommandBlacklist? = nil,
                                              onBlocked: MacroRunner.BlockedCommandHandler? = nil) async throws {
        // Blacklist check for direct terminal/text actions.
        if let bl = blacklist, !bl.autopilotEnabled {
            switch action {
            case .terminal(_, let command, _, _, _):
                if let pattern = CommandGuard.check(command, against: bl) {
                    if let handler = onBlocked {
                        let proceed = await handler(pattern, command)
                        if !proceed { throw ActionError.commandBlocked(pattern: pattern) }
                    } else {
                        throw ActionError.commandBlocked(pattern: pattern)
                    }
                }
            case .text(let content, _, _, _):
                if let pattern = CommandGuard.check(content, against: bl) {
                    if let handler = onBlocked {
                        let proceed = await handler(pattern, content)
                        if !proceed { throw ActionError.commandBlocked(pattern: pattern) }
                    } else {
                        throw ActionError.commandBlocked(pattern: pattern)
                    }
                }
            default: break
            }
        }
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
            try await MacroRunner.run(actions: actions, stopOnError: stopOnError,
                                      blacklist: blacklist, onBlocked: onBlocked)
        }
    }
}

/// Run `block` synchronously on the main queue and return its value.
/// Safe to call from any background queue. If called on the main queue,
/// executes immediately to avoid deadlock.
nonisolated func onMainSync<T>(_ block: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { block() }
    } else {
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { block() }
        }
    }
}

/// Bearer トークン認証ミドルウェア。
///
/// `token` が `nil` のときは認証なしでスルーする（testMode 用）。
/// `/ping` と `/health` は認証除外（死活監視用）。
/// それ以外のエンドポイントは `Authorization: Bearer <token>` が必須。
func wrapWithAuth(token: String?,
                  handler: @escaping ControlServer.Handler) -> ControlServer.Handler {
    return { req in
        guard let expectedToken = token else { return handler(req) }

        // Discovery endpoints must be reachable without a token: an AI agent
        // bootstraps by GET /manifest (or /.well-known/agent.json) to learn
        // *that* a token is required and *how* to obtain one. Gating these
        // behind auth would create a chicken-and-egg problem. Action-executing
        // endpoints below the discovery layer remain protected.
        let publicPaths: Set<String> = [
            "/ping", "/health",
            "/manifest", "/help",
            "/.well-known/agent.json",
            "/openapi.json",
            // ACP discovery: clients must be able to find the agent and read
            // its manifest before authenticating, mirroring /manifest.
            "/agents",
            "/agents/floatingmacro",
        ]
        if publicPaths.contains(req.path) { return handler(req) }

        // Phase 5: Web Panel 系は ephemeral LAN token で独自に守られている
        // (handleWebPanel* の中でクエリ / Authorization を検証する) ため、
        // 永続 Bearer トークン認証はスキップする。これがないとスマホは
        // 永続トークンを知らないので /webpanel に到達した時点で 401 になる。
        if req.path.hasPrefix("/webpanel") { return handler(req) }

        guard let authHeader = req.header("Authorization"),
              authHeader.hasPrefix("Bearer "),
              authHeader.dropFirst("Bearer ".count) == expectedToken else {
            return HTTPResponse(
                status: 401,
                reason: "Unauthorized",
                headers: [
                    ("Content-Type", "application/json"),
                    ("WWW-Authenticate", #"Bearer realm="FloatingMacro""#),
                ],
                body: #"{"error":"invalid or missing token"}"#.data(using: .utf8)!
            )
        }

        return handler(req)
    }
}
