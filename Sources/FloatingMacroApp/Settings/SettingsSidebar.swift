import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

// MARK: - Sidebar

struct SettingsSidebar: View {
    @ObservedObject var presetManager: PresetManager
    @Binding var selectedButtonId: String?
    @Binding var selectedGroupId: String?

    @State private var newPresetName = ""
    @State private var portText = ""
    @State private var lanPortText = ""
    /// Drop target highlight during drag (for group rows)
    @State private var dropTargetGroupId: String?
    /// Drag-and-drop drop target highlight (for button row)
    @State private var dropTargetButtonId: String?
    /// Display flag for preset sorting sheet
    @State private var showingPresetReorderSheet: Bool = false
    /// Flag for displaying the "Add from App..." picker sheet
    @State private var showingAppPickerSheet: Bool = false
    /// Local State for Preset Memo Editing. Switching Presets When
    /// Load from `currentPreset.memo`, save via PresetManager when changed.
    @State private var memoText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preset picker
            HStack {
                Text(L("Preset 96104a")).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            HStack {
                Picker("", selection: Binding(
                    get: { presetManager.appConfig?.activePreset ?? "default" },
                    set: { presetManager.switchPreset(to: $0) }
                )) {
                    ForEach(presetManager.presetEntries) { entry in
                        Text(entry.displayName).tag(entry.name)
                    }
                }
                .labelsHidden()
                Button(action: addPreset) {
                    Image(systemName: "plus")
                }
                .help(L("New preset: 7fefc6"))
                Button(action: deleteCurrentPreset) {
                    Image(systemName: "minus")
                }
                .disabled(presetManager.currentPreset?.name == "default")
                .help(L("Delete current preset 49de83"))
                Menu {
                    Button(L("Rename 1d1fd5"),        action: renameCurrentPreset)
                    Button(L("Sort_403f82"),          action: { showingPresetReorderSheet = true })
                    Divider()
                    Button(L("Export 4dc7ff"),       action: exportCurrentPreset)
                    Button(L("Export all presets: 9aa6b3"), action: exportAllPresets)
                    Button(L("import_c8bcdd"),         action: importPresets)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help(L("Rename Sort Export Import 174c89"))
            }

            // preset memo
            HStack {
                Text(L("memo_9490ad")).font(.caption).foregroundColor(.secondary)
                Spacer()
                if !memoText.isEmpty {
                    Text(L_("character_count", memoText.count))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            TextEditor(text: $memoText)
                .font(.system(size: 11))
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .help(L("This preset requires certain prerequisites and notes. You can refer to the top panel memo icon for details. 9337d8"))
            Text(L("Use before OS setting: Overwrite clipboard etc. Write down when you use the app again after a break. 3aF291"))
                .font(.caption2)
                .foregroundColor(.secondary)

            // AI mode picker
            HStack {
                Text(L("AI_mode_fec4eb")).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Picker("", selection: Binding(
                get: { presetManager.appConfig?.controlAPI.agentMode ?? .normal },
                set: { presetManager.setAgentMode($0) }
            )) {
                Text(L("Normal_b7519e")).tag(AgentMode.normal)
                Text(L("test_autonomous_1f6a94")).tag(AgentMode.test)
                Text("Claude Code").tag(AgentMode.claudeCode)
            }
            .labelsHidden()
            .help(L("GET_manifest_Switches to a system prompt for returning_767f36"))

            // AI Connection Configuration (Formerly Known As: Control API)
            HStack {
                Text(L("AI_Connection 3d125f")).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Toggle(L("on_22464d"), isOn: Binding(
                get: { presetManager.appConfig?.controlAPI.enabled ?? false },
                set: { presetManager.setControlAPIEnabled($0) }
            ))
            .help(L("Enabling this allows AI and external tools to operate the app via the _HTTP_API_ on a port fe4270."))
            HStack(spacing: 4) {
                Text(L("Port_4c1f86")).font(.caption).foregroundColor(.secondary)
                TextField("17430", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .onAppear {
                        portText = String(presetManager.appConfig?.controlAPI.port ?? 17430)
                    }
                    .onChange(of: presetManager.appConfig?.controlAPI.port) { newPort in
                        portText = String(newPort ?? 17430)
                    }
                    .onSubmit { commitPort() }
                Text("1024–65535").font(.caption2).foregroundColor(.secondary)
            }
            if presetManager.appConfig?.controlAPI.lanExposureEnabled == true {
                HStack(spacing: 4) {
                    Text("LAN Port").font(.caption).foregroundColor(.secondary)
                    TextField("17431", text: $lanPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onAppear {
                            lanPortText = String(presetManager.appConfig?.controlAPI.lanPort ?? 17431)
                        }
                        .onChange(of: presetManager.appConfig?.controlAPI.lanPort) { newPort in
                            lanPortText = String(newPort ?? 17431)
                        }
                        .onSubmit { commitLanPort() }
                    Text("1024–65535").font(.caption2).foregroundColor(.secondary)
                }
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
                Button(action: addGroup) {
                    Label(L("Group Add 49d331"), systemImage: "plus.circle")
                }
                Button(action: addEmptyButton) {
                    Label(L("Add Button _ae8c89"), systemImage: "plus.circle")
                }
                .disabled(selectedGroupId == nil)
                Button(action: { showingAppPickerSheet = true }) {
                    Label(L("Add _d9418a from app"), systemImage: "app.badge")
                }
                .disabled(selectedGroupId == nil)
                .help(L("Create Launch Button from Installed Apps List_f24f8d"))
            }
        }
        .padding(8)
        .sheet(isPresented: $showingPresetReorderSheet) {
            PresetReorderSheet(
                presetManager: presetManager,
                isPresented: $showingPresetReorderSheet
            )
        }
        .sheet(isPresented: $showingAppPickerSheet) {
            if let groupId = selectedGroupId {
                AppLauncherPickerSheet(
                    presetManager: presetManager,
                    groupId: groupId,
                    isPresented: $showingAppPickerSheet
                )
            }
        }
        .onAppear { syncMemoFromCurrentPreset() }
        .onChange(of: presetManager.currentPreset?.name) { _ in
            syncMemoFromCurrentPreset()
        }
        .onChange(of: memoText) { newValue in
            commitMemoIfChanged(newValue)
        }
    }

    /// Restore memoText that is being edited from currentPreset when switching presets.
    /// In the case of redrawing with the same preset, since `memoText` should already be up-to-date, do nothing.
    private func syncMemoFromCurrentPreset() {
        let next = presetManager.currentPreset?.memo ?? ""
        if memoText != next { memoText = next }
    }

    /// Save the memo being edited. The empty string is normalized to nil because,
    /// Ensure that the forward and backward conversion between "" does not result in a save loop.
    private func commitMemoIfChanged(_ newValue: String) {
        guard let preset = presetManager.currentPreset else { return }
        let normalized: String? = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : newValue
        if normalized != preset.memo {
            _ = presetManager.updatePresetMemo(name: preset.name, memo: normalized)
        }
    }

    private func groupRow(_ group: ButtonGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                HStack {
                    Image(systemName: "folder")
                    Text(group.label).bold()
                    Spacer()
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedGroupId == group.id && selectedButtonId == nil
                              ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor,
                                lineWidth: dropTargetGroupId == group.id ? 2 : 0)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedGroupId = group.id
                    selectedButtonId = nil
                }
                .onDrag {
                    NSItemProvider(object: "g:\(group.id)" as NSString)
                }
                .onDrop(of: [.text],
                        delegate: RowDropDelegate(
                            destGroupId: group.id,
                            beforeButtonId: nil,
                            isGroupTarget: true,
                            dropTargetGroupId: $dropTargetGroupId,
                            dropTargetButtonId: $dropTargetButtonId,
                            onDrop: { payload in
                                handleDrop(payload: payload,
                                           ontoGroupId: group.id,
                                           beforeButtonId: nil)
                            }))
                .contextMenu {
                    Button {
                        if let newId = presetManager.duplicateGroup(id: group.id) {
                            selectedGroupId = newId
                            selectedButtonId = nil
                        }
                    } label: {
                        Label(L("Copy_1fde1c"), systemImage: "plus.square.on.square")
                    }
                }

                Button {
                    renameGroup(group)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help(L("Rename Group f69757"))

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
                .help(L("Group deletion error: 7d09ee"))
            }
            ForEach(group.buttons, id: \.id) { btn in
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
                .overlay(
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .opacity(dropTargetButtonId == btn.id ? 1 : 0),
                    alignment: .top
                )
                .contentShape(Rectangle())
                .padding(.leading, 16)
                .onTapGesture {
                    selectedButtonId = btn.id
                    selectedGroupId = group.id
                }
                .onDrag {
                    NSItemProvider(object: "b:\(btn.id)" as NSString)
                }
                .onDrop(of: [.text],
                        delegate: RowDropDelegate(
                            destGroupId: group.id,
                            beforeButtonId: btn.id,
                            isGroupTarget: false,
                            dropTargetGroupId: $dropTargetGroupId,
                            dropTargetButtonId: $dropTargetButtonId,
                            onDrop: { payload in
                                handleDrop(payload: payload,
                                           ontoGroupId: group.id,
                                           beforeButtonId: btn.id)
                            }))
                .contextMenu {
                    Button {
                        if let newId = presetManager.duplicateButton(id: btn.id) {
                            selectedButtonId = newId
                            selectedGroupId = group.id
                        }
                    } label: {
                        Label(L("Copy_1fde1c"), systemImage: "plus.square.on.square")
                    }
                }
            }
        }
    }

    /// Core processing for drag-and-drop.
    /// payload: `"g:<id>"` for group, `"b:<id>"` for button
    /// drop target group
    /// Insert before button ID: Insert before the specified button. nil means at the end of the group.
    private func handleDrop(payload: String,
                            ontoGroupId destGroupId: String,
                            beforeButtonId: String?) -> Bool {
        guard let preset = presetManager.currentPreset else { return false }

        if payload.hasPrefix("b:") {
            let srcButtonId = String(payload.dropFirst(2))
            guard !srcButtonId.isEmpty else { return false }
            // Nothing happens when dropped on the same button
            if let bid = beforeButtonId, bid == srcButtonId { return false }

            // Use reorderButtons for reordering within the same group, and moveButton for cross-group movement.
            let srcGroupId: String? = preset.groups.first(where: {
                $0.buttons.contains(where: { $0.id == srcButtonId })
            })?.id

            if srcGroupId == destGroupId {
                guard let dest = preset.groups.first(where: { $0.id == destGroupId }) else { return false }
                var ids = dest.buttons.map { $0.id }
                ids.removeAll { $0 == srcButtonId }
                let insertIdx: Int
                if let bid = beforeButtonId, let i = ids.firstIndex(of: bid) {
                    insertIdx = i
                } else {
                    insertIdx = ids.count
                }
                ids.insert(srcButtonId, at: insertIdx)
                return presetManager.reorderButtons(ids: ids, inGroupId: destGroupId)
            } else {
                // Cross-group insertion: Determines the insertion position within the destination group.
                let position: Int?
                if let bid = beforeButtonId,
                   let dest = preset.groups.first(where: { $0.id == destGroupId }),
                   let i = dest.buttons.firstIndex(where: { $0.id == bid }) {
                    position = i
                } else {
                    position = nil
                }
                let ok = presetManager.moveButton(id: srcButtonId,
                                                  toGroupId: destGroupId,
                                                  at: position)
                if ok { selectedGroupId = destGroupId }
                return ok
            }
        }

        if payload.hasPrefix("g:") {
            let srcGroupId = String(payload.dropFirst(2))
            guard !srcGroupId.isEmpty, srcGroupId != destGroupId else { return false }
            // The group is inserted immediately before the drop target group.
            var ids = preset.groups.map { $0.id }
            ids.removeAll { $0 == srcGroupId }
            let insertIdx = ids.firstIndex(of: destGroupId) ?? ids.count
            ids.insert(srcGroupId, at: insertIdx)
            return presetManager.reorderGroups(ids: ids)
        }

        return false
    }

    private func addPreset() {
        let alert = NSAlert()
        alert.messageText = L("New preset: 7fefc6")
        alert.informativeText = L("Enter preset name: _free input_ changeable later_ 984cd1")
        alert.addButton(withTitle: L("Create 4f8c0a"))
        alert.addButton(withTitle: L("Cancel 6ef349"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = L("Example: MidJourney_Used_b050a8")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let displayName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        let internalName = presetManager.nextPresetName()
        if presetManager.createPreset(name: internalName, displayName: displayName) {
            presetManager.switchPreset(to: internalName)
        }
    }

    private func deleteCurrentPreset() {
        guard let name = presetManager.currentPreset?.name, name != "default" else { return }
        _ = presetManager.deletePreset(name: name)
    }

    private func renameCurrentPreset() {
        guard let preset = presetManager.currentPreset else { return }
        let alert = NSAlert()
        alert.messageText = L("Change Preset Name: 2d5bf7")
        alert.informativeText = L("Enter a new display name: _c5f18e")
        alert.addButton(withTitle: L("Change_fbcc6e"))
        alert.addButton(withTitle: L("Cancel 6ef349"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = preset.displayName
        textField.placeholderString = L("Display name_ea5693")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != preset.displayName else { return }
        _ = presetManager.renamePreset(name: preset.name, displayName: newName)
    }

    private func exportCurrentPreset() {
        guard let preset = presetManager.currentPreset,
              let data = presetManager.exportPresetData(name: preset.name) else { return }
        let panel = NSSavePanel()
        panel.title = L("Export preset _d51675")
        panel.nameFieldStringValue = "\(preset.displayName).fmpreset.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { presetManager.showTransientError(L_("export_failed", error.localizedDescription)) }
    }

    private func exportAllPresets() {
        guard let data = presetManager.exportAllPresetsData() else { return }
        let panel = NSSavePanel()
        panel.title = L("Export all presets _dd2086")
        panel.nameFieldStringValue = "presets.fmpreset-bundle.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { presetManager.showTransientError(L_("export_failed", error.localizedDescription)) }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.title = L("Import preset 0e2962")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return }
        var total = 0
        for url in panel.urls {
            total += presetManager.importPresets(from: url)
        }
        if total == 0 {
            presetManager.showTransientError(L("Failed to import: 0ca2b5"))
        }
    }

    private func addGroup() {
        let id = "g-\(Int.random(in: 1000...9999))"
        let group = ButtonGroup(id: id, label: L("New group_050f97"), buttons: [])
        _ = presetManager.addGroup(group)
        selectedGroupId = id
        selectedButtonId = nil
    }

    private func renameGroup(_ group: ButtonGroup) {
        let alert = NSAlert()
        alert.messageText = L("Rename Group f69757")
        alert.informativeText = L("Please enter a new name: 4d4602")
        alert.addButton(withTitle: L("Change_fbcc6e"))
        alert.addButton(withTitle: L("Cancel 6ef349"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = group.label
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newLabel = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newLabel.isEmpty, newLabel != group.label else { return }
        _ = presetManager.updateGroup(id: group.id, label: newLabel)
    }

    private func commitPort() {
        guard let port = Int(portText) else {
            // Reset invalid value
            portText = String(presetManager.appConfig?.controlAPI.port ?? 17430)
            return
        }
        presetManager.setControlAPIPort(port)
        // Update display to match clamped value within setControlAPIPort
        portText = String(presetManager.appConfig?.controlAPI.port ?? port)
    }

    private func commitLanPort() {
        guard let port = Int(lanPortText) else {
            lanPortText = String(presetManager.appConfig?.controlAPI.lanPort ?? 17431)
            return
        }
        presetManager.setControlAPILanPort(port)
        lanPortText = String(presetManager.appConfig?.controlAPI.lanPort ?? port)
    }

    private func addEmptyButton() {
        guard let groupId = selectedGroupId else { return }
        let id = "b-\(Int.random(in: 1000...9999))"
        let button = ButtonDefinition(
            id: id, label: L("New button _d6206a"),
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
        )
        _ = presetManager.addButton(button, toGroupId: groupId)
        selectedButtonId = id
    }
}
