import SwiftUI
import AppKit
import FloatingMacroCore

/// Root view of the Settings window. Left column: preset selector + group
/// browser. Right column: detail form for the selected button.
struct SettingsView: View {
    @ObservedObject var presetManager: PresetManager
    @State private var selectedButtonId: String?
    @State private var selectedGroupId: String?

    var body: some View {
        HSplitView {
            SettingsSidebar(
                presetManager: presetManager,
                selectedButtonId: $selectedButtonId,
                selectedGroupId: $selectedGroupId
            )
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)

            SettingsDetail(
                presetManager: presetManager,
                selectedButtonId: $selectedButtonId,
                selectedGroupId: $selectedGroupId
            )
            .frame(minWidth: 360, idealWidth: 420)
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { selectFirstButtonIfNeeded() }
        .onChange(of: presetManager.externalSelectButtonRequest) { requestedId in
            guard let id = requestedId else { return }
            applyExternalSelection(id)
            // Consume the request so the same id can be requested twice.
            presetManager.externalSelectButtonRequest = nil
        }
        .onChange(of: presetManager.externalSelectGroupRequest) { requestedId in
            guard let id = requestedId else { return }
            selectedGroupId = id
            selectedButtonId = nil
            presetManager.externalSelectGroupRequest = nil
        }
    }

    /// On open, auto-select the first button in the first non-empty group so
    /// the detail pane isn't an empty "select a button" message. Preserves
    /// the user's existing selection if they reopen the window.
    private func selectFirstButtonIfNeeded() {
        guard selectedButtonId == nil,
              let preset = presetManager.currentPreset else { return }
        for group in preset.groups {
            if let first = group.buttons.first {
                selectedGroupId = group.id
                selectedButtonId = first.id
                return
            }
        }
    }

    /// Jump selection to the given button id (usually from a right-click
    /// "Edit…" on the floating panel).
    private func applyExternalSelection(_ id: String) {
        guard let preset = presetManager.currentPreset else { return }
        for group in preset.groups {
            if group.buttons.contains(where: { $0.id == id }) {
                selectedGroupId = group.id
                selectedButtonId = id
                return
            }
        }
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @ObservedObject var presetManager: PresetManager
    @Binding var selectedButtonId: String?
    @Binding var selectedGroupId: String?

    @State private var newPresetName = ""
    @State private var newGroupLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preset picker
            HStack {
                Text("プリセット").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            HStack {
                Picker("", selection: Binding(
                    get: { presetManager.appConfig?.activePreset ?? "default" },
                    set: { presetManager.switchPreset(to: $0) }
                )) {
                    ForEach(presetManager.listPresets(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                Button(action: addPreset) {
                    Image(systemName: "plus")
                }
                .help("新しいプリセット")
                Button(action: deleteCurrentPreset) {
                    Image(systemName: "minus")
                }
                .disabled(presetManager.currentPreset?.name == "default")
                .help("現在のプリセットを削除")
            }

            Divider()

            // Group + button tree
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let preset = presetManager.currentPreset {
                        ForEach(preset.groups, id: \.id) { group in
                            groupRow(group)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider()

            // Add group + add button
            HStack {
                TextField("新グループ名", text: $newGroupLabel)
                    .textFieldStyle(.roundedBorder)
                Button("追加") { addGroup() }
                    .disabled(newGroupLabel.isEmpty)
            }
            Button(action: addEmptyButton) {
                Label("ボタン追加", systemImage: "plus.circle")
            }
            .disabled(selectedGroupId == nil)
        }
        .padding(8)
    }

    private func groupRow(_ group: ButtonGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button {
                    selectedGroupId = group.id
                    selectedButtonId = nil
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text(group.label).bold()
                        Spacer()
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedGroupId == group.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                Button {
                    _ = presetManager.deleteGroup(id: group.id)
                    if selectedGroupId == group.id {
                        selectedGroupId = nil
                        selectedButtonId = nil
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("グループ削除")
            }
            .contextMenu {
                Button {
                    selectedGroupId = group.id
                    selectedButtonId = nil
                } label: {
                    Label("編集", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    _ = presetManager.deleteGroup(id: group.id)
                    if selectedGroupId == group.id {
                        selectedGroupId = nil
                        selectedButtonId = nil
                    }
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }

            ForEach(group.buttons, id: \.id) { btn in
                Button {
                    selectedButtonId = btn.id
                    selectedGroupId = group.id
                } label: {
                    HStack(spacing: 6) {
                        if let icon = btn.iconText {
                            Text(icon)
                        } else {
                            Image(systemName: "square.fill")
                                .foregroundColor(.secondary)
                        }
                        Text(btn.label)
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedButtonId == btn.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
            }
        }
    }

    private func addPreset() {
        let name = "preset-\(Int.random(in: 1000...9999))"
        _ = presetManager.createPreset(name: name, displayName: name)
    }

    private func deleteCurrentPreset() {
        guard let name = presetManager.currentPreset?.name, name != "default" else { return }
        _ = presetManager.deletePreset(name: name)
    }

    private func addGroup() {
        let id = "g-\(Int.random(in: 1000...9999))"
        let group = ButtonGroup(id: id, label: newGroupLabel, buttons: [])
        _ = presetManager.addGroup(group)
        newGroupLabel = ""
    }

    private func addEmptyButton() {
        guard let groupId = selectedGroupId else { return }
        let id = "b-\(Int.random(in: 1000...9999))"
        let button = ButtonDefinition(
            id: id, label: "新ボタン",
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true)
        )
        _ = presetManager.addButton(button, toGroupId: groupId)
        selectedButtonId = id
    }
}
