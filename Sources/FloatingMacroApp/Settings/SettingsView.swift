import SwiftUI
import AppKit
import FloatingMacroCore

/// Root view of the Settings window. Left column: preset selector + group
/// browser. Right column: detail form for the selected button.
struct SettingsView: View {
    @ObservedObject var presetManager: PresetManager
    @State private var selectedButtonId: String?
    @State private var selectedGroupId: String?
    @State private var activeTab: SettingsTab = .buttons

    enum SettingsTab: String, Hashable {
        case buttons  = "ボタン編集"
        case security = "セキュリティ"
    }

    var body: some View {
        VStack(spacing: 0) {
            // タブバー
            HStack(spacing: 0) {
                ForEach([SettingsTab.buttons, .security], id: \.self) { tab in
                    Button(action: { activeTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 13))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(activeTab == tab
                                ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
                                : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(activeTab == tab ? .primary : .secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // タブコンテンツ
            switch activeTab {
            case .buttons:
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

            case .security:
                SecuritySettingsView(presetManager: presetManager)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { selectFirstButtonIfNeeded() }
        .onChange(of: presetManager.externalSelectButtonRequest) { requestedId in
            guard let id = requestedId else { return }
            activeTab = .buttons
            applyExternalSelection(id)
            // Consume the request so the same id can be requested twice.
            presetManager.externalSelectButtonRequest = nil
        }
        .onChange(of: presetManager.externalSelectGroupRequest) { requestedId in
            guard let id = requestedId else { return }
            activeTab = .buttons
            selectedGroupId = id
            selectedButtonId = nil
            presetManager.externalSelectGroupRequest = nil
        }
        .onChange(of: presetManager.clearSelectionNonce) { _ in
            selectedButtonId = nil
            selectedGroupId = nil
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

// MARK: - SecuritySettingsView

/// コマンドブラックリストとオートパイロット設定の編集画面。
struct SecuritySettingsView: View {
    @ObservedObject var presetManager: PresetManager

    // ローカル編集用の状態
    @State private var enabled: Bool = true
    @State private var autopilotEnabled: Bool = false
    @State private var hasPassword: Bool = false
    @State private var patterns: [String] = []
    @State private var newPattern: String = ""
    @State private var editingIndex: Int? = nil
    @State private var editingText: String = ""

    // パスワード設定シート
    @State private var showingSetPasswordSheet: Bool = false
    @State private var newPassword1: String = ""
    @State private var newPassword2: String = ""
    @State private var passwordError: String = ""

    private var blacklist: CommandBlacklist {
        presetManager.appConfig?.commandBlacklist ?? CommandBlacklist()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ヘッダー説明
                VStack(alignment: .leading, spacing: 6) {
                    Text("コマンドセーフガード")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("登録したパターンを含むコマンド・テキストをターミナルに送る前に確認ダイアログを表示します。大文字・小文字を区別せず部分一致で判定します。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 有効/無効トグル
                Toggle("確認ダイアログを有効にする", isOn: $enabled)
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { newValue in
                        presetManager.setCommandBlacklistEnabled(newValue)
                    }

                Divider()

                // ─── オートパイロットセクション ───────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .foregroundColor(autopilotEnabled ? .orange : .secondary)
                        Text("オートパイロットモード")
                            .font(.headline)
                        if autopilotEnabled {
                            Text("有効")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    Text("有効にすると、パターンに一致するコマンドでも確認ダイアログなしで実行されます。AIに完全に操作を委ねたいときに使います。\n有効化にはパスワードが必要です。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !hasPassword {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.slash")
                                .foregroundColor(.secondary)
                            Text("パスワードが未設定です。先にパスワードを設定してください。")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        Button("パスワードを設定する…") {
                            newPassword1 = ""; newPassword2 = ""; passwordError = ""
                            showingSetPasswordSheet = true
                        }
                    } else {
                        HStack(spacing: 12) {
                            if autopilotEnabled {
                                Button("オートパイロットを無効にする") {
                                    presetManager.disableAutopilot()
                                    autopilotEnabled = false
                                }
                                .foregroundColor(.orange)
                            } else {
                                Button("オートパイロットを有効にする…") {
                                    enableAutopilotWithPrompt()
                                }
                            }
                            Button("パスワードを変更する…") {
                                newPassword1 = ""; newPassword2 = ""; passwordError = ""
                                showingSetPasswordSheet = true
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(autopilotEnabled ? Color.orange.opacity(0.5) : Color.gray.opacity(0.2))
                )

                if enabled {
                    Divider()

                    // パターン一覧
                    VStack(alignment: .leading, spacing: 8) {
                        Text("確認対象パターン一覧")
                            .font(.headline)

                        if patterns.isEmpty {
                            Text("パターンが登録されていません。")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(patterns.indices, id: \.self) { i in
                                    HStack(spacing: 8) {
                                        if editingIndex == i {
                                            TextField("パターン", text: $editingText)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12, design: .monospaced))
                                            Button("確定") {
                                                let trimmed = editingText.trimmingCharacters(in: .whitespaces)
                                                if !trimmed.isEmpty {
                                                    patterns[i] = trimmed
                                                    savePatterns()
                                                }
                                                editingIndex = nil
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            Button("キャンセル") { editingIndex = nil }
                                                .controlSize(.small)
                                        } else {
                                            Text(patterns[i])
                                                .font(.system(size: 12, design: .monospaced))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Button("編集") {
                                                editingIndex = i
                                                editingText = patterns[i]
                                            }
                                            .controlSize(.small)
                                            Button(role: .destructive) {
                                                patterns.remove(at: i)
                                                savePatterns()
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .background(i % 2 == 0
                                        ? Color(NSColor.controlBackgroundColor)
                                        : Color.clear)
                                }
                            }
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                        }
                    }

                    // 新規パターン追加
                    VStack(alignment: .leading, spacing: 6) {
                        Text("パターンを追加")
                            .font(.headline)
                        HStack {
                            TextField("例: rm -rf", text: $newPattern)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onSubmit { addPattern() }
                            Button("追加", action: addPattern)
                                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    HStack {
                        Button("デフォルトパターンに戻す") {
                            patterns = CommandBlacklist.defaultPatterns
                            savePatterns()
                        }
                        .foregroundColor(.orange)
                        Spacer()
                        Text("\(patterns.count) 件登録済み")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { loadFromConfig() }
        .onChange(of: presetManager.appConfig?.commandBlacklist) { _ in
            loadFromConfig()
        }
        // ─── パスワード設定シート ─────────────────────────────────
        .sheet(isPresented: $showingSetPasswordSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(hasPassword ? "パスワードを変更" : "オートパイロット用パスワードを設定")
                    .font(.headline)

                if hasPassword {
                    SecureField("現在のパスワード", text: $newPassword1)
                        .textFieldStyle(.roundedBorder)
                    SecureField("新しいパスワード", text: $newPassword2)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("パスワード", text: $newPassword1)
                        .textFieldStyle(.roundedBorder)
                    SecureField("確認のためもう一度", text: $newPassword2)
                        .textFieldStyle(.roundedBorder)
                }

                if !passwordError.isEmpty {
                    Text(passwordError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button("キャンセル") {
                        showingSetPasswordSheet = false
                    }
                    Spacer()
                    Button(hasPassword ? "変更する" : "設定する") {
                        commitPassword()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPassword1.isEmpty || newPassword2.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
    }

    // MARK: - Helpers

    private func loadFromConfig() {
        let bl = blacklist
        enabled         = bl.enabled
        autopilotEnabled = bl.autopilotEnabled
        hasPassword     = bl.autopilotPasswordHash != nil
        patterns        = bl.patterns
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !patterns.contains(trimmed) else { return }
        patterns.append(trimmed)
        newPattern = ""
        savePatterns()
    }

    private func savePatterns() {
        presetManager.setCommandBlacklistPatterns(patterns)
    }

    private func enableAutopilotWithPrompt() {
        guard let passphrase = CommandConfirmation.promptPassphrase(
            title: "オートパイロットを有効にする",
            message: "パスワードを入力してください。\n有効にすると確認ダイアログなしにすべてのコマンドが実行されます。"
        ) else { return }
        if presetManager.enableAutopilot(passphrase: passphrase) {
            autopilotEnabled = true
        } else {
            let alert = NSAlert()
            alert.messageText = "パスワードが違います"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func commitPassword() {
        if hasPassword {
            // 変更: newPassword1 = 現在、newPassword2 = 新しい
            if newPassword2.count < 4 {
                passwordError = "4文字以上のパスワードを設定してください。"
                return
            }
            if presetManager.setAutopilotPassword(oldPassphrase: newPassword1, newPassphrase: newPassword2) {
                hasPassword = true
                showingSetPasswordSheet = false
            } else {
                passwordError = "現在のパスワードが違います。"
            }
        } else {
            // 新規設定: newPassword1 = password、newPassword2 = confirm
            guard newPassword1 == newPassword2 else {
                passwordError = "パスワードが一致しません。"
                return
            }
            if newPassword1.count < 4 {
                passwordError = "4文字以上のパスワードを設定してください。"
                return
            }
            if presetManager.setAutopilotPassword(oldPassphrase: nil, newPassphrase: newPassword1) {
                hasPassword = true
                showingSetPasswordSheet = false
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
    @State private var portText = ""

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

            // AI モード picker
            HStack {
                Text("AI モード").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Picker("", selection: Binding(
                get: { presetManager.appConfig?.controlAPI.agentMode ?? .normal },
                set: { presetManager.setAgentMode($0) }
            )) {
                Text("ノーマル").tag(AgentMode.normal)
                Text("テスト（自律）").tag(AgentMode.test)
                Text("Claude Code").tag(AgentMode.claudeCode)
            }
            .labelsHidden()
            .help("GET /manifest で返すシステムプロンプトを切り替えます")

            // Control API 設定
            HStack {
                Text("Control API").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Toggle("有効", isOn: Binding(
                get: { presetManager.appConfig?.controlAPI.enabled ?? false },
                set: { presetManager.setControlAPIEnabled($0) }
            ))
            .help("有効にするとポートで HTTP API が起動します。変更後は再起動が必要です。")
            HStack(spacing: 4) {
                Text("ポート").font(.caption).foregroundColor(.secondary)
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
            Text("変更後はアプリの再起動が必要です。")
                .font(.caption2)
                .foregroundColor(.secondary)

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
                            .fill(selectedGroupId == group.id && selectedButtonId == nil
                                  ? Color.accentColor.opacity(0.2) : Color.clear)
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

    private func commitPort() {
        guard let port = Int(portText) else {
            // 無効な値はリセット
            portText = String(presetManager.appConfig?.controlAPI.port ?? 17430)
            return
        }
        presetManager.setControlAPIPort(port)
        // setControlAPIPort 内でクランプされた値に合わせて表示を更新
        portText = String(presetManager.appConfig?.controlAPI.port ?? port)
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
