import SwiftUI
import AppKit
import FloatingMacroCore

// MARK: - ButtonEditor

struct ButtonEditor: View {
    let button: ButtonDefinition
    @ObservedObject var presetManager: PresetManager
    let onCommit: (ButtonDefinition) -> Void
    let onDelete: () -> Void
    var parentGroupId: String? = nil
    var parentDisplayType: GroupDisplayType = .icon
    var parentIconSize: IconSize = .medium
    var parentShowLabels: Bool = true

    @State private var label: String = ""
    @State private var iconText: String = ""
    @State private var iconPath: String = ""
    @State private var showingSFSymbolPicker: Bool = false
    @State private var showingAppIconPicker: Bool = false
    @State private var iconGeneration: Int = 0
    @State private var previewLayoutOverride: GroupDisplayType? = nil
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
    @State private var cardThumbnailMode: CardThumbnailMode = .fill
    @State private var actionType: String = "text"   // Valid actions to save
    @State private var viewingType: String = "text"  // Type used for viewing segments (not used for saving)
    // Independent state for each action type — Switching types without overwriting each other
    @State private var previewDropTargeted: Bool = false
    @State private var actionText: String = ""
    /// The action's "append mode". When ON, pressing the button does not paste.
    /// Existing content is concatenated to the clipboard. Assemble prompt fragments.
    /// mode for
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

                    // Editor preview + group layout settings
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("プレビュー_21b7d4")).font(.caption).foregroundColor(.secondary)
                        HStack {
                            previewContent
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(previewDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                        .onDrop(of: [.fileURL, .image], isTargeted: $previewDropTargeted) { providers in
                            handlePreviewDrop(providers)
                        }

                        if parentGroupId != nil {
                            groupLayoutControls
                        }
                    }

                    Group {
                        labeled(L("ラベル_fddf3e")) {
                            TextField(L("表示文字列_7516d5"), text: $label)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeled(L("アイコンテキスト_絵文字など_c666a5")) {
                            TextField(L("や_など_49750c"), text: $iconText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: iconText) { newValue in
                                    if !newValue.isEmpty {
                                        iconPath = ""
                                        iconGeneration += 1
                                    }
                                }
                        }

                        HStack(spacing: 8) {
                            Button("SF Symbol...") { showingSFSymbolPicker = true }
                                .help(L("SF_Symbol_を一覧から選ぶ_ab178d"))
                            Button(L("アプリから_29035e")) { showingAppIconPicker = true }
                                .help(L("インストール済みアプリのアイコンから選ぶ_8d8c57"))
                            Button(L("画像を選択_a1c83f")) { pickIconFile() }
                            Button(L("クリア_d4b7e2")) {
                                iconPath = ""
                                iconText = ""
                                iconGeneration += 1
                            }
                                .disabled(iconPath.isEmpty && iconText.isEmpty)
                        }

                        HStack(spacing: 8) {
                            Picker("", selection: $cardThumbnailMode) {
                                Text(L("クロップ_fa6ab1")).tag(CardThumbnailMode.fill)
                                Text(L("全体表示_992e61")).tag(CardThumbnailMode.fit)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
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

                        // Pre-execution confirmation dialog. Visual input user, restart and...
                        // Shutdown-related irreversible operations with one tap
                        // Button for which you don't want to trigger.
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
            // special key segment / key recording / manual entry baseKey is
            // Confirmed as a "key action" at the moment of entry. Explicitly "enable".
            // To prevent the accident where an actionType remains as text even if a button is forgotten to be pressed.
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
        .onChange(of: iconPath) { newValue in
            if !newValue.isEmpty {
                iconText = ""
                iconGeneration += 1
            }
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
        previewLayoutOverride = parentDisplayType
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

        // When confirm is invalid, normalize related fields to default values and save.
        // At the moment when "confirmEnabled" is turned off in UI, "message" and "dangerous operation" appear.
        // Prevent from persisting so that it does not unexpectedly revive on re-ON. )
        let normalizedConfirmMessage: String? = {
            guard confirmEnabled else { return nil }
            let trimmed = confirmMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let normalizedConfirmDestructive = confirmEnabled ? confirmDestructive : false

        // Old data migration: External absolute path (e.g., user's ~/Pictures) remains
        // When saving a button, copy it under the preset folder to prevent link breakage.
        // SF Symbol / bundle id / lucide / already passed path in management directory.
        let migratedIcon = Self.migrateIfNeeded(
            path: iconPath.isEmpty ? nil : iconPath,
            into: .icons,
            assetId: button.id,
            presetManager: presetManager
        )
        // If the transition runs, reflect @State to align preview with latest path.
        if let m = migratedIcon, m != iconPath { iconPath = m }

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
            cardThumbnailMode: cardThumbnailMode,
            action: newAction
        )
        onCommit(updated)
    }

    /// Returns nothing and passes if preset name cannot be resolved when called.
    static func migrateIfNeeded(
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

    /// Select a file via NSOpenPanel drop zone fallback click.
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

    private func handlePreviewDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        importIconFile(from: url)
                    }
                }
                return true
            }
        }
        return false
    }

    /// Drag & Drop / Image selection to incorporate image as icon.
    /// Copy to `icons/<button-id>.<ext>` under preset and then set absolute path to `iconPath`.
    /// Store in the queue. If failed, notify with a toast and do not change the state.
    fileprivate func importIconFile(from url: URL) {
        guard let newPath = Self.importImage(
            from: url, into: .icons,
            assetId: button.id, presetManager: presetManager
        ) else { return }
        IconLoader.invalidate()
        iconPath = newPath
        iconText = ""
        iconGeneration += 1
    }

    /// Copy the file passed via DnD to the preset directory.
    /// Common processing. Returns nil on copy failure and notifies with an error toast.
    static func importImage(
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

    // MARK: - Group Layout Controls

    /// layout to be used in preview. If override is set, use that instead.
    /// Return the parent group's actual setting if not found.
    private var effectiveDisplayType: GroupDisplayType {
        previewLayoutOverride ?? parentDisplayType
    }

    @ViewBuilder
    private var groupLayoutControls: some View {
        HStack(spacing: 8) {
            Picker("", selection: $previewLayoutOverride) {
                Text("icon").tag(Optional<GroupDisplayType>.some(.icon))
                Text("wide").tag(Optional<GroupDisplayType>.some(.wide))
                Text("card").tag(Optional<GroupDisplayType>.some(.card))
                Text("grid").tag(Optional<GroupDisplayType>.some(.grid))
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()

            if let override = previewLayoutOverride, override != parentDisplayType {
                Button(L("グループに適用_e8b24a")) {
                    guard let gid = parentGroupId else { return }
                    _ = presetManager.updateGroup(
                        id: gid, label: nil, icon: nil, iconText: nil,
                        backgroundColor: nil, textColor: nil, tooltip: nil,
                        collapsed: nil, displayType: override, columns: nil,
                        iconSize: nil, showLabels: nil
                    )
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var previewContent: some View {
        let dt = effectiveDisplayType
        let btn = MacroButtonView(
            button: previewButton,
            onTap: {},
            displayType: dt,
            iconSize: parentIconSize,
            showLabel: parentShowLabels
        )
        .id(iconGeneration)
        switch dt {
        case .card:
            btn.frame(width: 140)
        case .grid:
            btn.frame(width: 100)
        case .icon, .wide:
            btn.fixedSize()
        }
    }

    /// Synthesize the current editor state as a ButtonDefinition (for preview before saving)
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

