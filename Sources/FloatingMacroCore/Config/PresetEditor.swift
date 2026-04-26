import Foundation

/// Pure CRUD operations on `Preset` values. All methods return the modified
/// value rather than mutating in place, so callers (PresetManager, HTTP
/// handlers, tests) can decide whether to persist.
///
/// These are kept in Core so they're testable without AppKit.
public enum PresetEditor {

    public enum EditError: Error, Equatable {
        case groupNotFound(String)
        case buttonNotFound(String)
        case duplicateId(String)
        case reorderIdsMismatch(expected: Int, got: Int)
    }

    // MARK: - Groups

    public static func addGroup(_ group: ButtonGroup, to preset: Preset) throws -> Preset {
        if preset.groups.contains(where: { $0.id == group.id }) {
            throw EditError.duplicateId(group.id)
        }
        var updated = preset
        updated.groups.append(group)
        return updated
    }

    public static func updateGroup(
        groupId: String,
        in preset: Preset,
        apply: (inout ButtonGroup) -> Void
    ) throws -> Preset {
        var updated = preset
        guard let idx = updated.groups.firstIndex(where: { $0.id == groupId }) else {
            throw EditError.groupNotFound(groupId)
        }
        apply(&updated.groups[idx])
        return updated
    }

    public static func deleteGroup(groupId: String, from preset: Preset) throws -> Preset {
        var updated = preset
        guard let idx = updated.groups.firstIndex(where: { $0.id == groupId }) else {
            throw EditError.groupNotFound(groupId)
        }
        updated.groups.remove(at: idx)
        return updated
    }

    public static func reorderGroups(ids: [String], in preset: Preset) throws -> Preset {
        guard ids.count == preset.groups.count else {
            throw EditError.reorderIdsMismatch(expected: preset.groups.count, got: ids.count)
        }
        var byId: [String: ButtonGroup] = [:]
        for g in preset.groups { byId[g.id] = g }
        var reordered: [ButtonGroup] = []
        for id in ids {
            guard let g = byId[id] else { throw EditError.groupNotFound(id) }
            reordered.append(g)
        }
        var updated = preset
        updated.groups = reordered
        return updated
    }

    // MARK: - Buttons

    public static func addButton(
        _ button: ButtonDefinition,
        toGroupId groupId: String,
        in preset: Preset
    ) throws -> Preset {
        return try updateGroup(groupId: groupId, in: preset) { g in
            if !g.buttons.contains(where: { $0.id == button.id }) {
                g.buttons.append(button)
            }
        }
    }

    /// Update a button located anywhere in the preset by id.
    public static func updateButton(
        buttonId: String,
        in preset: Preset,
        apply: (inout ButtonDefinition) -> Void
    ) throws -> Preset {
        var updated = preset
        for groupIdx in updated.groups.indices {
            if let btnIdx = updated.groups[groupIdx].buttons.firstIndex(where: { $0.id == buttonId }) {
                apply(&updated.groups[groupIdx].buttons[btnIdx])
                return updated
            }
        }
        throw EditError.buttonNotFound(buttonId)
    }

    public static func deleteButton(buttonId: String, from preset: Preset) throws -> Preset {
        var updated = preset
        for groupIdx in updated.groups.indices {
            if let btnIdx = updated.groups[groupIdx].buttons.firstIndex(where: { $0.id == buttonId }) {
                updated.groups[groupIdx].buttons.remove(at: btnIdx)
                return updated
            }
        }
        throw EditError.buttonNotFound(buttonId)
    }

    public static func reorderButtons(
        ids: [String],
        inGroupId groupId: String,
        in preset: Preset
    ) throws -> Preset {
        return try updateGroup(groupId: groupId, in: preset) { g in
            var byId: [String: ButtonDefinition] = [:]
            for b in g.buttons { byId[b.id] = b }
            var reordered: [ButtonDefinition] = []
            for id in ids {
                if let b = byId[id] { reordered.append(b) }
            }
            if reordered.count == g.buttons.count {
                g.buttons = reordered
            }
        }
    }

    public static func moveButton(
        buttonId: String,
        toGroupId destGroupId: String,
        at position: Int? = nil,
        in preset: Preset
    ) throws -> Preset {
        var updated = preset
        // Pluck the button out of its current group.
        var plucked: ButtonDefinition?
        for groupIdx in updated.groups.indices {
            if let btnIdx = updated.groups[groupIdx].buttons.firstIndex(where: { $0.id == buttonId }) {
                plucked = updated.groups[groupIdx].buttons.remove(at: btnIdx)
                break
            }
        }
        guard let button = plucked else { throw EditError.buttonNotFound(buttonId) }
        guard let destIdx = updated.groups.firstIndex(where: { $0.id == destGroupId }) else {
            throw EditError.groupNotFound(destGroupId)
        }
        let insertAt = position.map { min(max($0, 0), updated.groups[destIdx].buttons.count) }
                        ?? updated.groups[destIdx].buttons.count
        updated.groups[destIdx].buttons.insert(button, at: insertAt)
        return updated
    }

    // MARK: - Preset-level
    public static func renameDisplayName(_ newName: String, of preset: Preset) -> Preset {
        var updated = preset
        updated.displayName = newName
        return updated
    }
}

// MARK: - Convenient in-place mutators

public extension ButtonDefinition {
    /// Partial update. Any non-nil argument replaces the current value.
    mutating func patch(label: String? = nil,
                        icon: String?? = nil,
                        iconText: String?? = nil,
                        backgroundColor: String?? = nil,
                        textColor: String?? = nil,
                        width: Double?? = nil,
                        height: Double?? = nil,
                        tooltip: String?? = nil,
                        action: Action? = nil) {
        if let label = label { self.label = label }
        if let icon = icon { self.icon = icon }
        if let iconText = iconText { self.iconText = iconText }
        if let backgroundColor = backgroundColor { self.backgroundColor = backgroundColor }
        if let textColor = textColor { self.textColor = textColor }
        if let width = width { self.width = width }
        if let height = height { self.height = height }
        if let tooltip = tooltip { self.tooltip = tooltip }
        if let action = action { self.action = action }
    }
}

public extension ButtonGroup {
    mutating func patch(label: String? = nil,
                        icon: String?? = nil,
                        iconText: String?? = nil,
                        backgroundColor: String?? = nil,
                        textColor: String?? = nil,
                        tooltip: String?? = nil,
                        collapsed: Bool? = nil) {
        if let label = label { self.label = label }
        if let icon = icon { self.icon = icon }
        if let iconText = iconText { self.iconText = iconText }
        if let backgroundColor = backgroundColor { self.backgroundColor = backgroundColor }
        if let textColor = textColor { self.textColor = textColor }
        if let tooltip = tooltip { self.tooltip = tooltip }
        if let collapsed = collapsed { self.collapsed = collapsed }
    }
}
