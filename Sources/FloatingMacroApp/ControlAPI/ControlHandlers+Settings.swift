import Foundation
import AppKit
import FloatingMacroCore

// MARK: - Settings window, AI Integration window

extension ControlHandlers {

    // MARK: - Settings window

    @MainActor
    func handleSettingsOpen() -> HTTPResponse {
        SettingsWindowController.shared.show(presetManager: presetManager)
        return HTTPResponse.json(["visible": true])
    }

    @MainActor
    func handleSettingsClose() -> HTTPResponse {
        SettingsWindowController.shared.window?.orderOut(nil)
        return HTTPResponse.json(["visible": false])
    }

    // MARK: - AI Integration window

    @MainActor
    func handleAIIntegrationOpen() -> HTTPResponse {
        AIIntegrationWindowController.shared.show(presetManager: presetManager)
        return HTTPResponse.json(["visible": true])
    }

    @MainActor
    func handleAIIntegrationClose() -> HTTPResponse {
        AIIntegrationWindowController.shared.window?.orderOut(nil)
        return HTTPResponse.json(["visible": false])
    }

    /// Convenience for AI screenshot workflows: opens the settings window if
    /// it isn't already, then requests the SF Symbol picker sheet.
    @MainActor
    func handleSettingsOpenSFPicker() -> HTTPResponse {
        SettingsWindowController.shared.show(presetManager: presetManager)
        // Give SwiftUI one tick to mount before we flip the nonce.
        DispatchQueue.main.async { [presetManager = self.presetManager] in
            presetManager.requestSFPicker()
        }
        return HTTPResponse.json(["opened": true])
    }

    @MainActor
    func handleSettingsSelectButton(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must be {\"id\": String}")
        }
        SettingsWindowController.shared.show(presetManager: presetManager)
        presetManager.externalSelectButtonRequest = id
        return HTTPResponse.json(["id": id])
    }

    @MainActor
    func handleSettingsSelectGroup(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must be {\"id\": String}")
        }
        SettingsWindowController.shared.show(presetManager: presetManager)
        presetManager.externalSelectGroupRequest = id
        return HTTPResponse.json(["id": id])
    }

    @MainActor
    func handleSettingsOpenAppIconPicker() -> HTTPResponse {
        SettingsWindowController.shared.show(presetManager: presetManager)
        // Give SwiftUI one tick to mount before we flip the nonce.
        DispatchQueue.main.async { [presetManager = self.presetManager] in
            presetManager.requestAppIconPicker()
        }
        return HTTPResponse.json(["opened": true])
    }

    @MainActor
    func handleSettingsDismissPicker() -> HTTPResponse {
        presetManager.requestDismissPicker()
        return HTTPResponse.json(["dismissed": true])
    }

    @MainActor
    func handleSettingsClearSelection() -> HTTPResponse {
        presetManager.requestClearSelection()
        return HTTPResponse.json(["cleared": true])
    }

    @MainActor
    func handleSettingsCommit() -> HTTPResponse {
        presetManager.requestCommit()
        return HTTPResponse.json(["committed": true])
    }

    @MainActor
    func handleSettingsSetBackgroundColor(_ req: HTTPRequest) -> HTTPResponse {
        let dict = req.jsonDictionary() ?? [:]
        // enabled:false → disable. color:"#RRGGBB" → enable with that color.
        if let enabled = dict["enabled"] as? Bool, !enabled {
            presetManager.requestSetBackgroundColor(hex: nil)
            return HTTPResponse.json(["enabled": false])
        }
        guard let hex = dict["color"] as? String else {
            return HTTPResponse.badRequest("body must be {\"color\": \"#RRGGBB\"} or {\"enabled\": false}")
        }
        presetManager.requestSetBackgroundColor(hex: hex)
        return HTTPResponse.json(["color": hex])
    }

    @MainActor
    func handleSettingsSetTextColor(_ req: HTTPRequest) -> HTTPResponse {
        let dict = req.jsonDictionary() ?? [:]
        if let enabled = dict["enabled"] as? Bool, !enabled {
            presetManager.requestSetTextColor(hex: nil)
            return HTTPResponse.json(["enabled": false])
        }
        guard let hex = dict["color"] as? String else {
            return HTTPResponse.badRequest("body must be {\"color\": \"#RRGGBB\"} or {\"enabled\": false}")
        }
        presetManager.requestSetTextColor(hex: hex)
        return HTTPResponse.json(["color": hex])
    }

    @MainActor
    func handleSettingsMove(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let x = (dict["x"] as? NSNumber)?.doubleValue,
              let y = (dict["y"] as? NSNumber)?.doubleValue else {
            return HTTPResponse.badRequest("body must be {\"x\": Double, \"y\": Double}")
        }
        guard let w = SettingsWindowController.shared.window else {
            return HTTPResponse.internalError("Settings window not open")
        }
        var frame = w.frame
        frame.origin.x = CGFloat(x)
        frame.origin.y = CGFloat(y)
        w.setFrame(frame, display: true, animate: false)
        return HTTPResponse.json([
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
        ])
    }

    /// Arrange the floating panel and Settings window so they don't overlap.
    ///
    /// Layout (macOS screen coordinates, origin = bottom-left):
    ///   - If the screen is wide enough (≥ 1440 px), the Settings window goes
    ///     on the right half and the panel is placed in the upper-left corner.
    ///   - On narrower screens the Settings window is placed at the bottom and
    ///     the panel at the top-left.
    ///
    /// Body (all fields optional):
    ///   { "open_settings": true }   — also open the Settings window if not visible
    @MainActor
    func handleArrange(_ req: HTTPRequest) -> HTTPResponse {
        let dict = req.jsonDictionary() ?? [:]
        let openSettings = (dict["open_settings"] as? Bool) ?? false

        guard let screen = NSScreen.main else {
            return HTTPResponse.internalError("no main screen")
        }

        let visible = screen.visibleFrame   // excludes menu bar + Dock
        let margin: CGFloat = 12

        // Settings window size (keep current size if already open)
        let settingsW: CGFloat
        let settingsH: CGFloat
        if let sw = SettingsWindowController.shared.window {
            settingsW = sw.frame.width
            settingsH = sw.frame.height
        } else {
            settingsW = 820
            settingsH = 680
        }

        let panelFrame: NSRect
        let settingsOrigin: NSPoint

        let panelSize = panel?.frame.size ?? NSSize(width: 200, height: 120)

        if visible.width >= settingsW + panelSize.width + margin * 3 {
            // Wide enough: settings on left, panel top-right (no overlap)
            let settingsX = visible.minX + margin
            let settingsY = visible.minY + margin
            settingsOrigin = NSPoint(x: settingsX, y: settingsY)

            let panelX = settingsX + settingsW + margin
            let panelY = visible.maxY - panelSize.height - margin
            panelFrame = NSRect(origin: NSPoint(x: panelX, y: panelY), size: panelSize)
        } else {
            // Narrow screen: settings bottom-left, panel top-right.
            // Ensure the panel clears the top of the settings window vertically
            // so both remain fully visible without user intervention.
            let settingsX = visible.minX + margin
            let settingsY = visible.minY + margin
            settingsOrigin = NSPoint(x: settingsX, y: settingsY)

            let panelX = visible.maxX - panelSize.width - margin
            let settingsTop = settingsY + settingsH
            // Prefer the top-right corner; if that would overlap the settings
            // window vertically, push the panel above the settings top edge.
            let panelY = max(visible.maxY - panelSize.height - margin,
                             settingsTop + margin)
            panelFrame = NSRect(origin: NSPoint(x: panelX, y: panelY), size: panelSize)
        }

        // Move floating panel
        if let p = panel {
            var f = p.frame
            f.origin = panelFrame.origin
            p.setFrame(f, display: true, animate: false)
            presetManager.setPanelFrame(
                x: Double(f.origin.x), y: Double(f.origin.y),
                width: Double(f.size.width), height: Double(f.size.height)
            )
        }

        // Open Settings if requested, then move it
        if openSettings {
            SettingsWindowController.shared.show(presetManager: presetManager)
        }
        if let sw = SettingsWindowController.shared.window {
            var sf = sw.frame
            sf.origin = settingsOrigin
            sw.setFrame(sf, display: true, animate: false)
        }

        var result: [String: Any] = [
            "screen": ["width": Double(visible.width), "height": Double(visible.height)],
            "settings": ["x": Double(settingsOrigin.x), "y": Double(settingsOrigin.y)],
        ]
        if let p = panel {
            result["panel"] = ["x": Double(p.frame.origin.x), "y": Double(p.frame.origin.y)]
        }
        return HTTPResponse.json(result)
    }

    @MainActor
    func handleSettingsSetActionType(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let type = dict["type"] as? String else {
            return HTTPResponse.badRequest("body must be {\"type\": String}")
        }
        guard ["text", "key", "launch", "terminal"].contains(type) else {
            return HTTPResponse.badRequest("type must be one of: text, key, launch, terminal")
        }
        presetManager.externalActionTypeRequest = type
        return HTTPResponse.json(["type": type])
    }

    /// Set the key combo in the ButtonEditor key-action fields.
    /// Accepts either `{"combo": "cmd+shift+v"}` or individual modifier flags
    /// `{"cmd": true, "shift": false, "option": false, "ctrl": false, "key": "v"}`.
    @MainActor
    func handleSettingsSetKeyCombo(_ req: HTTPRequest) -> HTTPResponse {
        let dict = req.jsonDictionary() ?? [:]
        let combo: String
        if let c = dict["combo"] as? String {
            combo = c
        } else {
            var parts: [String] = []
            if (dict["cmd"]    as? Bool) == true { parts.append("cmd") }
            if (dict["shift"]  as? Bool) == true { parts.append("shift") }
            if (dict["option"] as? Bool) == true { parts.append("option") }
            if (dict["ctrl"]   as? Bool) == true { parts.append("ctrl") }
            if let key = dict["key"] as? String, !key.isEmpty {
                parts.append(key.lowercased())
            }
            combo = parts.joined(separator: "+")
        }
        guard !combo.isEmpty else {
            return HTTPResponse.badRequest(
                "body must be {\"combo\": String} or modifier booleans + {\"key\": String}"
            )
        }
        presetManager.requestSetKeyCombo(combo: combo)
        return HTTPResponse.json(["combo": combo])
    }

    /// Set the value field for the currently active action type in ButtonEditor.
    /// `type` must be "text", "launch", or "terminal". Also switches the
    /// action type tab to match.
    @MainActor
    func handleSettingsSetActionValue(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let type  = dict["type"]  as? String,
              let value = dict["value"] as? String else {
            return HTTPResponse.badRequest(
                "body must be {\"type\": \"text\"|\"launch\"|\"terminal\", \"value\": String}"
            )
        }
        guard ["text", "launch", "terminal"].contains(type) else {
            return HTTPResponse.badRequest("type must be one of: text, launch, terminal")
        }
        presetManager.requestSetActionValue(type: type, value: value)
        return HTTPResponse.json(["type": type, "value": value])
    }

    // MARK: - Snapshot

    @MainActor
    func handleSettingsSnapshot() -> HTTPResponse {
        guard let window = SettingsWindowController.shared.window,
              window.isVisible,
              let view = window.contentView else {
            return HTTPResponse.badRequest("settings window is not open")
        }
        let bounds = view.bounds
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return HTTPResponse.json(["error": "failed to create bitmap rep"], status: 500)
        }
        view.cacheDisplay(in: bounds, to: bitmapRep)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return HTTPResponse.json(["error": "PNG encoding failed"], status: 500)
        }
        return HTTPResponse(
            status: 200, reason: "OK",
            headers: [("Content-Type", "image/png"), ("Content-Length", "\(pngData.count)")],
            body: pngData
        )
    }

}
