import Foundation
import AppKit
import FloatingMacroCore

// MARK: - Panel (Phase 3 multi-panel, Phase 3.5 edge dock, Phase 3.6 per-id)

extension ControlHandlers {

    // MARK: - Panel (Phase 3 multi-panel)

    /// Returns a list of all panels in JSON format. Each entry includes id, presetName, and other details.
    /// Display name / visible / window shape / docked edge included.
    @MainActor
    func handlePanelList() -> HTTPResponse {
        let panels = presetManager.appConfig?.panels ?? []
        let entries: [[String: Any]] = panels.map { p in
            let displayName = presetManager.preset(named: p.presetName)?.displayName ?? p.presetName
            let isVisible = panelManager?.panel(id: p.id)?.isVisible ?? p.visible
            var entry: [String: Any] = [
                "id": p.id,
                "presetName": p.presetName,
                "displayName": displayName,
                "visible": isVisible,
                "window": {
                    var w: [String: Any] = [
                        "x": p.window.x,
                        "y": p.window.y,
                        "width": p.window.width,
                        "height": p.window.height,
                        "opacity": p.window.opacity,
                    ]
                    if let bg = p.window.backgroundColor {
                        w["backgroundColor"] = bg
                    }
                    return w
                }() as [String: Any],
            ]
            if let edge = p.dockedEdge {
                entry["dockedEdge"] = edge.rawValue
            } else {
                entry["dockedEdge"] = NSNull()
            }
            return entry
        }
        return HTTPResponse.json(["panels": entries])
    }

    /// Create a new panel. presetName is required, x/y/width/height/opacity are optional.
    /// Returns the generated ID when omitted, placed adjacent to the primary one.
    @MainActor
    func handlePanelCreate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let presetName = dict["presetName"] as? String, !presetName.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"presetName\": String}")
        }
        // If the specified preset does not exist, it fails.
        guard presetManager.preset(named: presetName) != nil else {
            return HTTPResponse.badRequest("preset not found: \(presetName)")
        }
        // Resolution of start position and size: Specify → primary offset → default in order.
        let primary = presetManager.appConfig?.panels.first
        let baseX = primary?.window.x ?? 100
        let baseY = primary?.window.y ?? 100
        let baseW = primary?.window.width ?? 200
        let baseH = primary?.window.height ?? 300
        let offset: Double = 32
        let win = WindowConfig(
            x:               (dict["x"]      as? NSNumber)?.doubleValue ?? (baseX + offset),
            y:               (dict["y"]      as? NSNumber)?.doubleValue ?? (baseY - offset),
            width:           (dict["width"]  as? NSNumber)?.doubleValue ?? baseW,
            height:          (dict["height"] as? NSNumber)?.doubleValue ?? baseH,
            opacity:         (dict["opacity"] as? NSNumber)?.doubleValue ?? 1.0,
            backgroundColor: dict["backgroundColor"] as? String
        )
        guard let id = presetManager.addPanel(presetName: presetName, window: win),
              let newConfig = presetManager.appConfig?.panels.first(where: { $0.id == id })
        else {
            return HTTPResponse.internalError("failed to create panel")
        }
        // The creation of NSWindow is automatically performed by the AppDelegate's reconcile sink.
        return HTTPResponse.json([
            "id": id,
            "presetName": presetName,
            "window": [
                "x": newConfig.window.x,
                "y": newConfig.window.y,
                "width": newConfig.window.width,
                "height": newConfig.window.height,
                "opacity": newConfig.window.opacity,
            ] as [String: Any],
        ])
    }

    /// Remove the panel. The last one will be rejected by Core side.
    /// The destruction of NSWindow is automatically handled by the AppDelegate's reconcile sink.
    @MainActor
    func handlePanelClose(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        let removed = presetManager.removePanel(id: id)
        return HTTPResponse.json(["removed": removed, "id": id])
    }

    /// Display panel with specified ID (orderFront). If not found, return 404.
    @MainActor
    func handlePanelShow(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        guard let p = panelManager?.panel(id: id) else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        // If in the dock or mini-icon state, expand and then show the parent panel.
        panelManager?.expandFromDock(id: id)
        panelManager?.expandFromMini(id: id)
        presetManager.undockPanel(id: id)
        p.orderFront(nil)
        presetManager.setPanelVisible(id: id, visible: true)
        return HTTPResponse.json(["id": id, "visible": true])
    }

    /// Hide panel with specified ID (orderOut).
    @MainActor
    func handlePanelHide(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        guard let p = panelManager?.panel(id: id) else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        p.orderOut(nil)
        panelManager?.miniIcon(id: id)?.orderOut(nil)
        panelManager?.dockBar(id: id)?.orderOut(nil)
        presetManager.setPanelVisible(id: id, visible: false)
        return HTTPResponse.json(["id": id, "visible": false])
    }

    // MARK: - Panel (Phase 3.6 per-id move/resize/opacity/preset)

    /// Move the panel with the specified ID to absolute coordinates. Update both NSWindow and config.json.
    @MainActor
    func handlePanelMove(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty,
              let x = (dict["x"] as? NSNumber)?.doubleValue,
              let y = (dict["y"] as? NSNumber)?.doubleValue else {
            return HTTPResponse.badRequest("body must include {\"id\": String, \"x\": Double, \"y\": Double}")
        }
        guard let p = panelManager?.panel(id: id) else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        var frame = p.frame
        frame.origin.x = CGFloat(x)
        frame.origin.y = CGFloat(y)
        p.setFrame(frame, display: true, animate: false)
        presetManager.updatePanelFrame(
            id: id,
            x: Double(frame.origin.x), y: Double(frame.origin.y),
            width: Double(frame.size.width), height: Double(frame.size.height)
        )
        return HTTPResponse.json([
            "id": id,
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
        ])
    }

    /// Resize the panel with the specified ID. The Core side clamps it to a minimum of 120x80.
    @MainActor
    func handlePanelResize(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty,
              let w = (dict["width"]  as? NSNumber)?.doubleValue,
              let h = (dict["height"] as? NSNumber)?.doubleValue else {
            return HTTPResponse.badRequest("body must include {\"id\": String, \"width\": Double, \"height\": Double}")
        }
        guard let p = panelManager?.panel(id: id) else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        // Apply the same clamping to updatingPanelFrame as in NSWindow.
        let clampedW = max(120, CGFloat(w))
        let clampedH = max(80, CGFloat(h))
        var frame = p.frame
        frame.size.width = clampedW
        frame.size.height = clampedH
        p.setFrame(frame, display: true, animate: false)
        presetManager.updatePanelFrame(
            id: id,
            x: Double(frame.origin.x), y: Double(frame.origin.y),
            width: Double(frame.size.width), height: Double(frame.size.height)
        )
        return HTTPResponse.json([
            "id": id,
            "width":  Double(frame.size.width),
            "height": Double(frame.size.height),
        ])
    }

    /// Update the transparency of a panel with a specified ID. Core side clamps to [0.25, 1.0].
    @MainActor
    func handlePanelOpacity(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty,
              let value = (dict["opacity"] as? NSNumber)?.doubleValue else {
            return HTTPResponse.badRequest("body must include {\"id\": String, \"opacity\": Double}")
        }
        guard panelManager?.panel(id: id) != nil else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        presetManager.updatePanelOpacity(id: id, opacity: value)
        let clamped = presetManager.appConfig?.panels.first(where: { $0.id == id })?.window.opacity ?? value
        panelManager?.setOpacity(id: id, opacity: clamped)
        return HTTPResponse.json(["id": id, "opacity": clamped])
    }

    /// Update the background color of the panel with the specified ID. Use `#RRGGBB` hex string or null to reset.
    @MainActor
    func handlePanelBackgroundColor(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        guard panelManager?.panel(id: id) != nil else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        let hex = dict["color"] as? String
        presetManager.updatePanelBackgroundColor(id: id, hex: hex)
        panelManager?.setBackgroundColor(id: id, hex: hex)
        return HTTPResponse.json(["id": id, "backgroundColor": hex as Any])
    }

    /// Switch to a preset that the panel with the specified ID displays.
    /// `presetName` is the internal ID (file name) that can be obtained from `preset_list`.
    @MainActor
    func handlePanelSetPreset(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty,
              let presetName = dict["presetName"] as? String, !presetName.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String, \"presetName\": String}")
        }
        guard panelManager?.panel(id: id) != nil else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        guard presetManager.preset(named: presetName) != nil else {
            return HTTPResponse.badRequest("preset not found: \(presetName)")
        }
        presetManager.switchPanelPreset(panelID: id, to: presetName)
        return HTTPResponse.json([
            "id": id,
            "presetName": presetName,
        ])
    }

    // MARK: - Phase 3.5: edge dock

    @MainActor
    func handlePanelDock(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        guard let p = panelManager?.panel(id: id) else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        let edge: DockEdge
        if let edgeStr = dict["edge"] as? String {
            guard let e = DockEdge(rawValue: edgeStr) else {
                return HTTPResponse.badRequest("invalid edge: \(edgeStr). Must be left/right/top/bottom.")
            }
            edge = e
        } else if let screen = NSScreen.main?.visibleFrame {
            let center = CGPoint(x: p.frame.midX, y: p.frame.midY)
            edge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        } else {
            edge = .right
        }

        let presetName = presetManager.appConfig?.panels.first(where: { $0.id == id })?.presetName ?? "default"
        let displayName = presetManager.preset(named: presetName)?.displayName ?? presetName
        let iconName = presetManager.preset(named: presetName)?.groups.first?.buttons.first?.icon

        let f = p.frame
        presetManager.updatePanelFrame(
            id: id,
            x: Double(f.origin.x),
            y: Double(f.origin.y),
            width: Double(f.size.width),
            height: Double(f.size.height)
        )
        panelManager?.collapseToDock(id: id, edge: edge, label: displayName, iconName: iconName)
        presetManager.dockPanel(id: id, edge: edge)
        return HTTPResponse.json(["id": id, "dockedEdge": edge.rawValue])
    }

    @MainActor
    func handlePanelUndock(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        guard panelManager?.panel(id: id) != nil else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        panelManager?.expandFromDock(id: id)
        presetManager.undockPanel(id: id)
        return HTTPResponse.json(["id": id, "dockedEdge": NSNull()])
    }

    func handlePanelResetDockPosition(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        guard panelManager?.panel(id: id) != nil else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        panelManager?.resetDockBarPosition(id: id)
        presetManager.clearDockBarPosition(id: id)
        return HTTPResponse.json(["id": id, "dockBarPosition": NSNull()])
    }

    func handlePanelGatherDockBars() -> HTTPResponse {
        panelManager?.resetAllDockBarPositions()
        presetManager.clearAllDockBarPositions()
        return HTTPResponse.json(["gathered": true])
    }

    // MARK: - Snapshot

    /// Return the current display content of the panel as a PNG image.
    /// Screen Recording permission not required - self-process cache display with NSView
    /// Directly bitmapize window content.
    @MainActor
    func handlePanelSnapshot(_ req: HTTPRequest) -> HTTPResponse {
        let id: String
        if let qid = req.query["id"], !qid.isEmpty {
            id = qid
        } else {
            id = presetManager.appConfig?.panels.first?.id ?? ""
        }
        guard !id.isEmpty else {
            return HTTPResponse.badRequest("no panel id (pass ?id=... or have at least one panel)")
        }
        guard let panel = panelManager?.panel(id: id) else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        guard let view = panel.contentView else {
            return HTTPResponse.json(["error": "panel has no contentView"], status: 500)
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
            headers: [
                ("Content-Type", "image/png"),
                ("Content-Length", "\(pngData.count)"),
            ],
            body: pngData
        )
    }

}
