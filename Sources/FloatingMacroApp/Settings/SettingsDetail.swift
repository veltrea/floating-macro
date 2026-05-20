import SwiftUI
import AppKit
import FloatingMacroCore

/// `NSColorWell` wrapper that keeps the SwiftUI binding in sync **while the
/// user is dragging inside `NSColorPanel`**. SwiftUI's built-in `ColorPicker`
/// on macOS only reports changes when the color panel is dismissed, which
/// makes real-time previews impossible. `NSColorWell.action` fires on every
/// color change from the panel, so bridging through it gives us a
/// continuously-updated binding.
struct ContinuousColorPicker: NSViewRepresentable {
    @Binding var color: Color

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        if #available(macOS 13.0, *) {
            well.colorWellStyle = .default
        }
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.color = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        context.coordinator.parent = self
        let incoming = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        if !(nsView.color.usingColorSpace(.sRGB)?.isEqual(incoming) ?? false) {
            nsView.color = incoming
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: ContinuousColorPicker
        init(_ parent: ContinuousColorPicker) { self.parent = parent }

        @objc func colorChanged(_ sender: NSColorWell) {
            parent.color = Color(nsColor: sender.color)
        }
    }
}

/// Detail editor for the currently selected button. Shows empty state when
/// nothing is selected.
struct SettingsDetail: View {
    @ObservedObject var presetManager: PresetManager
    @Binding var selectedButtonId: String?
    @Binding var selectedGroupId: String?

    var body: some View {
        if let btn = selectedButton {
            ButtonEditor(
                button: btn,
                presetManager: presetManager,
                onCommit: { updated in applyPatch(from: btn, to: updated) },
                onDelete: {
                    _ = presetManager.deleteButton(id: btn.id)
                    selectedButtonId = nil
                },
                parentGroupId: parentGroup?.id,
                parentDisplayType: parentGroup?.displayType ?? .icon,
                parentIconSize: parentGroup?.iconSize ?? .medium,
                parentShowLabels: parentGroup?.showLabels ?? true
            )
            // Force re-instantiation when selection changes so internal
            // @State fields refresh.
            .id(btn.id)
        } else if let group = selectedGroup {
            GroupEditor(
                group: group,
                presetManager: presetManager,
                onDelete: {
                    _ = presetManager.deleteGroup(id: group.id)
                    selectedGroupId = nil
                }
            )
            .id(group.id)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("左から編集するボタンまたはグループを選択してください_9b287c"))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedButton: ButtonDefinition? {
        guard let id = selectedButtonId,
              let preset = presetManager.currentPreset else { return nil }
        for g in preset.groups {
            if let b = g.buttons.first(where: { $0.id == id }) { return b }
        }
        return nil
    }

    private var parentGroup: ButtonGroup? {
        guard let id = selectedButtonId,
              let preset = presetManager.currentPreset else { return nil }
        return preset.groups.first(where: { $0.buttons.contains(where: { $0.id == id }) })
    }

    private var selectedGroup: ButtonGroup? {
        guard selectedButtonId == nil,
              let id = selectedGroupId,
              let preset = presetManager.currentPreset else { return nil }
        return preset.groups.first(where: { $0.id == id })
    }

    private func applyPatch(from old: ButtonDefinition, to new: ButtonDefinition) {
        _ = presetManager.updateButton(
            id: old.id,
            label: new.label,
            icon: .some(new.icon),
            iconText: .some(new.iconText),
            backgroundColor: .some(new.backgroundColor),
            textColor: .some(new.textColor),
            width: .some(new.width),
            height: .some(new.height),
            tooltip: .some(new.tooltip),
            confirm: new.confirm,
            confirmMessage: .some(new.confirmMessage),
            confirmDestructive: new.confirmDestructive,
            cardThumbnailMode: new.cardThumbnailMode,
            action: new.action
        )
    }
}

