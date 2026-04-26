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
            label: new.label,
            icon: .some(new.icon),
            iconText: .some(new.iconText),
            backgroundColor: .some(new.backgroundColor),
            textColor: .some(new.textColor),
            width: .some(new.width),
            height: .some(new.height),
            tooltip: .some(new.tooltip),
            action: new.action
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
    @State private var actionType: String = "text"   // 保存される有効アクション
    @State private var viewingType: String = "text"  // セグメントで閲覧中の種類（保存には使わない）
    // アクション種類ごとに独立した状態 —— 種類を切り替えても互いを上書きしない
    @State private var actionText: String = ""
    @State private var keyModCmd: Bool = false
    @State private var keyModShift: Bool = false
    @State private var keyModOption: Bool = false
    @State private var keyModCtrl: Bool = false
    @State private var keyBaseKey: String = ""
    @State private var launchTarget: String = ""
    @State private var terminalCommand: String = ""
    @State private var macroSteps: [MacroStepDraft] = []
    @State private var macroStopOnError: Bool = true

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

                    // エディター内プレビュー — 保存前の状態を確認できる
                    VStack(alignment: .leading, spacing: 4) {
                        Text("プレビュー").font(.caption).foregroundColor(.secondary)
                        HStack {
                            MacroButtonView(button: previewButton, onTap: {})
                                .fixedSize()
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                                if useBackgroundColor {
                                    ContinuousColorPicker(color: $backgroundColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: backgroundColor) { newValue in
                                            backgroundHex = Self.hexFromColor(newValue)
                                        }
                                    TextField("#RRGGBB", text: $backgroundHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                }
                            }
                        }

                        labeled("文字色") {
                            HStack {
                                Toggle("有効", isOn: $useTextColor)
                                if useTextColor {
                                    ContinuousColorPicker(color: $textColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: textColor) { newValue in
                                            textHex = Self.hexFromColor(newValue)
                                        }
                                    TextField("#RRGGBB", text: $textHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
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
                        HStack(alignment: .center) {
                            Text("アクション").font(.headline)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text(actionTypeDisplayName(actionType))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        Picker("種類", selection: $viewingType) {
                            Text("text").tag("text")
                            Text("key").tag("key")
                            Text("launch").tag("launch")
                            Text("terminal").tag("terminal")
                            Text("macro").tag("macro")
                        }
                        .pickerStyle(.segmented)

                        switch viewingType {
                        case "text":
                            labeled("貼り付けテキスト") {
                                TextEditor(text: $actionText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(minHeight: 80)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                            }
                        case "key":
                            VStack(alignment: .leading, spacing: 8) {
                                Text("修飾キー").font(.caption).foregroundColor(.secondary)
                                HStack(spacing: 16) {
                                    Toggle("⌘ cmd", isOn: $keyModCmd).toggleStyle(.checkbox)
                                    Toggle("⇧ shift", isOn: $keyModShift).toggleStyle(.checkbox)
                                    Toggle("⌥ option", isOn: $keyModOption).toggleStyle(.checkbox)
                                    Toggle("⌃ ctrl", isOn: $keyModCtrl).toggleStyle(.checkbox)
                                }
                                labeled("キー (a〜z / 0〜9 / space / return / esc 等)") {
                                    TextField("v", text: $keyBaseKey)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)
                                }
                                let preview = buildKeyCombo()
                                if !preview.isEmpty {
                                    Text("→ \(preview)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        case "launch":
                            labeled("起動対象 (パス / URL / bundle id / shell:)") {
                                HStack {
                                    TextField("/Applications/Slack.app", text: $launchTarget)
                                        .textFieldStyle(.roundedBorder)
                                    Button("参照...") { pickLaunchTarget() }
                                }
                            }
                        case "terminal":
                            labeled("コマンド (Terminal.app に投入)") {
                                TextField("cd ~/dev && claude", text: $terminalCommand)
                                    .textFieldStyle(.roundedBorder)
                            }
                        case "macro":
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(macroSteps.indices, id: \.self) { i in
                                    MacroStepRow(
                                        step: $macroSteps[i],
                                        canMoveUp: i > 0,
                                        canMoveDown: i < macroSteps.count - 1,
                                        onMoveUp:   { macroSteps.swapAt(i, i - 1) },
                                        onMoveDown: { macroSteps.swapAt(i, i + 1) },
                                        onDelete:   { macroSteps.remove(at: i) }
                                    )
                                }
                                Button {
                                    macroSteps.append(MacroStepDraft())
                                } label: {
                                    Label("ステップを追加", systemImage: "plus.circle")
                                }
                                .padding(.top, 2)
                                Toggle("エラーで中断", isOn: $macroStopOnError)
                                    .toggleStyle(.checkbox)
                                    .padding(.top, 4)
                            }
                        default: EmptyView()
                        }

                        if viewingType == actionType {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(actionTypeDisplayName(viewingType))が有効です")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            Button {
                                actionType = viewingType
                            } label: {
                                Label("この\(actionTypeDisplayName(viewingType))を有効にする", systemImage: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
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
        .onChange(of: presetManager.appIconPickerRequestNonce) { _ in
            showingAppIconPicker = true
        }
        .onChange(of: presetManager.dismissPickerNonce) { _ in
            showingSFSymbolPicker = false
            showingAppIconPicker = false
        }
        .onChange(of: presetManager.externalActionTypeRequest) { requested in
            guard let type = requested else { return }
            actionType = type
            viewingType = type
            presetManager.externalActionTypeRequest = nil
        }
        .onChange(of: presetManager.externalBackgroundColorRequest) { req in
            guard let req else { return }
            if let hex = req.hex, let color = Color(hex: hex) {
                useBackgroundColor = true
                backgroundColor = color
                backgroundHex = hex
            } else {
                useBackgroundColor = false
                backgroundHex = ""
            }
            presetManager.externalBackgroundColorRequest = nil
        }
        .onChange(of: presetManager.externalTextColorRequest) { req in
            guard let req else { return }
            if let hex = req.hex, let color = Color(hex: hex) {
                useTextColor = true
                textColor = color
                textHex = hex
            } else {
                useTextColor = false
                textHex = ""
            }
            presetManager.externalTextColorRequest = nil
        }
        .onChange(of: presetManager.commitNonce) { _ in
            commit()
        }
        .onChange(of: presetManager.externalKeyComboRequest) { req in
            guard let req else { return }
            parseKeyCombo(req.combo)
            presetManager.externalKeyComboRequest = nil
        }
        .onChange(of: presetManager.externalActionValueRequest) { req in
            guard let req else { return }
            switch req.type {
            case "text":     actionType = "text";     viewingType = "text";     actionText = req.value
            case "launch":   actionType = "launch";   viewingType = "launch";   launchTarget = req.value
            case "terminal": actionType = "terminal"; viewingType = "terminal"; terminalCommand = req.value
            default: break
            }
            presetManager.externalActionValueRequest = nil
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
            actionType = "text"; actionText = c
        case .key(let c):
            actionType = "key"; parseKeyCombo(c)
        case .launch(let t):
            actionType = "launch"; launchTarget = t
        case .terminal(_, let c, _, _, _):
            actionType = "terminal"; terminalCommand = c
        case .delay(let ms):
            actionType = "text"; actionText = "delay=\(ms)ms (編集非対応)"
        case .macro(let actions, let stopOnError):
            actionType = "macro"
            macroSteps = actions.map { MacroStepDraft.from($0) }
            macroStopOnError = stopOnError
        }
        viewingType = actionType
    }

    private func commit() {
        let widthVal = Double(width)
        let heightVal = Double(height)

        let newAction: Action
        switch actionType {
        case "text":
            newAction = .text(content: actionText, pasteDelayMs: 120, restoreClipboard: true)
        case "key":
            newAction = .key(combo: buildKeyCombo())
        case "launch":
            newAction = .launch(target: launchTarget)
        case "terminal":
            newAction = .terminal(app: "Terminal", command: terminalCommand,
                                  newWindow: true, execute: true, profile: nil)
        case "macro":
            let steps = macroSteps.compactMap { $0.toAction() }
            newAction = .macro(actions: steps, stopOnError: macroStopOnError)
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
            launchTarget = url.path
        }
    }

    // MARK: - Key combo helpers

    private func parseKeyCombo(_ combo: String) {
        let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        let modSet = Set(["cmd", "command", "shift", "option", "alt", "opt", "ctrl", "control"])
        keyModCmd    = parts.contains("cmd")    || parts.contains("command")
        keyModShift  = parts.contains("shift")
        keyModOption = parts.contains("option") || parts.contains("alt") || parts.contains("opt")
        keyModCtrl   = parts.contains("ctrl")   || parts.contains("control")
        keyBaseKey   = parts.last(where: { !modSet.contains($0) }) ?? ""
    }

    private func buildKeyCombo() -> String {
        var parts: [String] = []
        if keyModCmd    { parts.append("cmd") }
        if keyModShift  { parts.append("shift") }
        if keyModOption { parts.append("option") }
        if keyModCtrl   { parts.append("ctrl") }
        if !keyBaseKey.isEmpty { parts.append(keyBaseKey.lowercased()) }
        return parts.joined(separator: "+")
    }

    // MARK: - Helpers

    /// 現在のエディター状態を ButtonDefinition として合成する（保存前プレビュー用）
    private var previewButton: ButtonDefinition {
        ButtonDefinition(
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
            width: nil,
            height: nil,
            tooltip: nil,
            action: button.action
        )
    }

    private func actionTypeDisplayName(_ type: String) -> String {
        switch type {
        case "text":     return "テキスト貼り付け"
        case "key":      return "キー入力"
        case "launch":   return "アプリ起動"
        case "terminal": return "ターミナル"
        case "macro":    return "マクロ"
        default:         return type
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

                    // グループヘッダーのエディター内プレビュー
                    VStack(alignment: .leading, spacing: 4) {
                        Text("プレビュー").font(.caption).foregroundColor(.secondary)
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(previewTextColor)
                                    .frame(width: 12)
                                if !iconText.isEmpty {
                                    Text(iconText).font(.system(size: 12))
                                }
                                Text(label.isEmpty ? group.label : label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(previewTextColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                previewBackground.map { color in
                                    RoundedRectangle(cornerRadius: 4).fill(color)
                                }
                            )
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                                if useBackgroundColor {
                                    ContinuousColorPicker(color: $backgroundColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: backgroundColor) { newValue in
                                            backgroundHex = Self.hexFromColor(newValue)
                                        }
                                    TextField("#RRGGBB", text: $backgroundHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
                                }
                            }
                        }

                        labeled("文字色") {
                            HStack {
                                Toggle("有効", isOn: $useTextColor)
                                if useTextColor {
                                    ContinuousColorPicker(color: $textColor)
                                        .frame(width: 44, height: 24)
                                        .onChange(of: textColor) { newValue in
                                            textHex = Self.hexFromColor(newValue)
                                        }
                                    TextField("#RRGGBB", text: $textHex)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
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
        .onChange(of: presetManager.appIconPickerRequestNonce) { _ in
            showingAppIconPicker = true
        }
        .onChange(of: presetManager.dismissPickerNonce) { _ in
            showingSFSymbolPicker = false
            showingAppIconPicker = false
        }
        .onChange(of: presetManager.externalBackgroundColorRequest) { req in
            guard let req else { return }
            if let hex = req.hex, let color = Color(hex: hex) {
                useBackgroundColor = true
                backgroundColor = color
                backgroundHex = hex
            } else {
                useBackgroundColor = false
                backgroundHex = ""
            }
            presetManager.externalBackgroundColorRequest = nil
        }
        .onChange(of: presetManager.externalTextColorRequest) { req in
            guard let req else { return }
            if let hex = req.hex, let color = Color(hex: hex) {
                useTextColor = true
                textColor = color
                textHex = hex
            } else {
                useTextColor = false
                textHex = ""
            }
            presetManager.externalTextColorRequest = nil
        }
        .onChange(of: presetManager.commitNonce) { _ in
            commit()
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

    private var previewBackground: Color? {
        guard useBackgroundColor else { return nil }
        let hex = backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex
        return Color(hex: hex)
    }

    private var previewTextColor: Color {
        if useTextColor {
            let hex = textHex.isEmpty ? Self.hexFromColor(textColor) : textHex
            return Color(hex: hex) ?? .secondary
        }
        return .secondary
    }
}

// MARK: - MacroStepDraft

struct MacroStepDraft: Identifiable {
    var id = UUID()
    var type: String = "text"
    var text: String = ""
    var keyCombo: String = ""
    var launchTarget: String = ""
    var terminalCommand: String = ""
    var delayMs: String = "500"

    func toAction() -> Action? {
        switch type {
        case "text":
            return .text(content: text, pasteDelayMs: 120, restoreClipboard: true)
        case "key":
            guard !keyCombo.isEmpty else { return nil }
            return .key(combo: keyCombo)
        case "launch":
            guard !launchTarget.isEmpty else { return nil }
            return .launch(target: launchTarget)
        case "terminal":
            guard !terminalCommand.isEmpty else { return nil }
            return .terminal(app: "Terminal", command: terminalCommand,
                             newWindow: true, execute: true, profile: nil)
        case "delay":
            guard let ms = Int(delayMs), ms > 0 else { return nil }
            return .delay(ms: ms)
        default:
            return nil
        }
    }

    static func from(_ action: Action) -> MacroStepDraft {
        var d = MacroStepDraft()
        switch action {
        case .text(let c, _, _):
            d.type = "text"; d.text = c
        case .key(let c):
            d.type = "key"; d.keyCombo = c
        case .launch(let t):
            d.type = "launch"; d.launchTarget = t
        case .terminal(_, let c, _, _, _):
            d.type = "terminal"; d.terminalCommand = c
        case .delay(let ms):
            d.type = "delay"; d.delayMs = String(ms)
        case .macro:
            break
        }
        return d
    }
}

// MARK: - MacroStepRow

struct MacroStepRow: View {
    @Binding var step: MacroStepDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $step.type) {
                Text("text").tag("text")
                Text("key").tag("key")
                Text("launch").tag("launch")
                Text("terminal").tag("terminal")
                Text("delay").tag("delay")
            }
            .labelsHidden()
            .frame(width: 90)

            switch step.type {
            case "text":
                TextField("テキスト", text: $step.text)
                    .textFieldStyle(.roundedBorder)
            case "key":
                TextField("cmd+shift+v", text: $step.keyCombo)
                    .textFieldStyle(.roundedBorder)
            case "launch":
                TextField("/Applications/… または bundle id", text: $step.launchTarget)
                    .textFieldStyle(.roundedBorder)
            case "terminal":
                TextField("コマンド", text: $step.terminalCommand)
                    .textFieldStyle(.roundedBorder)
            case "delay":
                TextField("500", text: $step.delayMs)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("ms")
                    .foregroundColor(.secondary)
            default:
                EmptyView()
            }

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }
}
