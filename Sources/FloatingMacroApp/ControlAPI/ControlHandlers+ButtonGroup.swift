import Foundation
import AppKit
import FloatingMacroCore

// MARK: - Group CRUD, Button CRUD

extension ControlHandlers {

    // MARK: - Group CRUD

    @MainActor
    func handleGroupAdd(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String,
              let label = dict["label"] as? String else {
            return HTTPResponse.badRequest("body must contain {id, label}")
        }
        let collapsed = (dict["collapsed"] as? Bool) ?? false
        let displayType: GroupDisplayType = {
            guard let raw = dict["displayType"] as? String,
                  let value = GroupDisplayType(rawValue: raw) else { return .icon }
            return value
        }()
        let columns: GroupColumns = Self.parseColumns(dict["columns"])
        let iconSize: IconSize = {
            guard let raw = dict["iconSize"] as? String,
                  let value = IconSize(rawValue: raw) else { return .medium }
            return value
        }()
        let showLabels = (dict["showLabels"] as? Bool) ?? true
        let group = ButtonGroup(id: id, label: label, collapsed: collapsed,
                                displayType: displayType, columns: columns,
                                iconSize: iconSize, showLabels: showLabels, buttons: [])
        let ok = presetManager.addGroup(group)
        return HTTPResponse.json(["ok": ok, "id": id])
    }

    @MainActor
    func handleGroupUpdate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id: String}")
        }
        let label = dict["label"] as? String
        let icon: String?? = dict.keys.contains("icon")
            ? .some(dict["icon"] as? String) : nil
        let iconText: String?? = dict.keys.contains("iconText")
            ? .some(dict["iconText"] as? String) : nil
        let bgColor: String?? = dict.keys.contains("backgroundColor")
            ? .some(dict["backgroundColor"] as? String) : nil
        let txtColor: String?? = dict.keys.contains("textColor")
            ? .some(dict["textColor"] as? String) : nil
        let tip: String?? = dict.keys.contains("tooltip")
            ? .some(dict["tooltip"] as? String) : nil
        let collapsed = dict["collapsed"] as? Bool
        // Resolve displayType: string ("icon" | "wide" | "card") to enum.
        // Ignore invalid values, ignoring nil as no change, preserving existing behavior.
        let displayType: GroupDisplayType? = {
            guard let raw = dict["displayType"] as? String else { return nil }
            return GroupDisplayType(rawValue: raw)
        }()
        let columns: GroupColumns? = dict.keys.contains("columns")
            ? Self.parseColumns(dict["columns"]) : nil
        let iconSize: IconSize? = {
            guard let raw = dict["iconSize"] as? String else { return nil }
            return IconSize(rawValue: raw)
        }()
        let showLabels = dict["showLabels"] as? Bool
        let ok = presetManager.updateGroup(
            id: id, label: label, icon: icon, iconText: iconText,
            backgroundColor: bgColor, textColor: txtColor,
            tooltip: tip, collapsed: collapsed,
            displayType: displayType, columns: columns,
            iconSize: iconSize, showLabels: showLabels
        )
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    func handleGroupDelete(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id: String}")
        }
        let ok = presetManager.deleteGroup(id: id)
        return HTTPResponse.json(["ok": ok])
    }

    static func parseColumns(_ value: Any?) -> GroupColumns {
        if let n = value as? Int, (1...3).contains(n) { return .fixed(n) }
        if let s = value as? String {
            if s == "auto" { return .auto }
            if let n = Int(s), (1...3).contains(n) { return .fixed(n) }
        }
        return .auto
    }

    // MARK: - Button CRUD

    @MainActor
    func handleButtonAdd(_ req: HTTPRequest) -> HTTPResponse {
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
    func handleButtonUpdate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id: String}")
        }
        let label = dict["label"] as? String
        let icon: String??      = dict.keys.contains("icon") ? .some(dict["icon"] as? String) : nil
        let iconText: String??  = dict.keys.contains("iconText") ? .some(dict["iconText"] as? String) : nil
        let bg: String??        = dict.keys.contains("backgroundColor") ? .some(dict["backgroundColor"] as? String) : nil
        let tc: String??        = dict.keys.contains("textColor") ? .some(dict["textColor"] as? String) : nil
        let width: Double??     = dict.keys.contains("width")  ? .some((dict["width"]  as? NSNumber)?.doubleValue) : nil
        let height: Double??    = dict.keys.contains("height") ? .some((dict["height"] as? NSNumber)?.doubleValue) : nil
        let tooltip: String??   = dict.keys.contains("tooltip") ? .some(dict["tooltip"] as? String) : nil
        let confirm: Bool?            = dict["confirm"] as? Bool
        let confirmDestructive: Bool? = dict["confirmDestructive"] as? Bool
        let confirmMessage: String??  = dict.keys.contains("confirmMessage")
            ? .some(dict["confirmMessage"] as? String) : nil
        let cardThumbnailMode: CardThumbnailMode? = {
            guard let raw = dict["cardThumbnailMode"] as? String else { return nil }
            return CardThumbnailMode(rawValue: raw)
        }()

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
            icon: icon, iconText: iconText,
            backgroundColor: bg, textColor: tc,
            width: width, height: height, tooltip: tooltip,
            confirm: confirm,
            confirmMessage: confirmMessage,
            confirmDestructive: confirmDestructive,
            cardThumbnailMode: cardThumbnailMode,
            action: action
        )
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    func handleButtonDelete(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id}")
        }
        let ok = presetManager.deleteButton(id: id)
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    func handlePresetReorder(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let ids = dict["ids"] as? [String] else {
            return HTTPResponse.badRequest("body must be {ids: [String]}")
        }
        let ok = presetManager.reorderPresets(ids: ids)
        let order = presetManager.appConfig?.presetOrder ?? []
        return HTTPResponse.json(["ok": ok, "order": order])
    }

    @MainActor
    func handleButtonReorder(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let groupId = dict["groupId"] as? String,
              let ids = dict["ids"] as? [String] else {
            return HTTPResponse.badRequest("body must be {groupId, ids: [String]}")
        }
        let ok = presetManager.reorderButtons(ids: ids, inGroupId: groupId)
        return HTTPResponse.json(["ok": ok])
    }

    @MainActor
    func handleButtonMove(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String,
              let toGroupId = dict["toGroupId"] as? String else {
            return HTTPResponse.badRequest("body must contain {id, toGroupId}")
        }
        let position = (dict["position"] as? NSNumber)?.intValue
        let ok = presetManager.moveButton(id: id, toGroupId: toGroupId, at: position)
        return HTTPResponse.json(["ok": ok])
    }

    /// Press a button by id by **synthesizing a real mouse click** at the
    /// button's screen location (via Accessibility lookup + CGEvent). This
    /// means a test that calls `button_press` exercises the same OS event
    /// dispatch chain a Magic Mouse click takes — window manager, hit-test,
    /// SwiftUI gesture recognizer, Button.action — so failure modes that
    /// `executeButton` would mask (window obstruction, broken hit-test,
    /// disabled views) are caught.
    ///
    /// On success: 202 + visual press feedback in the panel, the human
    /// observer sees the cursor zip to the button and the button flash.
    /// On AX-lookup or CGEvent failure: 502 with a description so the
    /// caller can act (panel hidden, group collapsed, AX permission
    /// missing, etc.).
    @MainActor
    func handleButtonPress(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let id = dict["id"] as? String else {
            return HTTPResponse.badRequest("body must contain {id: String}")
        }

        // Phase 5: Web Panel from which the panel was opened (different from active preset)
        // to receive the button_press for displaying the currently active preset on the iPhone)
        // Search for IDs from all presets, not just the limited ones.
        let activePresetName = presetManager.currentPreset?.name
        var foundButton: ButtonDefinition? = nil
        var foundInPreset: String? = nil
        for panelCfg in (presetManager.appConfig?.panels ?? []) {
            guard let preset = presetManager.preset(named: panelCfg.presetName) else { continue }
            if let btn = preset.groups.flatMap({ $0.buttons }).first(where: { $0.id == id }) {
                foundButton = btn
                foundInPreset = preset.name
                if preset.name == activePresetName { break } // prioritize active
            }
        }
        guard let button = foundButton, let presetName = foundInPreset else {
            return HTTPResponse.json([
                "error": "button not found in any panel preset",
                "id":    id,
            ], status: 404)
        }

        // The Active preset button is an AX click (the cursor actually moves and is pressed)
        // Because a series of OS event chains are verified). Different preset buttons...
        // Directly execute actions (main purpose for Web Panels, AX click target panel)
        // Rescue cases that are not on the screen).
        if presetName == activePresetName {
            panel?.orderFront(nil)
            Task.detached {
                try? await Task.sleep(nanoseconds: 80_000_000)
                if let err = ButtonClicker.click(buttonId: id) {
                    LoggerContext.shared.error("ControlAPI",
                        "button_press click failed",
                        ["id": id, "error": err])
                }
            }
        } else {
            LoggerContext.shared.info("ControlAPI", "button_press direct execute", [
                "id":     id,
                "preset": presetName,
            ])
            presetManager.executeButton(button)
        }

        return HTTPResponse.json([
            "accepted":   true,
            "id":         button.id,
            "label":      button.label,
            "actionType": String(describing: button.action).split(separator: "(").first.map(String.init) ?? "?",
            "via":        "synthesized-mouse-click",
        ], status: 202)
    }

}
