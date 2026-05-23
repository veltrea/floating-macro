import Foundation
import AppKit
import FloatingMacroCore

extension PresetManager {

    // MARK: - Preset / group / button editing

    /// Apply a transform to the currently-active preset and persist.
    /// Errors bubble through `errorMessage` for the GUI, and the function
    /// returns whether the edit succeeded so HTTP callers can report it.
    ///
    /// Fix Phase 3: Update `loadedPresets[next.name]` synchronously. Without this, the...
    /// When the edit target is a preset other than panels[0], multiple panels are being read.
    /// The cache remains old, and the display after editing does not reflect it. directory
    /// Relying on a delay via watcher to reload may result in "moments of flickering after saving".
    /// Two bugs that will become the breeding ground for watcher and currentPreset.
    @discardableResult
    func editActivePreset(_ transform: (Preset) throws -> Preset) -> Bool {
        guard let preset = currentPreset else { return false }
        do {
            let next = try transform(preset)
            try writer.savePreset(next)
            currentPreset = next
            loadedPresets[next.name] = next
            return true
        } catch {
            showTransientError(L_("edit_failed", error.localizedDescription))
            return false
        }
    }

    func addGroup(_ group: ButtonGroup) -> Bool {
        editActivePreset { try PresetEditor.addGroup(group, to: $0) }
    }

    func updateGroup(id: String, label: String? = nil,
                      icon: String?? = nil, iconText: String?? = nil,
                      backgroundColor: String?? = nil, textColor: String?? = nil,
                      tooltip: String?? = nil, collapsed: Bool? = nil,
                      displayType: GroupDisplayType? = nil,
                      columns: GroupColumns? = nil,
                      iconSize: IconSize? = nil,
                      showLabels: Bool? = nil) -> Bool {
        editActivePreset { preset in
            try PresetEditor.updateGroup(groupId: id, in: preset) { g in
                g.patch(label: label, icon: icon, iconText: iconText,
                        backgroundColor: backgroundColor, textColor: textColor,
                        tooltip: tooltip, collapsed: collapsed,
                        displayType: displayType, columns: columns,
                        iconSize: iconSize, showLabels: showLabels)
            }
        }
    }

    func deleteGroup(id: String) -> Bool {
        editActivePreset { try PresetEditor.deleteGroup(groupId: id, from: $0) }
    }

    func addButton(_ button: ButtonDefinition, toGroupId: String, afterButtonId: String? = nil) -> Bool {
        editActivePreset { try PresetEditor.addButton(button, toGroupId: toGroupId, afterButtonId: afterButtonId, in: $0) }
    }

    func updateButton(id: String,
                      label: String?,
                      icon: String??,
                      iconText: String??,
                      backgroundColor: String??,
                      textColor: String??,
                      width: Double??,
                      height: Double??,
                      tooltip: String??,
                      confirm: Bool? = nil,
                      confirmMessage: String?? = nil,
                      confirmDestructive: Bool? = nil,
                      cardThumbnailMode: CardThumbnailMode? = nil,
                      action: Action?) -> Bool {
        editActivePreset { preset in
            try PresetEditor.updateButton(buttonId: id, in: preset) { b in
                b.patch(label: label,
                        icon: icon,
                        iconText: iconText,
                        backgroundColor: backgroundColor,
                        textColor: textColor,
                        width: width,
                        height: height,
                        tooltip: tooltip,
                        confirm: confirm,
                        confirmMessage: confirmMessage,
                        confirmDestructive: confirmDestructive,
                        cardThumbnailMode: cardThumbnailMode,
                        action: action)
            }
        }
    }

    func deleteButton(id: String) -> Bool {
        editActivePreset { try PresetEditor.deleteButton(buttonId: id, from: $0) }
    }

    /// Duplicate a group in-place with all its buttons. Each button gets a
    /// fresh id; the new group is inserted right after the source group.
    /// Returns the new group's id on success, nil otherwise.
    @discardableResult
    func duplicateGroup(id: String) -> String? {
        guard let preset = currentPreset,
              let src = preset.groups.first(where: { $0.id == id }) else { return nil }

        let newGroupId = "g-\(Int.random(in: 10000...99999))"
        let copiedButtons = src.buttons.map { b in
            ButtonDefinition(
                id: "b-\(Int.random(in: 10000...99999))",
                label: b.label,
                icon: b.icon,
                iconText: b.iconText,
                backgroundColor: b.backgroundColor,
                width: b.width,
                height: b.height,
                tooltip: b.tooltip,
                confirm: b.confirm,
                confirmMessage: b.confirmMessage,
                confirmDestructive: b.confirmDestructive,
                action: b.action
            )
        }
        let copy = ButtonGroup(
            id: newGroupId,
            label: L_("copy_of_named_item", src.label),
            icon: src.icon,
            iconText: src.iconText,
            backgroundColor: src.backgroundColor,
            textColor: src.textColor,
            tooltip: src.tooltip,
            collapsed: src.collapsed,
            buttons: copiedButtons
        )
        guard addGroup(copy) else { return nil }

        // Move the new group to right after the source group.
        var ids = (currentPreset?.groups.map { $0.id }) ?? []
        ids.removeAll { $0 == newGroupId }
        if let i = ids.firstIndex(of: id) {
            ids.insert(newGroupId, at: i + 1)
            _ = reorderGroups(ids: ids)
        }
        return newGroupId
    }

    /// Duplicate a button in-place. The copy is appended to the same group,
    /// gets a fresh id, and has " copy" appended to the label. Returns the
    /// new button's id if the operation succeeded, nil otherwise.
    @discardableResult
    func duplicateButton(id: String) -> String? {
        guard let preset = currentPreset else { return nil }
        // Find the source button and its group.
        var sourceGroup: ButtonGroup?
        var sourceButton: ButtonDefinition?
        for group in preset.groups {
            if let b = group.buttons.first(where: { $0.id == id }) {
                sourceGroup = group
                sourceButton = b
                break
            }
        }
        guard let group = sourceGroup, let src = sourceButton else { return nil }

        let newId = "b-\(Int.random(in: 10000...99999))"
        let copy = ButtonDefinition(
            id: newId,
            label: L_("copy_of_named_item", src.label),
            icon: src.icon,
            iconText: src.iconText,
            backgroundColor: src.backgroundColor,
            width: src.width,
            height: src.height,
            tooltip: src.tooltip,
            confirm: src.confirm,
            confirmMessage: src.confirmMessage,
            confirmDestructive: src.confirmDestructive,
            action: src.action
        )
        let ok = addButton(copy, toGroupId: group.id)
        return ok ? newId : nil
    }

    func reorderButtons(ids: [String], inGroupId: String) -> Bool {
        editActivePreset {
            try PresetEditor.reorderButtons(ids: ids, inGroupId: inGroupId, in: $0)
        }
    }

    func reorderGroups(ids: [String]) -> Bool {
        editActivePreset {
            try PresetEditor.reorderGroups(ids: ids, in: $0)
        }
    }

    func moveButton(id: String, toGroupId: String, at position: Int?) -> Bool {
        editActivePreset {
            try PresetEditor.moveButton(buttonId: id, toGroupId: toGroupId,
                                        at: position, in: $0)
        }
    }

    /// Create a new empty preset file. Refuses to overwrite an existing
    /// file — callers that want a fresh internal id should pass
    /// `nextPresetName()`.
    /// `memo` is optional; pass non-nil to seed a usage note on creation
    /// (mostly used by ACP `preset_create` so AI agents can write the memo
    /// at the same time they create the preset).
    func createPreset(name: String, displayName: String, memo: String? = nil) -> Bool {
        let url = loader.presetsURL.appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: url.path) {
            showTransientError(L_("preset_create_failed_exists", name))
            return false
        }
        let trimmed = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMemo: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let preset = Preset(name: name, displayName: displayName,
                            memo: normalizedMemo, groups: [])
        do {
            try writer.savePreset(preset)
            appendToPresetOrder([name])
            refreshPresetEntries()
            return true
        } catch {
            showTransientError(L_("preset_create_failed", error.localizedDescription))
            return false
        }
    }

    /// Append the given preset names to `appConfig.presetOrder` so newly
    /// created or imported presets land at the bottom of the user's
    /// chosen order (instead of being mixed alphabetically with other
    /// unknown names by the self-heal pass).
    func appendToPresetOrder(_ names: [String]) {
        guard var cfg = appConfig else { return }
        let existing = Set(cfg.presetOrder)
        let toAppend = names.filter { !existing.contains($0) }
        guard !toAppend.isEmpty else { return }
        cfg.presetOrder.append(contentsOf: toAppend)
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    func renamePreset(name: String, displayName: String) -> Bool {
        guard let p = (try? loader.loadPreset(name: name)) else { return false }
        let next = PresetEditor.renameDisplayName(displayName, of: p)
        do {
            try writer.savePreset(next)
            if currentPreset?.name == name { currentPreset = next }
            // Displaying cache synchronized. Immediate redraw for existing panels.
            if loadedPresets[name] != nil { loadedPresets[name] = next }
            refreshPresetEntries()
            return true
        } catch {
            showTransientError(L_("preset_rename_failed", error.localizedDescription))
            return false
        }
    }

    @discardableResult
    func updatePresetMemo(name: String, memo: String?) -> Bool {
        guard let p = (try? loader.loadPreset(name: name)) else { return false }
        let next = PresetEditor.updateMemo(memo, of: p)
        do {
            try writer.savePreset(next)
            if currentPreset?.name == name { currentPreset = next }
            // Synchronize cache that is currently being displayed.
            if loadedPresets[name] != nil { loadedPresets[name] = next }
            return true
        } catch {
            showTransientError(L_("memo_save_failed", error.localizedDescription))
            return false
        }
    }

}
