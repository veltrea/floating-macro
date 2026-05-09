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
            thumbnail: .some(new.thumbnail),
            cardThumbnailMode: new.cardThumbnailMode,
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
    @State private var confirmEnabled: Bool = false
    @State private var confirmMessageText: String = ""
    @State private var confirmDestructive: Bool = false
    /// Card タイプ用のサムネイル画像パス。group.displayType が .card のときに
    /// MacroButtonView がここを優先して表示する。空文字列で「未設定」。
    @State private var thumbnailPath: String = ""
    @State private var cardThumbnailMode: CardThumbnailMode = .fill
    @State private var actionType: String = "text"   // 保存される有効アクション
    @State private var viewingType: String = "text"  // セグメントで閲覧中の種類（保存には使わない）
    // アクション種類ごとに独立した状態 —— 種類を切り替えても互いを上書きしない
    @State private var actionText: String = ""
    /// text アクションの「追記モード」。ON の場合、ボタンを押すとペーストせず
    /// 既存のクリップボードに content が連結される。プロンプト断片を組み立てる
    /// ためのモード。
    @State private var actionAppendMode: Bool = false
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
                        Text(L_("button_id_label", button.id)).font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }

                    // エディター内プレビュー — 保存前の状態を確認できる
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("プレビュー_21b7d4")).font(.caption).foregroundColor(.secondary)
                        HStack {
                            MacroButtonView(button: previewButton, onTap: {})
                                .fixedSize()
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Group {
                        labeled(L("ラベル_fddf3e")) {
                            TextField(L("表示文字列_7516d5"), text: $label)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled(L("アイコンテキスト_絵文字など_c666a5")) {
                            TextField(L("や_など_49750c"), text: $iconText)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled(L("アイコン_d160a5")) {
                            HStack(alignment: .top, spacing: 12) {
                                IconDropZoneView(
                                    iconRef: iconPath,
                                    iconText: iconText,
                                    onDropImageURL: { url in
                                        importIconFile(from: url)
                                    },
                                    onClickFallback: { pickIconFile() }
                                )
                                VStack(alignment: .leading, spacing: 6) {
                                    Button("SF Symbol...") { showingSFSymbolPicker = true }
                                        .help(L("SF_Symbol_を一覧から選ぶ_ab178d"))
                                    Button(L("アプリから_29035e")) { showingAppIconPicker = true }
                                        .help(L("インストール済みアプリのアイコンから選ぶ_8d8c57"))
                                    Button(L("クリア_deba64")) { iconPath = "" }
                                        .disabled(iconPath.isEmpty)
                                    Text(L("画像をドロップするか枠をクリックすると_preset_配下にコピーして登録します_e6c5e7"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }

                        // Card タイプのグループに置いたときだけ視覚的に意味を持つ
                        // 画像。グループの displayType を編集者が即時に取れる
                        // 経路が無いため、常時表示にして見出しに用途を書く。
                        labeled(L("サムネイル_card_タイプのグループ用_c65447")) {
                            HStack(alignment: .top, spacing: 12) {
                                ThumbnailDropZoneView(
                                    thumbnailPath: thumbnailPath,
                                    onDropImageURL: { url in
                                        importThumbnailFile(from: url)
                                    },
                                    onClickFallback: { pickThumbnailFile() }
                                )
                                VStack(alignment: .leading, spacing: 6) {
                                    Button(L("クリア_deba64")) { thumbnailPath = "" }
                                        .disabled(thumbnailPath.isEmpty)
                                    Text(L("親グループの表示タイプが_card_のときに大きく表示されます_icon_wide_では無視されます_f23931"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Picker(L("表示モード_23d885"), selection: $cardThumbnailMode) {
                                        Text(L("クロップ_fa6ab1")).tag(CardThumbnailMode.fill)
                                        Text(L("全体表示_992e61")).tag(CardThumbnailMode.fit)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 200)
                                    Text(cardThumbnailMode == .fill
                                        ? L("画像を拡大して正方形を埋める_はみ出す部分は切り取り_f8bed8")
                                        : L("画像全体をアスペクト比を保って表示_余白あり_0e78fd"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Group {
                        labeled(L("背景色_2f97db")) {
                            HStack {
                                Toggle(L("有効_ce1518"), isOn: $useBackgroundColor)
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

                        labeled(L("文字色_94e49c")) {
                            HStack {
                                Toggle(L("有効_ce1518"), isOn: $useTextColor)
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
                                    Text(L("自動_背景色があれば白_なければ_システム既定_fe1254"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        HStack {
                            labeled(L("幅_cfd914")) {
                                TextField("auto", text: $width)
                                    .textFieldStyle(.roundedBorder)
                            }
                            labeled(L("高さ_def5c2")) {
                                TextField("auto", text: $height)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    Divider()

                    Group {
                        HStack(alignment: .center) {
                            Text(L("アクション_36a9d7")).font(.headline)
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
                        Picker(L("種類_e84e1e"), selection: $viewingType) {
                            Text("text").tag("text")
                            Text("key").tag("key")
                            Text("launch").tag("launch")
                            Text("terminal").tag("terminal")
                            Text("macro").tag("macro")
                        }
                        .pickerStyle(.segmented)

                        switch viewingType {
                        case "text":
                            labeled(L("貼り付けテキスト_de7105")) {
                                TextEditor(text: $actionText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(minHeight: 80)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(isOn: $actionAppendMode) {
                                    Text(L("追記モード_プロンプトビルダー_4653eb"))
                                }
                                .toggleStyle(.checkbox)
                                Text(L("ON_にすると_ボタンを押してもペーストせず_上のテキストが既存のクリップボードに連結されます_プロ_09cf9e"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 4)
                        case "key":
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("修飾キー_475829")).font(.caption).foregroundColor(.secondary)
                                HStack(spacing: 16) {
                                    Toggle("⌘ cmd", isOn: $keyModCmd).toggleStyle(.checkbox)
                                    Toggle("⇧ shift", isOn: $keyModShift).toggleStyle(.checkbox)
                                    Toggle("⌥ option", isOn: $keyModOption).toggleStyle(.checkbox)
                                    Toggle("⌃ ctrl", isOn: $keyModCtrl).toggleStyle(.checkbox)
                                }
                                labeled(L("キー_a_z_0_9_矢印_Delete_F1_等_4a4c33")) {
                                    HStack(spacing: 8) {
                                        TextField("v", text: $keyBaseKey)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 120)
                                        KeyRecorderButton(
                                            modCmd: $keyModCmd,
                                            modShift: $keyModShift,
                                            modOption: $keyModOption,
                                            modCtrl: $keyModCtrl,
                                            baseKey: $keyBaseKey
                                        )
                                        SpecialKeyMenu(baseKey: $keyBaseKey)
                                    }
                                }
                                let preview = buildKeyCombo()
                                if !preview.isEmpty {
                                    Text("→ \(preview)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        case "launch":
                            labeled(L("起動対象_パス_URL_bundle_id_shell_09a2e0")) {
                                HStack {
                                    TextField("/Applications/Slack.app", text: $launchTarget)
                                        .textFieldStyle(.roundedBorder)
                                    Button(L("参照_69faf0")) { pickLaunchTarget() }
                                }
                            }
                        case "terminal":
                            labeled(L("コマンド_Terminal_app_に投入_21f117")) {
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
                                    Label(L("ステップを追加_55f11e"), systemImage: "plus.circle")
                                }
                                .padding(.top, 2)
                                Toggle(L("エラーで中断_3f6a5d"), isOn: $macroStopOnError)
                                    .toggleStyle(.checkbox)
                                    .padding(.top, 4)
                            }
                        default: EmptyView()
                        }

                        if viewingType == actionType {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(L_("action_type_is_active", actionTypeDisplayName(viewingType)))
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            Button {
                                actionType = viewingType
                            } label: {
                                Label(L_("enable_this_action_type", actionTypeDisplayName(viewingType)), systemImage: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        labeled(L("ツールチップ_ホバー時に表示_e40d98")) {
                            TextField(L("ボタンの用途を説明_ee7b98"), text: $tooltip)
                                .textFieldStyle(.roundedBorder)
                        }

                        // 実行前の確認ダイアログ。視線入力ユーザーや、再起動・
                        // シャットダウン等の取り返しのつかない操作を 1 タップで
                        // 発火させたくないボタン向け。
                        labeled(L("実行前の確認_a9e65b")) {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(L("実行前に確認ダイアログを出す_3a4d8d"), isOn: $confirmEnabled)
                                    .toggleStyle(.checkbox)
                                if confirmEnabled {
                                    VStack(alignment: .leading, spacing: 4) {
                                        TextField(L("確認メッセージ_空欄なら自動生成_cf8221"),
                                                  text: $confirmMessageText)
                                            .textFieldStyle(.roundedBorder)
                                        Toggle(L("危険な操作_実行ボタンを赤く強調_618998"),
                                               isOn: $confirmDestructive)
                                            .toggleStyle(.checkbox)
                                            .help(L("再起動_シャットダウン等_取り消しのきかない操作のみ_ON_にしてください_65f3ba"))
                                    }
                                    .padding(.leading, 18)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(L("削除_c6577c"), systemImage: "trash")
                }
                Button(action: commit) {
                    Label(L("保存_be5fbb"), systemImage: "checkmark.circle.fill")
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
            actionType = "key"
            viewingType = "key"
            presetManager.externalKeyComboRequest = nil
        }
        .onChange(of: keyBaseKey) { newValue in
            // key セグメントで特殊キー / キー記録 / 手入力により baseKey が
            // 入った瞬間に「key アクション」として確定する。明示的な「有効にする」
            // ボタンを押し忘れて actionType が text のまま保存される事故を防ぐ。
            if !newValue.isEmpty && viewingType == "key" {
                actionType = "key"
            }
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
            L("このボタンを削除しますか_ec2177"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L_("delete_named_item", button.label), role: .destructive, action: onDelete)
            Button(L("キャンセル_6ef349"), role: .cancel) {}
        } message: {
            Text(L("この操作は元に戻せません_3955a5"))
        }
    }

    // MARK: - Mapping between state and model

    private func loadFromButton() {
        label = button.label
        iconText = button.iconText ?? ""
        iconPath = button.icon ?? ""
        thumbnailPath = button.thumbnail ?? ""
        cardThumbnailMode = button.cardThumbnailMode
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
        confirmEnabled     = button.confirm
        confirmMessageText = button.confirmMessage ?? ""
        confirmDestructive = button.confirmDestructive

        switch button.action {
        case .text(let c, _, _, let append):
            actionType = "text"; actionText = c; actionAppendMode = append
        case .key(let c):
            actionType = "key"; parseKeyCombo(c)
        case .launch(let t):
            actionType = "launch"; launchTarget = t
        case .terminal(_, let c, _, _, _):
            actionType = "terminal"; terminalCommand = c
        case .delay(let ms):
            actionType = "text"; actionText = L_("delay_not_editable", ms)
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
            newAction = .text(content: actionText, pasteDelayMs: 120,
                              restoreClipboard: true, appendMode: actionAppendMode)
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

        // confirm が無効のときは関連フィールドを規定値に正規化して保存する。
        // (UI で confirmEnabled を OFF にした瞬間に「メッセージ」「危険操作」が
        // ファイルに残らないようにする — 再 ON 時に意図せず復活するのを防ぐ。)
        let normalizedConfirmMessage: String? = {
            guard confirmEnabled else { return nil }
            let trimmed = confirmMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let normalizedConfirmDestructive = confirmEnabled ? confirmDestructive : false

        // 旧データ移行: 外部の絶対パス (ユーザーの ~/Pictures など) が残っている
        // ボタンを保存するときは、preset 配下にコピーしてリンク切れを未然に防ぐ。
        // SF Symbol / bundle id / lucide / 既に管理ディレクトリ内のパスは素通り。
        let migratedIcon = Self.migrateIfNeeded(
            path: iconPath.isEmpty ? nil : iconPath,
            into: .icons,
            assetId: button.id,
            presetManager: presetManager
        )
        let migratedThumbnail = Self.migrateIfNeeded(
            path: thumbnailPath.isEmpty ? nil : thumbnailPath,
            into: .images,
            assetId: button.id,
            presetManager: presetManager
        )
        // 移行が走った場合は @State にも反映してプレビューを最新パスに揃える。
        if let m = migratedIcon, m != iconPath { iconPath = m }
        if let m = migratedThumbnail, m != thumbnailPath { thumbnailPath = m }

        let updated = ButtonDefinition(
            id: button.id,
            label: label,
            icon: migratedIcon,
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
            confirm: confirmEnabled,
            confirmMessage: normalizedConfirmMessage,
            confirmDestructive: normalizedConfirmDestructive,
            thumbnail: migratedThumbnail,
            cardThumbnailMode: cardThumbnailMode,
            action: newAction
        )
        onCommit(updated)
    }

    /// commit 時に呼ぶラッパ。preset 名が解決できなければ何もせずパスを返す。
    fileprivate static func migrateIfNeeded(
        path: String?,
        into subdirectory: IconAssetSaver.AssetSubdirectory,
        assetId: String,
        presetManager: PresetManager
    ) -> String? {
        guard let presetName = presetManager.currentPreset?.name else {
            return path
        }
        return IconAssetSaver.migrateExternalImagePath(
            path,
            into: subdirectory,
            assetId: assetId,
            presetName: presetName
        )
    }

    /// ドロップゾーンのフォールバッククリック (NSOpenPanel 経由) でファイルを選択。
    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("選択_8ba15a")
        if panel.runModal() == .OK, let url = panel.url {
            importIconFile(from: url)
        }
    }

    /// 同上 (サムネイル用)。
    private func pickThumbnailFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("選択_8ba15a")
        if panel.runModal() == .OK, let url = panel.url {
            importThumbnailFile(from: url)
        }
    }

    /// ドラッグ&ドロップ / ファイル選択で受け取った画像をアイコンとして取り込む。
    /// preset 配下の `icons/<button-id>.<ext>` にコピーしてから絶対パスを `iconPath`
    /// に格納する。失敗時はトーストで通知し、状態は変更しない。
    fileprivate func importIconFile(from url: URL) {
        guard let newPath = Self.importImage(
            from: url, into: .icons,
            assetId: button.id, presetManager: presetManager
        ) else { return }
        iconPath = newPath
    }

    /// 同上 (サムネイル用)。
    fileprivate func importThumbnailFile(from url: URL) {
        guard let newPath = Self.importImage(
            from: url, into: .images,
            assetId: button.id, presetManager: presetManager
        ) else { return }
        thumbnailPath = newPath
    }

    /// ファイルピッカー / DnD で渡されたファイルを preset 配下にコピーする
    /// 共通処理。コピー失敗時は `nil` を返してトーストでエラー通知。
    fileprivate static func importImage(
        from source: URL,
        into subdirectory: IconAssetSaver.AssetSubdirectory,
        assetId: String,
        presetManager: PresetManager
    ) -> String? {
        guard let presetName = presetManager.currentPreset?.name else {
            presetManager.showTransientError(
                L("アクティブな_preset_が見つかりません_2ddc75"), clearAfter: 4)
            return nil
        }
        do {
            return try IconAssetSaver.copyImage(
                from: source,
                into: subdirectory,
                assetId: assetId,
                presetName: presetName
            )
        } catch {
            presetManager.showTransientError(
                L_("image_import_failed", error.localizedDescription),
                clearAfter: 4
            )
            return nil
        }
    }

    private func pickLaunchTarget() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("選択_8ba15a")
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
            confirm: confirmEnabled,
            confirmMessage: confirmEnabled
                ? (confirmMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : confirmMessageText)
                : nil,
            confirmDestructive: confirmEnabled ? confirmDestructive : false,
            thumbnail: thumbnailPath.isEmpty ? nil : thumbnailPath,
            cardThumbnailMode: cardThumbnailMode,
            action: button.action
        )
    }

    private func actionTypeDisplayName(_ type: String) -> String {
        switch type {
        case "text":     return L("テキスト貼り付け_542a65")
        case "key":      return L("キー入力_fdc0ab")
        case "launch":   return L("アプリ起動_d176e3")
        case "terminal": return L("ターミナル_3da5b3")
        case "macro":    return L("マクロ_07bc32")
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
    @State private var displayType: GroupDisplayType = .icon
    @State private var columns: GroupColumns = .auto
    @State private var iconSize: IconSize = .medium
    @State private var showLabels: Bool = true
    @State private var showingSFSymbolPicker: Bool = false
    @State private var showingAppIconPicker: Bool = false
    @State private var confirmingDelete: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L_("group_id_label", group.id)).font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }

                    // グループヘッダーのエディター内プレビュー
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("プレビュー_21b7d4")).font(.caption).foregroundColor(.secondary)
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
                        labeled(L("グループ名_0a11c7")) {
                            TextField(L("グループの見出し_f24511"), text: $label)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled(L("アイコンテキスト_絵文字など_c666a5")) {
                            TextField(L("や_など_49750c"), text: $iconText)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled(L("アイコン_d160a5")) {
                            HStack(alignment: .top, spacing: 12) {
                                IconDropZoneView(
                                    iconRef: iconPath,
                                    iconText: iconText,
                                    onDropImageURL: { url in importIconFile(from: url) },
                                    onClickFallback: { pickIconFile() }
                                )
                                VStack(alignment: .leading, spacing: 6) {
                                    Button("SF Symbol...") { showingSFSymbolPicker = true }
                                        .help(L("SF_Symbol_を一覧から選ぶ_ab178d"))
                                    Button(L("アプリから_29035e")) { showingAppIconPicker = true }
                                        .help(L("インストール済みアプリのアイコンから選ぶ_8d8c57"))
                                    Button(L("クリア_deba64")) { iconPath = "" }
                                        .disabled(iconPath.isEmpty)
                                    Text(L("画像をドロップするか枠をクリックすると_preset_配下にコピーして登録します_e6c5e7"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    Group {
                        labeled(L("背景色_2f97db")) {
                            HStack {
                                Toggle(L("有効_ce1518"), isOn: $useBackgroundColor)
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

                        labeled(L("文字色_94e49c")) {
                            HStack {
                                Toggle(L("有効_ce1518"), isOn: $useTextColor)
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
                                    Text(L("自動_背景色があれば白_なければシステム既定_22d22a"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    displayTypeSection

                    labeled(L("ツールチップ_ホバー時に表示_e40d98")) {
                        TextField(L("グループの用途を説明_5a4540"), text: $tooltip)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text(L_("button_count_label", group.buttons.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                if onDelete != nil {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label(L("削除_c6577c"), systemImage: "trash")
                    }
                }
                Button(action: commit) {
                    Label(L("保存_be5fbb"), systemImage: "checkmark.circle.fill")
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
            L("このグループを削除しますか_fd0e79"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L_("delete_named_item", group.label), role: .destructive) { onDelete?() }
            Button(L("キャンセル_6ef349"), role: .cancel) {}
        } message: {
            Text(L("グループ内のボタンもすべて削除されます_この操作は元に戻せません_4da004"))
        }
    }

    // MARK: - Mapping between state and model

    private func loadFromGroup() {
        label = group.label
        iconText = group.iconText ?? ""
        iconPath = group.icon ?? ""
        tooltip = group.tooltip ?? ""
        displayType = group.displayType
        columns = group.columns
        iconSize = group.iconSize
        showLabels = group.showLabels
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
        // ButtonEditor と同じ自動移行: 外部絶対パスを preset 配下にコピー。
        let migratedIcon = ButtonEditor.migrateIfNeeded(
            path: iconPath.isEmpty ? nil : iconPath,
            into: .icons,
            assetId: group.id,
            presetManager: presetManager
        )
        if let m = migratedIcon, m != iconPath { iconPath = m }

        _ = presetManager.updateGroup(
            id: group.id,
            label: label.isEmpty ? nil : label,
            icon: migratedIcon == nil ? .some(nil) : .some(migratedIcon),
            iconText: iconText.isEmpty ? .some(nil) : .some(iconText),
            backgroundColor: useBackgroundColor
                ? .some(backgroundHex.isEmpty ? Self.hexFromColor(backgroundColor) : backgroundHex)
                : .some(nil),
            textColor: useTextColor
                ? .some(textHex.isEmpty ? Self.hexFromColor(textColor) : textHex)
                : .some(nil),
            tooltip: tooltip.isEmpty ? .some(nil) : .some(tooltip),
            displayType: displayType,
            columns: (displayType == .card || displayType == .grid) ? columns : nil,
            iconSize: iconSize,
            showLabels: displayType == .grid ? showLabels : nil
        )
    }

    @ViewBuilder
    private var displayTypeSection: some View {
        labeled(L("ボタンの表示タイプ_4d03fd")) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $displayType) {
                    Text(L("icon_小さなアイコン_9d9c3e")).tag(GroupDisplayType.icon)
                    Text(L("wide_横長セル_9e31df")).tag(GroupDisplayType.wide)
                    Text(L("card_大きなサムネイル_ed0037")).tag(GroupDisplayType.card)
                    Text(L("grid_アイコングリッド_d4e92a")).tag(GroupDisplayType.grid)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(displayTypeHint(displayType))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if displayType == .card || displayType == .grid {
            labeled(L("列数_b2c7f3")) {
                columnsPickerContent
            }
        }
        labeled(L("アイコンサイズ_f7a3c2")) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $iconSize) {
                    Text("S (16pt)").tag(IconSize.small)
                    Text("M (32pt)").tag(IconSize.medium)
                    Text("L (48pt)").tag(IconSize.large)
                    Text("XL (64pt)").tag(IconSize.xlarge)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(L("アプリアイコンや絵文字の表示サイズを変更します_b8e1d4"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if displayType == .grid {
            labeled(L("ラベル表示_a1d5f8")) {
                Toggle(L("アイコンの下に名前を表示_c3b7e2"), isOn: $showLabels)
            }
        }
    }

    @ViewBuilder
    private var columnsPickerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if displayType == .grid {
                HStack(spacing: 8) {
                    Text(L("自動_5c8b29"))
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(columns == .auto ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .onTapGesture { columns = .auto }
                    Stepper(
                        value: Binding(
                            get: { if case .fixed(let n) = columns { return n } else { return 4 } },
                            set: { columns = .fixed(max(1, min($0, 12))) }
                        ),
                        in: 1...12
                    ) {
                        Text(columnStepperLabel)
                            .font(.system(size: 11))
                    }
                    .onTapGesture {
                        if columns == .auto { columns = .fixed(4) }
                    }
                }
            } else {
                Picker("", selection: $columns) {
                    Text(L("自動_5c8b29")).tag(GroupColumns.auto)
                    Text("1").tag(GroupColumns.fixed(1))
                    Text("2").tag(GroupColumns.fixed(2))
                    Text("3").tag(GroupColumns.fixed(3))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Text(columnsHint(columns))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var columnStepperLabel: String {
        if case .fixed(let n) = columns {
            return L_("fixed_columns_short", n)
        }
        return L("自動_5c8b29")
    }

    /// 表示タイプの違いを 1 行で説明するヘルプ文字列。
    private func displayTypeHint(_ type: GroupDisplayType) -> String {
        switch type {
        case .icon: return L("既存の小さなアイコン_ラベルを縦に並べる_コンパクトな表示_08324c")
        case .wide: return L("全幅の横長セル_長いラベルや_視認性を優先したいボタンに_70ed46")
        case .card: return L("サムネイル画像_タイトルを_2_列のグリッドに配置_プロンプトギャラリー向け_3fed87")
        case .grid: return L("アイコンをグリッド状に並べる_ランチャー風_列数を自由に設定可_7f1e3b")
        }
    }

    private func columnsHint(_ cols: GroupColumns) -> String {
        switch cols {
        case .auto: return L("ウィンドウ幅に応じて列数が自動で変わります_最小セル幅_120pt_a3f8b1")
        case .fixed(let n): return L_("fixed_columns_hint", n)
        }
    }

    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("選択_8ba15a")
        if panel.runModal() == .OK, let url = panel.url {
            importIconFile(from: url)
        }
    }

    /// DnD / クリックで受け取った画像をグループアイコンとして preset 配下にコピー。
    fileprivate func importIconFile(from url: URL) {
        guard let newPath = ButtonEditor.importImage(
            from: url, into: .icons,
            assetId: group.id, presetManager: presetManager
        ) else { return }
        iconPath = newPath
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
            // マクロ内の text ステップは現状 appendMode をサポートしない。
            // 必要になったら MacroStepDraft に appendMode を足して UI を増やす。
            return .text(content: text, pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
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
        case .text(let c, _, _, _):
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
                TextField(L("テキスト_fe9ebd"), text: $step.text)
                    .textFieldStyle(.roundedBorder)
            case "key":
                HStack(spacing: 4) {
                    TextField("cmd+shift+v / left / delete / f5", text: $step.keyCombo)
                        .textFieldStyle(.roundedBorder)
                    ComboKeyRecorderButton(combo: $step.keyCombo)
                    ComboSpecialKeyMenu(combo: $step.keyCombo)
                }
            case "launch":
                TextField(L("Applications_または_bundle_id_cb12d6"), text: $step.launchTarget)
                    .textFieldStyle(.roundedBorder)
            case "terminal":
                TextField(L("コマンド_4c2ea9"), text: $step.terminalCommand)
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

// MARK: - Key recorder & special key catalog

/// macOS の virtual key code → KeyCombo パーサが理解するキー名。
/// `KeyCombo.keyCodeMap` の逆引きを正規名で行う。
enum KeyNameLookup {
    static func name(forKeyCode code: UInt16) -> String? {
        switch code {
        case 0x00: return "a"; case 0x01: return "s"; case 0x02: return "d"; case 0x03: return "f"
        case 0x04: return "h"; case 0x05: return "g"; case 0x06: return "z"; case 0x07: return "x"
        case 0x08: return "c"; case 0x09: return "v"; case 0x0B: return "b"; case 0x0C: return "q"
        case 0x0D: return "w"; case 0x0E: return "e"; case 0x0F: return "r"; case 0x10: return "y"
        case 0x11: return "t"; case 0x12: return "1"; case 0x13: return "2"; case 0x14: return "3"
        case 0x15: return "4"; case 0x16: return "6"; case 0x17: return "5"; case 0x18: return "="
        case 0x19: return "9"; case 0x1A: return "7"; case 0x1B: return "-"; case 0x1C: return "8"
        case 0x1D: return "0"; case 0x1E: return "]"; case 0x1F: return "o"; case 0x20: return "u"
        case 0x21: return "["; case 0x22: return "i"; case 0x23: return "p"; case 0x25: return "l"
        case 0x26: return "j"; case 0x27: return "'"; case 0x28: return "k"; case 0x29: return ";"
        case 0x2A: return "\\"; case 0x2B: return ","; case 0x2C: return "/"; case 0x2D: return "n"
        case 0x2E: return "m"; case 0x2F: return "."; case 0x32: return "`"
        case 0x24: return "return"
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x33: return "delete"
        case 0x35: return "escape"
        case 0x75: return "forwarddelete"
        case 0x7B: return "left"; case 0x7C: return "right"
        case 0x7D: return "down"; case 0x7E: return "up"
        case 0x73: return "home"; case 0x77: return "end"
        case 0x74: return "pageup"; case 0x79: return "pagedown"
        case 0x7A: return "f1"; case 0x78: return "f2"; case 0x63: return "f3"; case 0x76: return "f4"
        case 0x60: return "f5"; case 0x61: return "f6"; case 0x62: return "f7"; case 0x64: return "f8"
        case 0x65: return "f9"; case 0x6D: return "f10"; case 0x67: return "f11"; case 0x6F: return "f12"
        case 0x69: return "f13"; case 0x6B: return "f14"; case 0x71: return "f15"; case 0x6A: return "f16"
        case 0x40: return "f17"; case 0x4F: return "f18"; case 0x50: return "f19"; case 0x5A: return "f20"
        default: return nil
        }
    }

    /// 特殊キーのドロップダウン用一覧（label = 表示名, value = KeyCombo 名）。
    /// 真実のソースは `KeyCombo.specialKeys` + `KeyCombo.functionKeys`。
    static var specialKeys: [(label: String, value: String)] {
        (KeyCombo.specialKeys + KeyCombo.functionKeys).map { ($0.label, $0.name) }
    }
}

/// クリックすると次の 1 キー入力を吸い取り、修飾キー＋ベースキーを書き戻す。
/// Esc で記録キャンセル。
struct KeyRecorderButton: View {
    @Binding var modCmd: Bool
    @Binding var modShift: Bool
    @Binding var modOption: Bool
    @Binding var modCtrl: Bool
    @Binding var baseKey: String

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                    .foregroundColor(isRecording ? .red : .accentColor)
                Text(isRecording ? L("押してください_Esc_で取消_1ccbec") : L("キーを押して記録_e8d275"))
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggle() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
            return nil // イベントを消費（Delete キー等が他フィールドに伝播しない）
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Esc 単独はキャンセル扱い（修飾なし）
        if event.keyCode == 0x35 && mods.subtracting([.capsLock]).isEmpty {
            stopRecording()
            return
        }
        guard let name = KeyNameLookup.name(forKeyCode: event.keyCode) else {
            NSSound.beep()
            return
        }
        modCmd    = mods.contains(.command)
        modShift  = mods.contains(.shift)
        modOption = mods.contains(.option)
        modCtrl   = mods.contains(.control)
        baseKey   = name
        stopRecording()
    }
}

/// 特殊キー（矢印・F1〜・Delete 等）を一覧から選んで `baseKey` に流し込むメニュー。
struct SpecialKeyMenu: View {
    @Binding var baseKey: String

    var body: some View {
        Menu {
            ForEach(KeyNameLookup.specialKeys, id: \.value) { opt in
                Button(opt.label) { baseKey = opt.value }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text(L("特殊キー_cdc3db"))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// マクロステップ用：1 個の combo 文字列バインディングに直接記録するボタン。
struct ComboKeyRecorderButton: View {
    @Binding var combo: String
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                .foregroundColor(isRecording ? .red : .accentColor)
        }
        .help(isRecording ? L("押してください_Esc_で取消_1ccbec") : L("キーを押して記録_e8d275"))
        .buttonStyle(.borderless)
        .onDisappear { stopRecording() }
    }

    private func toggle() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 0x35 && mods.subtracting([.capsLock]).isEmpty {
            stopRecording()
            return
        }
        guard let name = KeyNameLookup.name(forKeyCode: event.keyCode) else {
            NSSound.beep()
            return
        }
        var parts: [String] = []
        if mods.contains(.command)  { parts.append("cmd") }
        if mods.contains(.shift)    { parts.append("shift") }
        if mods.contains(.option)   { parts.append("option") }
        if mods.contains(.control)  { parts.append("ctrl") }
        parts.append(name)
        combo = parts.joined(separator: "+")
        stopRecording()
    }
}

/// マクロステップ用：特殊キー選択メニュー（combo 文字列を直接上書き）。
struct ComboSpecialKeyMenu: View {
    @Binding var combo: String

    var body: some View {
        Menu {
            ForEach(KeyNameLookup.specialKeys, id: \.value) { opt in
                Button(opt.label) { combo = opt.value }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .help(L("特殊キーを選択_b5bdcd"))
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
