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
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.color = NSColor(color)
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        context.coordinator.parent = self
        let incoming = NSColor(color)
        if !nsView.color.isEqual(incoming) {
            // Avoid a feedback loop: only push into the well when the source
            // of truth drifted outside of user interaction (e.g. hex typed).
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
                }
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
                Text("左から編集するボタンまたはグループを選択してください。")
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

    private var selectedGroup: ButtonGroup? {
        guard selectedButtonId == nil,
              let id = selectedGroupId,
              let preset = presetManager.currentPreset else { return nil }
        return preset.groups.first(where: { $0.id == id })
    }

    private func applyPatch(from old: ButtonDefinition, to new: ButtonDefinition) {
        _ = presetManager.updateButton(
            id: old.id,
            label: new.label != old.label ? new.label : nil,
            icon: new.icon != old.icon ? .some(new.icon) : nil,
            iconText: new.iconText != old.iconText ? .some(new.iconText) : nil,
            backgroundColor: new.backgroundColor != old.backgroundColor ? .some(new.backgroundColor) : nil,
            textColor: new.textColor != old.textColor ? .some(new.textColor) : nil,
            width: new.width != old.width ? .some(new.width) : nil,
            height: new.height != old.height ? .some(new.height) : nil,
            tooltip: new.tooltip != old.tooltip ? .some(new.tooltip) : nil,
            action: new.action != old.action ? new.action : nil
        )
    }
}

// MARK: - ButtonEditor

struct ButtonEditor: View {
    let button: ButtonDefinition
    @ObservedObject var presetManager: PresetManager
    let onCommit: (ButtonDefinition) -> Void
    let onDelete: () -> Void

    @State private var label: String = ""
    @State private var iconText: String = ""
    @State private var iconPath: String = ""
    @State private var showingSFSymbolPicker: Bool = false
    @State private var showingAppIconPicker: Bool = false
    @State private var confirmingDelete: Bool = false
    @State private var backgroundColor: Color = .clear
    @State private var backgroundHex: String = ""
    @State private var useBackgroundColor: Bool = false
    @State private var textColor: Color = .white
    @State private var textHex: String = ""
    @State private var useTextColor: Bool = false
    @State private var width: String = ""
    @State private var height: String = ""
    @State private var tooltip: String = ""
    @State private var actionType: String = "text"
    @State private var actionValue: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("ボタン: \(button.id)").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }

                    Group {
                        labeled("ラベル") {
                            TextField("表示文字列", text: $label)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled("アイコンテキスト (絵文字など)") {
                            TextField("🧠 や ⚡ など", text: $iconText)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled("アイコン画像 / アプリ / SF Symbol") {
                            HStack {
                                TextField("例: sf:star.fill / lucide:folder / com.apple.Safari", text: $iconPath)
                                    .textFieldStyle(.roundedBorder)
                                Button("参照...") { pickIconFile() }
                                Button("SF...") { showingSFSymbolPicker = true }
                                    .help("SF Symbol を一覧から選ぶ")
                                Button("アプリ...") { showingAppIconPicker = true }
                                    .help("インストール済みアプリのアイコンから選ぶ")
                                Button("クリア") { iconPath = "" }
                            }
                        }
                    }

                    Group {
                        labeled("背景色") {
                            HStack {
                                Toggle("有効", isOn: $useBackgroundColor)
                                    .onChange(of: useBackgroundColor) { newValue in
                                        applyBackgroundColorLive(enabled: newValue)
                                    }
                                if useBackgroundColor {
                                    ContinuousColorPicker(color: $backgroundColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: backgroundColor) { newValue in
                                            backgroundHex = Self.hexFromColor(newValue)
                                            applyBackgroundColorLive(enabled: true)
                                        }
                                    TextField("#RRGGBB", text: $backgroundHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                        .onChange(of: backgroundHex) { _ in
                                            applyBackgroundColorLive(enabled: useBackgroundColor)
                                        }
                                }
                            }
                        }

                        labeled("文字色") {
                            HStack {
                                Toggle("有効", isOn: $useTextColor)
                                    .onChange(of: useTextColor) { newValue in
                                        applyTextColorLive(enabled: newValue)
                                    }
                                if useTextColor {
                                    ContinuousColorPicker(color: $textColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: textColor) { newValue in
                                            textHex = Self.hexFromColor(newValue)
                                            applyTextColorLive(enabled: true)
                                        }
                                    TextField("#RRGGBB", text: $textHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                        .onChange(of: textHex) { _ in
                                            applyTextColorLive(enabled: useTextColor)
                                        }
                                } else {
                                    Text("(自動: 背景色があれば白、なければ システム既定)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        HStack {
                            labeled("幅") {
                                TextField("auto", text: $width)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeled("高さ") {
                                TextField("auto", text: $height)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    Divider()

                    Group {
                        Text("アクション").font(.headline)
                        Picker("種類", selection: $actionType) {
                            Text("text").tag("text")
                            Text("key").tag("key")
                            Text("launch").tag("launch")
                            Text("terminal").tag("terminal")
                        }
                        .pickerStyle(.segmented)

                        switch actionType {
                        case "text":
                            labeled("貼り付けテキスト") {
                                TextEditor(text: $actionValue)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(minHeight: 80)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                            }
                        case "key":
                            labeled("コンボ (例: cmd+shift+v)") {
                                TextField("cmd+v", text: $actionValue)
                                    .textFieldStyle(.roundedBorder)
                            }
                        case "launch":
                            labeled("起動対象 (パス / URL / bundle id / shell:)") {
                                HStack {
                                    TextField("/Applications/Slack.app", text: $actionValue)
                                        .textFieldStyle(.roundedBorder)
                                    Button("参照...") { pickLaunchTarget() }
                                }
                            }
                        case "terminal":
                            labeled("コマンド (Terminal.app に投入)") {
                                TextField("cd ~/dev && claude", text: $actionValue)
                                    .textFieldStyle(.roundedBorder)
                            }
                        default: EmptyView()
                        }

                        labeled("ツールチップ (ホバー時に表示)") {
                            TextField("ボタンの用途を説明", text: $tooltip)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                Button(action: commit) {
                    Label("保存", systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { loadFromButton() }
        .onChange(of: presetManager.sfPickerRequestNonce) { _ in
            showingSFSymbolPicker = true
        }
        .sheet(isPresented: $showingSFSymbolPicker) {
            SFSymbolPicker(
                selection: $iconPath,
                onClose: { showingSFSymbolPicker = false }
            )
        }
        .sheet(isPresented: $showingAppIconPicker) {
            AppIconPicker(
                selection: $iconPath,
                onClose: { showingAppIconPicker = false }
            )
        }
        .confirmationDialog(
            "このボタンを削除しますか?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("「\(button.label)」を削除", role: .destructive, action: onDelete)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は元に戻せません。")
        }
    }

    // MARK: - Mapping between state and model

    private func loadFromButton() {
        label = button.label
        iconText = button.iconText ?? ""
        iconPath = button.icon ?? ""
        tooltip = button.tooltip ?? ""
        if let hex = button.backgroundColor, let color = Color(hex: hex) {
            backgroundColor = color
            backgroundHex = hex
            useBackgroundColor = true
        } else {
            useBackgroundColor = false
            backgroundHex = ""
        }
        if let hex = button.textColor, let color = Color(hex: hex) {
            textColor = color
            textHex = hex
            useTextColor = true
        } else {
            useTextColor = false
            textHex = ""
        }
        width  = button.width.map { String(Int($0)) } ?? ""
        height = button.height.map { String(Int($0)) } ?? ""

        switch button.action {
        case .text(let c, _, _):
            actionType = "text"; actionValue = c
        case .key(let c):
            actionType = "key"; actionValue = c
        case .launch(let t):
            actionType = "launch"; actionValue = t
        case .terminal(_, let c, _, _, _):
            actionType = "terminal"; actionValue = c
        case .delay(let ms):
            actionType = "text"; actionValue = "delay=\(ms)ms (編集非対応)"
        case .macro:
            actionType = "text"; actionValue = "macro (JSON で直接編集してください)"
        }
    }

    private func commit() {
        let widthVal = Double(width)
        let heightVal = Double(height)

        let newAction: Action
        switch actionType {
        case "text":
            newAction = .text(content: actionValue, pasteDelayMs: 120, restoreClipboard: true)
        case "key":
            newAction = .key(combo: actionValue)
        case "launch":
            newAction = .launch(target: actionValue)
        case "terminal":
            newAction = .terminal(app: "Terminal", command: actionValue,
                                  newWindow: true, execute: true, profile: nil)
        default:
            newAction = button.action
        }

        let updated = ButtonDefinition(
            id: button.id,
            label: label,
            icon: iconPath.isEmpty ? nil : iconPath,
            iconText: iconText.isEmpty ? nil : iconText,
            backgroundColor: useBackgroundColor
                ? (backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex)
                : nil,
            textColor: useTextColor
                ? (textHex.isEmpty ? Self.hexFromColor(textColor) : textHex)
                : nil,
            width: widthVal,
            height: heightVal,
            tooltip: tooltip.isEmpty ? nil : tooltip,
            action: newAction
        )
        onCommit(updated)
    }

    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            iconPath = url.path
        }
    }

    private func pickLaunchTarget() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            actionValue = url.path
        }
    }

    // MARK: - Helpers

    private func labeled<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            content()
        }
    }

    private static func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let r = Int((nsColor.redComponent   * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Apply just the background color change to the live preset, bypassing
    /// the full `commit()` path so color-picker drags update the floating
    /// panel in real time.
    private func applyBackgroundColorLive(enabled: Bool) {
        let hex: String?
        if enabled {
            hex = backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex
        } else {
            hex = nil
        }
        _ = presetManager.updateButton(
            id: button.id,
            label: nil, icon: nil, iconText: nil,
            backgroundColor: .some(hex),
            textColor: nil, width: nil, height: nil,
            tooltip: nil, action: nil
        )
    }

    private func applyTextColorLive(enabled: Bool) {
        let hex: String?
        if enabled {
            hex = textHex.isEmpty ? Self.hexFromColor(textColor) : textHex
        } else {
            hex = nil
        }
        _ = presetManager.updateButton(
            id: button.id,
            label: nil, icon: nil, iconText: nil,
            backgroundColor: nil,
            textColor: .some(hex),
            width: nil, height: nil,
            tooltip: nil, action: nil
        )
    }
}

// MARK: - GroupEditor

struct GroupEditor: View {
    let group: ButtonGroup
    @ObservedObject var presetManager: PresetManager
    var onDelete: (() -> Void)? = nil

    @State private var label: String = ""
    @State private var iconText: String = ""
    @State private var iconPath: String = ""
    @State private var backgroundColor: Color = .clear
    @State private var backgroundHex: String = ""
    @State private var useBackgroundColor: Bool = false
    @State private var textColor: Color = .white
    @State private var textHex: String = ""
    @State private var useTextColor: Bool = false
    @State private var tooltip: String = ""
    @State private var showingSFSymbolPicker: Bool = false
    @State private var showingAppIconPicker: Bool = false
    @State private var confirmingDelete: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("グループ: \(group.id)").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        if onDelete != nil {
                            Button(role: .destructive) {
                                confirmingDelete = true
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }

                    Group {
                        labeled("グループ名") {
                            TextField("グループの見出し", text: $label)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled("アイコンテキスト (絵文字など)") {
                            TextField("🧠 や ⚡ など", text: $iconText)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled("アイコン画像 / アプリ / SF Symbol") {
                            HStack {
                                TextField("例: sf:folder.fill / com.apple.Safari", text: $iconPath)
                                    .textFieldStyle(.roundedBorder)
                                Button("参照...") { pickIconFile() }
                                Button("SF...") { showingSFSymbolPicker = true }
                                    .help("SF Symbol を一覧から選ぶ")
                                Button("アプリ...") { showingAppIconPicker = true }
                                    .help("インストール済みアプリのアイコンから選ぶ")
                                Button("クリア") { iconPath = "" }
                            }
                        }
                    }

                    Group {
                        labeled("背景色") {
                            HStack {
                                Toggle("有効", isOn: $useBackgroundColor)
                                    .onChange(of: useBackgroundColor) { newValue in
                                        applyBackgroundColorLive(enabled: newValue)
                                    }
                                if useBackgroundColor {
                                    ContinuousColorPicker(color: $backgroundColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: backgroundColor) { newValue in
                                            backgroundHex = Self.hexFromColor(newValue)
                                            applyBackgroundColorLive(enabled: true)
                                        }
                                    TextField("#RRGGBB", text: $backgroundHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                        .onChange(of: backgroundHex) { _ in
                                            applyBackgroundColorLive(enabled: useBackgroundColor)
                                        }
                                }
                            }
                        }

                        labeled("文字色") {
                            HStack {
                                Toggle("有効", isOn: $useTextColor)
                                    .onChange(of: useTextColor) { newValue in
                                        applyTextColorLive(enabled: newValue)
                                    }
                                if useTextColor {
                                    ContinuousColorPicker(color: $textColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: textColor) { newValue in
                                            textHex = Self.hexFromColor(newValue)
                                            applyTextColorLive(enabled: true)
                                        }
                                    TextField("#RRGGBB", text: $textHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                        .onChange(of: textHex) { _ in
                                            applyTextColorLive(enabled: useTextColor)
                                        }
                                } else {
                                    Text("(自動: 背景色があれば白、なければシステム既定)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    labeled("ツールチップ (ホバー時に表示)") {
                        TextField("グループの用途を説明", text: $tooltip)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("ボタン数: \(group.buttons.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                Button(action: commit) {
                    Label("保存", systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { loadFromGroup() }
        .sheet(isPresented: $showingSFSymbolPicker) {
            SFSymbolPicker(
                selection: $iconPath,
                onClose: { showingSFSymbolPicker = false }
            )
        }
        .sheet(isPresented: $showingAppIconPicker) {
            AppIconPicker(
                selection: $iconPath,
                onClose: { showingAppIconPicker = false }
            )
        }
        .confirmationDialog(
            "このグループを削除しますか?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("「\(group.label)」を削除", role: .destructive) { onDelete?() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("グループ内のボタンもすべて削除されます。この操作は元に戻せません。")
        }
    }

    // MARK: - Mapping between state and model

    private func loadFromGroup() {
        label = group.label
        iconText = group.iconText ?? ""
        iconPath = group.icon ?? ""
        tooltip = group.tooltip ?? ""
        if let hex = group.backgroundColor, let color = Color(hex: hex) {
            backgroundColor = color
            backgroundHex = hex
            useBackgroundColor = true
        } else {
            useBackgroundColor = false
            backgroundHex = ""
        }
        if let hex = group.textColor, let color = Color(hex: hex) {
            textColor = color
            textHex = hex
            useTextColor = true
        } else {
            useTextColor = false
            textHex = ""
        }
    }

    private func commit() {
        _ = presetManager.updateGroup(
            id: group.id,
            label: label.isEmpty ? nil : label,
            icon: iconPath.isEmpty ? .some(nil) : .some(iconPath),
            iconText: iconText.isEmpty ? .some(nil) : .some(iconText),
            backgroundColor: useBackgroundColor
                ? .some(backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex)
                : .some(nil),
            textColor: useTextColor
                ? .some(textHex.isEmpty ? Self.hexFromColor(textColor) : textHex)
                : .some(nil),
            tooltip: tooltip.isEmpty ? .some(nil) : .some(tooltip)
        )
    }

    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            iconPath = url.path
        }
    }

    private func labeled<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            content()
        }
    }

    private static func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let r = Int((nsColor.redComponent   * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Apply just the group's background color to the live preset so
    /// color-picker drags update the floating panel in real time.
    private func applyBackgroundColorLive(enabled: Bool) {
        let hex: String?
        if enabled {
            hex = backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex
        } else {
            hex = nil
        }
        _ = presetManager.updateGroup(
            id: group.id,
            label: nil, icon: nil, iconText: nil,
            backgroundColor: .some(hex),
            textColor: nil, tooltip: nil
        )
    }

    private func applyTextColorLive(enabled: Bool) {
        let hex: String?
        if enabled {
            hex = textHex.isEmpty ? Self.hexFromColor(textColor) : textHex
        } else {
            hex = nil
        }
        _ = presetManager.updateGroup(
            id: group.id,
            label: nil, icon: nil, iconText: nil,
            backgroundColor: nil,
            textColor: .some(hex),
            tooltip: nil
        )
    }
}
