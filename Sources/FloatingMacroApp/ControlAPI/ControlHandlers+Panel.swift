import Foundation
import AppKit
import FloatingMacroCore

// MARK: - Panel (Phase 3 multi-panel, Phase 3.5 edge dock, Phase 3.6 per-id)

extension ControlHandlers {

    // MARK: - Panel (Phase 3 multi-panel)

    /// 全パネルの一覧を JSON で返す。各エントリには id / presetName /
    /// displayName / visible / window 形状 / dockedEdge を含む。
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

    /// 新規パネルを生成。presetName 必須、x/y/width/height/opacity はオプション
    /// (省略時はプライマリの隣にオフセット配置)。生成された id を返す。
    @MainActor
    func handlePanelCreate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let presetName = dict["presetName"] as? String, !presetName.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"presetName\": String}")
        }
        // 指定された preset が存在しない場合は失敗。
        guard presetManager.preset(named: presetName) != nil else {
            return HTTPResponse.badRequest("preset not found: \(presetName)")
        }
        // 開始位置・サイズの解決: 指定 → primary オフセット → デフォルト の順。
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
        // NSWindow の生成は AppDelegate の reconcile sink が自動で行う。
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

    /// パネルを削除。Core 側で最後の 1 件は削除拒否される。
    /// NSWindow の破棄は AppDelegate の reconcile sink が自動で行う。
    @MainActor
    func handlePanelClose(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        let removed = presetManager.removePanel(id: id)
        return HTTPResponse.json(["removed": removed, "id": id])
    }

    /// 指定 id のパネルを表示 (orderFront)。存在しない場合は 404。
    @MainActor
    func handlePanelShow(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String, !id.isEmpty else {
            return HTTPResponse.badRequest("body must include {\"id\": String}")
        }
        guard let p = panelManager?.panel(id: id) else {
            return HTTPResponse.notFound("panel id: \(id)")
        }
        // ドック中 or ミニアイコン中なら展開してから親パネルを出す。
        panelManager?.expandFromDock(id: id)
        panelManager?.expandFromMini(id: id)
        presetManager.undockPanel(id: id)
        p.orderFront(nil)
        presetManager.setPanelVisible(id: id, visible: true)
        return HTTPResponse.json(["id": id, "visible": true])
    }

    /// 指定 id のパネルを非表示 (orderOut)。
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

    /// 指定 id のパネルを絶対座標に移動。NSWindow と config.json の両方を更新。
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

    /// 指定 id のパネルをリサイズ。Core 側で min 120×80 にクランプされる。
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
        // Core の updatingPanelFrame と同じクランプを NSWindow にも適用。
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

    /// 指定 id のパネルの透明度を更新。Core 側で [0.25, 1.0] にクランプ。
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

    /// 指定 id のパネルの背景色を更新。`#RRGGBB` hex 文字列、または null でリセット。
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

    /// 指定 id のパネルが表示するプリセットを切り替え。
    /// `presetName` は preset_list で取得できる内部 id (ファイル名)。
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

    /// パネルの現在の表示内容を PNG 画像として返す。
    /// Screen Recording 権限不要 — NSView.cacheDisplay で自プロセスの
    /// ウィンドウ内容を直接ビットマップ化する。
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
