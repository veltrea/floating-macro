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

    private let presetManager: PresetManager
    private weak var panel: NSPanel?
    private let logURL: URL

    init(presetManager: PresetManager, panel: NSPanel?, logURL: URL) {
        self.presetManager = presetManager
        self.panel = panel
        self.logURL = logURL
    }

    /// Build a handler closure suitable for `ControlServer.Handler`. All AppKit
    /// / presetManager work is explicitly hopped to the main queue inside.
    func makeHandler() -> ControlServer.Handler {
        return { [self] request in
            onMainSync { self.dispatch(request) }
        }
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
        case (.POST, "/window/show"):     return handleWindowShow()
        case (.POST, "/window/hide"):     return handleWindowHide()
        case (.POST, "/window/toggle"):   return handleWindowToggle()
        case (.POST, "/window/opacity"):  return handleWindowOpacity(req)
        case (.POST, "/window/move"):     return handleWindowMove(req)
        case (.POST, "/window/resize"):   return handleWindowResize(req)
        case (.POST, "/settings/open"):           return handleSettingsOpen()
        case (.POST, "/settings/close"):          return handleSettingsClose()
        case (.POST, "/settings/open-sf-picker"): return handleSettingsOpenSFPicker()
        case (.POST, "/preset/reload"):   return handlePresetReload()
        case (.POST, "/preset/switch"):   return handlePresetSwitch(req)
        case (.GET,  "/preset/list"):     return handlePresetList()
        case (.POST, "/preset/create"):   return handlePresetCreate(req)
        case (.POST, "/preset/rename"):   return handlePresetRename(req)
        case (.POST, "/preset/delete"):   return handlePresetDelete(req)
        case (.GET,  "/preset/current"):  return handlePresetCurrent()
        case (.POST, "/group/add"):       return handleGroupAdd(req)
        case (.POST, "/group/update"):    return handleGroupUpdate(req)
        case (.POST, "/group/delete"):    return handleGroupDelete(req)
        case (.POST, "/button/add"):      return handleButtonAdd(req)
        case (.POST, "/button/update"):   return handleButtonUpdate(req)
        case (.POST, "/button/delete"):   return handleButtonDelete(req)
        case (.POST, "/button/reorder"):  return handleButtonReorder(req)
        case (.POST, "/button/move"):     return handleButtonMove(req)
        case (.POST, "/action"):          return handleAction(req)
        case (.GET,  "/log/tail"):        return handleLogTail(req)
        case (.GET,  "/icon/for-app"):    return handleIconForApp(req)
        case (.GET,  "/tools"):           return handleToolsList(req)
        case (.POST, "/tools/call"):      return handleToolsCall(req)
        case (_,     let path):           return HTTPResponse.notFound(path)
        }
    }

    // MARK: - Tool discovery & dispatch

    @MainActor
    private func handleToolsList(_ req: HTTPRequest) -> HTTPResponse {
        let dialect: ToolCatalog.Dialect
        switch (req.query["format"] ?? "mcp").lowercased() {
        case "openai":    dialect = .openai
        case "anthropic": dialect = .anthropic
        default:          dialect = .mcp
        }
        return HTTPResponse.json(ToolCatalog.render(dialect: dialect))
    }

    @MainActor
    private func handleToolsCall(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must be {name: String, arguments?: object}")
        }
        guard let tool = ToolCatalog.find(name) else {
            return HTTPResponse.json(
                ["error": "unknown tool", "name": name],
                status: 404
            )
        }
        // Build a synthetic HTTPRequest that targets the tool's real endpoint.
        let args = (dict["arguments"] as? [String: Any]) ?? [:]
        var newPath = tool.path
        var body = Data()
        if tool.method == "GET" && !args.isEmpty {
            // Encode arguments as query string.
            let pairs = args.compactMap { (k, v) -> String? in
                guard let enc = "\(v)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
                return "\(k)=\(enc)"
            }
            if !pairs.isEmpty {
                newPath += newPath.contains("?") ? "&" : "?"
                newPath += pairs.joined(separator: "&")
            }
        } else if tool.method != "GET" {
            body = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
        }

        let (innerPath, innerQuery) = HTTPParser.splitPathAndQuery(newPath)
        let synthetic = HTTPRequest(
            method: HTTPMethod(rawValue: tool.method) ?? .POST,
            rawTarget: newPath,
            path: innerPath,
            query: innerQuery,
            headers: req.headers,
            body: body
        )
        // Re-enter the dispatcher for the real endpoint.
        let inner = dispatch(synthetic)

        // Wrap the inner response so the caller gets a uniform envelope
        // compatible with MCP's tools/call result shape.
        var envelope: [String: Any] = [
            "name": name,
            "status": inner.status,
        ]
        if let innerObj = try? JSONSerialization.jsonObject(with: inner.body) {
            envelope["result"] = innerObj
        } else if let str = String(data: inner.body, encoding: .utf8) {
            envelope["result"] = str
        }
        return HTTPResponse.json(envelope, status: inner.status < 400 ? 200 : inner.status)
    }

    // MARK: - Endpoints

    @MainActor
    private func handleManifest() -> HTTPResponse {
        HTTPResponse.json(SystemPrompt.manifest())
    }

    @MainActor
    private func handleOpenAPI() -> HTTPResponse {
        HTTPResponse.json(OpenAPIGenerator.document())
    }

    @MainActor
    private func handleAgentCard() -> HTTPResponse {
        HTTPResponse.json(AgentCard.card())
    }

    /// JSON-RPC 2.0 / MCP endpoint. Bridges into the same REST handlers
    /// used by /tools/call so behavior is identical regardless of transport.
    @MainActor
    private func handleMCP(_ req: HTTPRequest) -> HTTPResponse {
        switch MCPAdapter.parseRequest(req.body) {
        case .failure(let errorResponse):
            let body = try? JSONSerialization.data(withJSONObject: errorResponse.serialize())
            return HTTPResponse(
                status: 200, reason: "OK",
                headers: [("Content-Type", "application/json")],
                body: body ?? Data()
            )
        case .success(let rpcRequest):
            let response = MCPAdapter.handle(rpcRequest) { [self] toolName, arguments in
                return callToolByName(toolName, arguments: arguments)
            }
            let body = try? JSONSerialization.data(withJSONObject: response.serialize())
            return HTTPResponse(
                status: 200, reason: "OK",
                headers: [("Content-Type", "application/json")],
                body: body ?? Data()
            )
        }
    }

    /// Internal helper: run a tool by name against its real endpoint and
    /// return the parsed JSON result (or a JSON-RPC error).
    @MainActor
    private func callToolByName(_ name: String,
                                arguments: [String: Any]) -> Result<Any, MCPAdapter.JSONRPCError> {
        guard let tool = ToolCatalog.find(name) else {
            return .failure(.methodNotFound)
        }

        // Build a synthetic HTTPRequest mirroring /tools/call dispatch.
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
            headers: [:],
            body: body
        )
        let innerResponse = dispatch(synthetic)
        guard innerResponse.status < 400 else {
            let msg = String(data: innerResponse.body, encoding: .utf8) ?? "error"
            return .failure(MCPAdapter.JSONRPCError(
                code: -32000,
                message: "Tool \(name) failed with status \(innerResponse.status)",
                data: msg
            ))
        }
        if let parsed = try? JSONSerialization.jsonObject(with: innerResponse.body) {
            return .success(parsed)
        }
        return .success(["ok": true])
    }

    @MainActor
    private func handlePing() -> HTTPResponse {
        HTTPResponse.json(["ok": true, "product": "FloatingMacro"])
    }

    @MainActor
    private func handleState() -> HTTPResponse {
        var body: [String: Any] = [
            "visible": panel?.isVisible ?? false,
            "activePreset": presetManager.currentPreset?.name as Any? ?? NSNull(),
            "displayName":  presetManager.currentPreset?.displayName as Any? ?? NSNull(),
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
        let list: [[String: Any]] = presetManager.listPresets().map { name in
            ["name": name, "active": name == active]
        }
        return HTTPResponse.json(["presets": list])
    }

    @MainActor
    private func handleAction(_ req: HTTPRequest) -> HTTPResponse {
        guard let action = req.jsonBody(as: Action.self) else {
            return HTTPResponse.badRequest("body must be a valid Action JSON")
        }
        // Fire the action asynchronously; respond immediately with 202.
        Task.detached {
            do {
                try await Self.runAction(action)
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

    // MARK: - Settings window

    @MainActor
    private func handleSettingsOpen() -> HTTPResponse {
        SettingsWindowController.shared.show(presetManager: presetManager)
        return HTTPResponse.json(["visible": true])
    }

    @MainActor
    private func handleSettingsClose() -> HTTPResponse {
        SettingsWindowController.shared.window?.orderOut(nil)
        return HTTPResponse.json(["visible": false])
    }

    /// Convenience for AI screenshot workflows: opens the settings window if
    /// it isn't already, then requests the SF Symbol picker sheet.
    @MainActor
    private func handleSettingsOpenSFPicker() -> HTTPResponse {
        SettingsWindowController.shared.show(presetManager: presetManager)
        // Give SwiftUI one tick to mount before we flip the nonce.
        DispatchQueue.main.async { [presetManager = self.presetManager] in
            presetManager.requestSFPicker()
        }
        return HTTPResponse.json(["opened": true])
    }

    // MARK: - Preset CRUD

    @MainActor
    private func handlePresetCurrent() -> HTTPResponse {
        guard let preset = presetManager.currentPreset else {
            return HTTPResponse.json(["preset": NSNull()])
        }
        if let data = try? JSONEncoder().encode(preset),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return HTTPResponse.json(["preset": obj])
        }
        return HTTPResponse.internalError("failed to encode preset")
    }

    @MainActor
    private func handlePresetCreate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must contain {name: String}")
        }
        let displayName = (dict["displayName"] as? String) ?? name
        let ok = presetManager.createPreset(name: name, displayName: displayName)
        return HTTPResponse.json(["ok": ok, "name": name])
    }

    @MainActor
    private func handlePresetRename(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String,
              let display = dict["displayName"] as? String else {
            return HTTPResponse.badRequest("body must contain {name, displayName}")
        }
        let ok = presetManager.renamePreset(name: name, displayName: display)
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    private func handlePresetDelete(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must contain {name: String}")
        }
        let ok = presetManager.deletePreset(name: name)
        return HTTPResponse.json(["ok": ok])
    }

    // MARK: - Group CRUD

    @MainActor
    private func handleGroupAdd(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String,
              let label = dict["label"] as? String else {
            return HTTPResponse.badRequest("body must contain {id, label}")
        }
        let collapsed = (dict["collapsed"] as? Bool) ?? false
        let group = ButtonGroup(id: id, label: label, collapsed: collapsed, buttons: [])
        let ok = presetManager.addGroup(group)
        return HTTPResponse.json(["ok": ok, "id": id])
    }

    @MainActor
    private func handleGroupUpdate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id: String}")
        }
        let label = dict["label"] as? String
        let collapsed = dict["collapsed"] as? Bool
        let ok = presetManager.updateGroup(id: id, label: label, collapsed: collapsed)
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    private func handleGroupDelete(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id: String}")
        }
        let ok = presetManager.deleteGroup(id: id)
        return HTTPResponse.json(["ok": ok])
    }

    // MARK: - Button CRUD

    @MainActor
    private func handleButtonAdd(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let groupId = dict["groupId"] as? String,
              let buttonDict = dict["button"] as? [String: Any] else {
            return HTTPResponse.badRequest("body must be {groupId, button: {...}}")
        }
        // Re-encode the button dict back through JSONDecoder to enforce schema.
        guard let data = try? JSONSerialization.data(withJSONObject: buttonDict),
              let button = try? JSONDecoder().decode(ButtonDefinition.self, from: data) else {
            return HTTPResponse.badRequest("button dict is not a valid ButtonDefinition")
        }
        let ok = presetManager.addButton(button, toGroupId: groupId)
        return HTTPResponse.json(["ok": ok, "id": button.id])
    }

    @MainActor
    private func handleButtonUpdate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id: String}")
        }
        // Each optional field uses Optional<Optional<T>> semantics via
        // PresetManager.updateButton: `nil` = do nothing, `.some(nil)` = clear.
        let label = dict["label"] as? String
        let icon: String??      = dict.keys.contains("icon") ? (dict["icon"] as? String) : nil
        let iconText: String??  = dict.keys.contains("iconText") ? (dict["iconText"] as? String) : nil
        let bg: String??        = dict.keys.contains("backgroundColor") ? (dict["backgroundColor"] as? String) : nil
        let width: Double??     = dict.keys.contains("width")  ? ((dict["width"]  as? NSNumber)?.doubleValue) : nil
        let height: Double??    = dict.keys.contains("height") ? ((dict["height"] as? NSNumber)?.doubleValue) : nil

        var action: Action?
        if let actionDict = dict["action"] as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: actionDict),
               let a = try? JSONDecoder().decode(Action.self, from: data) {
                action = a
            } else {
                return HTTPResponse.badRequest("action is not a valid Action")
            }
        }

        let ok = presetManager.updateButton(
            id: id, label: label,
            icon: icon, iconText: iconText, backgroundColor: bg,
            width: width, height: height, action: action
        )
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    private func handleButtonDelete(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id}")
        }
        let ok = presetManager.deleteButton(id: id)
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    private func handleButtonReorder(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let groupId = dict["groupId"] as? String,
              let ids = dict["ids"] as? [String] else {
            return HTTPResponse.badRequest("body must be {groupId, ids: [String]}")
        }
        let ok = presetManager.reorderButtons(ids: ids, inGroupId: groupId)
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    private func handleButtonMove(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String,
              let toGroupId = dict["toGroupId"] as? String else {
            return HTTPResponse.badRequest("body must contain {id, toGroupId}")
        }
        let position = (dict["position"] as? NSNumber)?.intValue
        let ok = presetManager.moveButton(id: id, toGroupId: toGroupId, at: position)
        return HTTPResponse.json(["ok": ok])
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

    nonisolated private static func runAction(_ action: Action) async throws {
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
