import Foundation
import FloatingMacroCore

// MARK: - Web Panel (non-main fast path)

extension ControlHandlers {

    nonisolated func handleWebPanelHTML_nonMain(_ req: HTTPRequest) -> HTTPResponse {
        let ua = req.header("User-Agent") ?? "(no UA)"
        guard lanExposureEnabledSnapshot else {
            LoggerContext.shared.warn("WebPanel", "HTML blocked: LAN off (fast)", ["ua": ua])
            return HTTPResponse.json(["error": "LAN off"], status: 403)
        }
        guard let token = req.query["token"] else {
            return HTTPResponse.json(["error": "missing token"], status: 401)
        }
        guard EphemeralLANTokenStore.shared.matches(token) else {
            return HTTPResponse.json(["error": "invalid token"], status: 401)
        }

        let presetName = req.query["preset"]
        let preset = resolvePresetForSSR(name: presetName)
        let presetJSON = encodePresetJSONString(preset) ?? "null"
        let presetDisplay = preset?.displayName ?? presetName ?? L("現在のプリセット_95367b")
        let ssrHTML = WebPanelSSR.renderInnerHTML(preset: preset)

        if let preset = preset {
            WebPanelIconRenderer.shared.prewarm(preset: preset)
        }

        guard let body = WebPanelAssets.renderHTML(token: token,
                                                   presetJSON: presetJSON,
                                                   presetDisplay: presetDisplay,
                                                   ssrHTML: ssrHTML) else {
            return HTTPResponse.internalError("asset missing")
        }
        return HTTPResponse(
            status: 200, reason: "OK",
            headers: [
                ("Content-Type",   WebPanelAssets.AssetKind.html.contentType),
                ("Cache-Control",  "no-store, no-cache, must-revalidate, max-age=0"),
                ("Pragma",         "no-cache"),
            ],
            body: body
        )
    }

    nonisolated func resolvePresetForSSR(name: String?) -> Preset? {
        if let name = name, !name.isEmpty {
            return presetManager.preset(named: name)
        }
        if let active = presetManager.appConfig?.activePreset {
            return presetManager.preset(named: active)
        }
        return nil
    }

    nonisolated func encodePresetJSONString(_ preset: Preset?) -> String? {
        guard let preset = preset else { return nil }
        guard let data = try? JSONEncoder().encode(preset),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
            .replacingOccurrences(of: "</", with: "\\u003c/")
            .replacingOccurrences(of: "<!--", with: "\\u003c!--")
    }

    nonisolated func handleWebPanelAsset_nonMain(_ kind: WebPanelAssets.AssetKind) -> HTTPResponse {
        guard lanExposureEnabledSnapshot else {
            return HTTPResponse.json(["error": "LAN off"], status: 403)
        }
        guard let body = WebPanelAssets.data(kind) else {
            return HTTPResponse.notFound("/webpanel/\(kind.fileName)")
        }
        return HTTPResponse(
            status: 200, reason: "OK",
            headers: [
                ("Content-Type",  kind.contentType),
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("Pragma",        "no-cache"),
            ],
            body: body
        )
    }

    nonisolated func handleWebPanelIcon_nonMain(_ req: HTTPRequest) -> HTTPResponse {
        guard lanExposureEnabledSnapshot else {
            return HTTPResponse.json(["error": "LAN off"], status: 403)
        }
        guard let token = req.query["token"],
              EphemeralLANTokenStore.shared.matches(token) else {
            return HTTPResponse.json(["error": "invalid token"], status: 401)
        }
        guard let ref = req.query["ref"], !ref.isEmpty else {
            return HTTPResponse.badRequest("missing 'ref'")
        }
        let requestedSize = Int(req.query["size"] ?? "") ?? 128
        let size = max(32, min(2048, requestedSize))
        let format: WebPanelIconRenderer.Format = {
            switch req.query["format"]?.lowercased() {
            case "jpeg": return .jpeg
            case "webp": return .webp
            default:     return .png
            }
        }()

        guard let entry = WebPanelIconRenderer.shared.render(ref: ref,
                                                             maxSize: size,
                                                             format: format) else {
            return HTTPResponse.notFound("/webpanel/icon")
        }
        if let inm = req.header("If-None-Match"), inm == entry.etag {
            return HTTPResponse(
                status: 304, reason: "Not Modified",
                headers: [
                    ("ETag",          entry.etag),
                    ("Cache-Control", "public, max-age=86400, immutable"),
                ]
            )
        }
        return HTTPResponse(
            status: 200, reason: "OK",
            headers: [
                ("Content-Type",  entry.contentType),
                ("ETag",          entry.etag),
                ("Cache-Control", "public, max-age=86400, immutable"),
            ],
            body: entry.data
        )
    }
}

// MARK: - Web Panel (main-actor routes)

extension ControlHandlers {

    @MainActor
    func handleWebPanelHTML(_ req: HTTPRequest) -> HTTPResponse {
        return handleWebPanelHTML_nonMain(req)
    }

    @MainActor
    func handleWebPanelAsset(_ kind: WebPanelAssets.AssetKind) -> HTTPResponse {
        guard presetManager.appConfig?.controlAPI.lanExposureEnabled == true else {
            LoggerContext.shared.warn("WebPanel", "asset blocked: LAN off", ["kind": kind.fileName])
            return HTTPResponse.json(
                ["error": "web panel is only available in LAN exposure mode"],
                status: 403
            )
        }
        guard let body = WebPanelAssets.data(kind) else {
            LoggerContext.shared.error("WebPanel", "asset 404", ["kind": kind.fileName])
            return HTTPResponse.notFound("/webpanel/\(kind.fileName)")
        }
        LoggerContext.shared.info("WebPanel", "asset 200", [
            "kind":  kind.fileName,
            "bytes": String(body.count),
        ])
        return HTTPResponse(
            status: 200, reason: "OK",
            headers: [
                ("Content-Type",  kind.contentType),
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("Pragma",        "no-cache"),
            ],
            body: body
        )
    }

    @MainActor
    func handleWebPanelToolsCall(_ req: HTTPRequest) -> HTTPResponse {
        let ua = req.header("User-Agent") ?? "(no UA)"
        guard presetManager.appConfig?.controlAPI.lanExposureEnabled == true else {
            LoggerContext.shared.warn("WebPanel", "tools/call 403: LAN off", ["ua": ua])
            return HTTPResponse.json(
                ["error": "web panel is only available in LAN exposure mode"],
                status: 403
            )
        }
        guard let auth = req.header("Authorization"),
              auth.hasPrefix("Bearer ") else {
            LoggerContext.shared.warn("WebPanel", "tools/call 401: missing Authorization", ["ua": ua])
            return HTTPResponse.json(
                ["error": "Authorization: Bearer <token> required"],
                status: 401
            )
        }
        let candidate = String(auth.dropFirst("Bearer ".count))
        guard EphemeralLANTokenStore.shared.matches(candidate) else {
            LoggerContext.shared.warn("WebPanel", "tools/call 401: token mismatch", [
                "ua": ua,
                "tokenPrefix": String(candidate.prefix(8)),
            ])
            return HTTPResponse.json(
                ["error": "invalid ephemeral token"],
                status: 401
            )
        }
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            LoggerContext.shared.warn("WebPanel", "tools/call 400: bad body", ["ua": ua])
            return HTTPResponse.badRequest("body must be {name: String, arguments?: object}")
        }
        guard WebPanelToolWhitelist.isAllowed(name) else {
            LoggerContext.shared.warn("WebPanel", "tools/call 403: not whitelisted", [
                "ua":   ua,
                "name": name,
            ])
            return HTTPResponse.json(
                ["error": "tool not allowed from web panel",
                 "name": name],
                status: 403
            )
        }
        guard let tool = ToolCatalog.find(name) else {
            LoggerContext.shared.warn("WebPanel", "tools/call 404: unknown tool", ["name": name])
            return HTTPResponse.json(
                ["error": "unknown tool", "name": name],
                status: 404
            )
        }
        let args = (dict["arguments"] as? [String: Any]) ?? [:]
        let inner = invokeToolByDispatch(tool: tool, arguments: args, headers: req.headers)
        LoggerContext.shared.info("WebPanel", "tools/call \(inner.status)", [
            "ua":    ua,
            "name":  name,
            "args":  String(describing: args.keys.sorted()),
        ])
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

    @MainActor
    func handleWebPanelIcon(_ req: HTTPRequest) -> HTTPResponse {
        guard presetManager.appConfig?.controlAPI.lanExposureEnabled == true else {
            LoggerContext.shared.warn("WebPanel", "icon 403: LAN off")
            return HTTPResponse.json(
                ["error": "web panel is only available in LAN exposure mode"],
                status: 403
            )
        }
        guard let token = req.query["token"],
              EphemeralLANTokenStore.shared.matches(token) else {
            LoggerContext.shared.warn("WebPanel", "icon 401: token mismatch")
            return HTTPResponse.json(
                ["error": "missing or invalid token"], status: 401
            )
        }
        guard let ref = req.query["ref"], !ref.isEmpty else {
            return HTTPResponse.badRequest("missing 'ref' query parameter")
        }
        let requestedSize = Int(req.query["size"] ?? "") ?? 128
        let size = max(32, min(2048, requestedSize))
        let format: WebPanelIconRenderer.Format = {
            switch req.query["format"]?.lowercased() {
            case "jpeg": return .jpeg
            case "webp": return .webp
            default:     return .png
            }
        }()

        guard let entry = WebPanelIconRenderer.shared.render(ref: ref,
                                                             maxSize: size,
                                                             format: format) else {
            LoggerContext.shared.warn("WebPanel", "icon 404", [
                "ref": ref, "size": String(size), "fmt": format.rawValue,
            ])
            return HTTPResponse.notFound("/webpanel/icon")
        }

        if let inm = req.header("If-None-Match"), inm == entry.etag {
            LoggerContext.shared.info("WebPanel", "icon 304", [
                "ref":  ref,
                "size": String(size),
            ])
            return HTTPResponse(
                status: 304, reason: "Not Modified",
                headers: [
                    ("ETag",          entry.etag),
                    ("Cache-Control", "public, max-age=86400, immutable"),
                ]
            )
        }

        LoggerContext.shared.info("WebPanel", "icon 200", [
            "ref":   ref,
            "size":  String(size),
            "fmt":   format.rawValue,
            "bytes": String(entry.data.count),
        ])
        return HTTPResponse(
            status: 200, reason: "OK",
            headers: [
                ("Content-Type",   entry.contentType),
                ("ETag",           entry.etag),
                ("Cache-Control",  "public, max-age=86400, immutable"),
            ],
            body: entry.data
        )
    }

    // MARK: - LAN token info (Bearer auth)

    @MainActor
    func handleLANTokenInfo() -> HTTPResponse {
        let lanEnabled = presetManager.appConfig?.controlAPI.lanExposureEnabled ?? false
        let token = EphemeralLANTokenStore.shared.current
        let issuedAt = EphemeralLANTokenStore.shared.lastRotatedAt
        var body: [String: Any] = [
            "lanExposureEnabled": lanEnabled,
            "token": token as Any,
        ]
        if let issuedAt = issuedAt {
            body["issuedAt"] = ISO8601DateFormatter().string(from: issuedAt)
        }
        return HTTPResponse.json(body)
    }

    @MainActor
    func handleLANTokenRotate() -> HTTPResponse {
        let lanEnabled = presetManager.appConfig?.controlAPI.lanExposureEnabled ?? false
        guard lanEnabled else {
            return HTTPResponse.json(
                ["error": "LAN exposure is disabled; enable it before rotating"],
                status: 409
            )
        }
        let token = EphemeralLANTokenStore.shared.rotate()
        return HTTPResponse.json([
            "token": token,
            "issuedAt": ISO8601DateFormatter().string(from: Date()),
        ])
    }
}
