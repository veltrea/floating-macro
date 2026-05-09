import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

/// 行ベースの DnD 用デリゲート。
/// テキスト UTType でドラッグペイロードを受け取り、ハイライト管理と onDrop を行う。
struct RowDropDelegate: DropDelegate {
    let destGroupId: String
    let beforeButtonId: String?
    let isGroupTarget: Bool
    @Binding var dropTargetGroupId: String?
    @Binding var dropTargetButtonId: String?
    let onDrop: (String) -> Bool

    func dropEntered(info: DropInfo) {
        if isGroupTarget {
            dropTargetGroupId = destGroupId
        } else {
            dropTargetButtonId = beforeButtonId
        }
    }

    func dropExited(info: DropInfo) {
        if isGroupTarget, dropTargetGroupId == destGroupId {
            dropTargetGroupId = nil
        }
        if !isGroupTarget, dropTargetButtonId == beforeButtonId {
            dropTargetButtonId = nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text.identifier])
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetGroupId = nil
        dropTargetButtonId = nil
        guard let item = info.itemProviders(for: [UTType.text.identifier]).first else {
            return false
        }
        // ペイロード読み出しは非同期。メインスレッドをブロックしないこと。
        // 同期 wait + main.sync の組み合わせは確実にデッドロックする。
        let onDrop = self.onDrop
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            let payload: String?
            if let str = data as? String {
                payload = str
            } else if let d = data as? Data, let s = String(data: d, encoding: .utf8) {
                payload = s
            } else {
                payload = nil
            }
            guard let payload else { return }
            DispatchQueue.main.async { _ = onDrop(payload) }
        }
        return true
    }
}

/// Root view of the Settings window. Left column: preset selector + group
/// browser. Right column: detail form for the selected button.
struct SettingsView: View {
    @ObservedObject var presetManager: PresetManager
    @State private var selectedButtonId: String?
    @State private var selectedGroupId: String?
    @State private var activeTab: SettingsTab = .buttons

    enum SettingsTab: String, Hashable {
        case buttons  = "buttons"
        case panels   = "panels"
        case security = "security"

        var localizedLabel: String {
            switch self {
            case .buttons:  return L("編集_757886")
            case .panels:   return L("パネル_17f050")
            case .security: return L("セキュリティ_1c7258")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // タブバー
            HStack(spacing: 0) {
                ForEach([SettingsTab.buttons, .panels, .security], id: \.self) { tab in
                    Button(action: { activeTab = tab }) {
                        Text(tab.localizedLabel)
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

            case .panels:
                PanelsSettingsView(presetManager: presetManager)

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
                    Text(L("コマンドセーフガード_c5f232"))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(L("登録したパターンを含むコマンド_テキストをターミナルに送る前に確認ダイアログを表示します_大文字_小_858217"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 有効/無効トグル
                Toggle(L("確認ダイアログを有効にする_27222d"), isOn: $enabled)
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
                        Text(L("オートパイロットモード_03f795"))
                            .font(.headline)
                        if autopilotEnabled {
                            Text(L("有効_ce1518"))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    Text(L("有効にすると_パターンに一致するコマンドでも確認ダイアログなしで実行されます_AIに完全に操作を委ね_c01c70"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !hasPassword {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.slash")
                                .foregroundColor(.secondary)
                            Text(L("パスワードが未設定です_先にパスワードを設定してください_7fe6ab"))
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        Button(L("パスワードを設定する_e91363")) {
                            newPassword1 = ""; newPassword2 = ""; passwordError = ""
                            showingSetPasswordSheet = true
                        }
                    } else {
                        HStack(spacing: 12) {
                            if autopilotEnabled {
                                Button(L("オートパイロットを無効にする_fa7832")) {
                                    presetManager.disableAutopilot()
                                    autopilotEnabled = false
                                }
                                .foregroundColor(.orange)
                            } else {
                                Button(L("オートパイロットを有効にする_69de91")) {
                                    enableAutopilotWithPrompt()
                                }
                            }
                            Button(L("パスワードを変更する_ba5901")) {
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
                        Text(L("確認対象パターン一覧_e4b5f1"))
                            .font(.headline)

                        if patterns.isEmpty {
                            Text(L("パターンが登録されていません_f9f240"))
                                .foregroundColor(.secondary)
                                .font(.callout)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(patterns.indices, id: \.self) { i in
                                    HStack(spacing: 8) {
                                        if editingIndex == i {
                                            TextField(L("パターン_1f6ae2"), text: $editingText)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12, design: .monospaced))
                                            Button(L("確定_ba0fcf")) {
                                                let trimmed = editingText.trimmingCharacters(in: .whitespaces)
                                                if !trimmed.isEmpty {
                                                    patterns[i] = trimmed
                                                    savePatterns()
                                                }
                                                editingIndex = nil
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            Button(L("キャンセル_6ef349")) { editingIndex = nil }
                                                .controlSize(.small)
                                        } else {
                                            Text(patterns[i])
                                                .font(.system(size: 12, design: .monospaced))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Button(L("編集_757886")) {
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
                        Text(L("パターンを追加_bf7d0b"))
                            .font(.headline)
                        HStack {
                            TextField(L("例_rm_rf_ee43ae"), text: $newPattern)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onSubmit { addPattern() }
                            Button(L("追加_7dc3a5"), action: addPattern)
                                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    HStack {
                        Button(L("デフォルトパターンに戻す_516a9f")) {
                            patterns = CommandBlacklist.defaultPatterns
                            savePatterns()
                        }
                        .foregroundColor(.orange)
                        Spacer()
                        Text(L_("patterns_registered_count", patterns.count))
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
                Text(hasPassword ? L("パスワードを変更_fb3e11") : L("オートパイロット用パスワードを設定_55fc32"))
                    .font(.headline)

                if hasPassword {
                    SecureField(L("現在のパスワード_ada493"), text: $newPassword1)
                        .textFieldStyle(.roundedBorder)
                    SecureField(L("新しいパスワード_291f74"), text: $newPassword2)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField(L("パスワード_4bdfe7"), text: $newPassword1)
                        .textFieldStyle(.roundedBorder)
                    SecureField(L("確認のためもう一度_6bd0d5"), text: $newPassword2)
                        .textFieldStyle(.roundedBorder)
                }

                if !passwordError.isEmpty {
                    Text(passwordError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button(L("キャンセル_6ef349")) {
                        showingSetPasswordSheet = false
                    }
                    Spacer()
                    Button(hasPassword ? L("変更する_0f1a79") : L("設定する_a160b0")) {
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
            title: L("オートパイロットを有効にする_3d57fc"),
            message: L("パスワードを入力してください_n有効にすると確認ダイアログなしにすべてのコマンドが実行されます_927a3e")
        ) else { return }
        if presetManager.enableAutopilot(passphrase: passphrase) {
            autopilotEnabled = true
        } else {
            let alert = NSAlert()
            alert.messageText = L("パスワードが違います_e629b7")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func commitPassword() {
        if hasPassword {
            // 変更: newPassword1 = 現在、newPassword2 = 新しい
            if newPassword2.count < 4 {
                passwordError = L("4文字以上のパスワードを設定してください_85efe5")
                return
            }
            if presetManager.setAutopilotPassword(oldPassphrase: newPassword1, newPassphrase: newPassword2) {
                hasPassword = true
                showingSetPasswordSheet = false
            } else {
                passwordError = L("現在のパスワードが違います_2309b8")
            }
        } else {
            // 新規設定: newPassword1 = password、newPassword2 = confirm
            guard newPassword1 == newPassword2 else {
                passwordError = L("パスワードが一致しません_0fa3b3")
                return
            }
            if newPassword1.count < 4 {
                passwordError = L("4文字以上のパスワードを設定してください_85efe5")
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
    @State private var portText = ""
    /// ドラッグ中のドロップ先ハイライト（グループ行用）
    @State private var dropTargetGroupId: String?
    /// ドラッグ中のドロップ先ハイライト（ボタン行用）
    @State private var dropTargetButtonId: String?
    /// プリセット並べ替えシートの表示フラグ
    @State private var showingPresetReorderSheet: Bool = false
    /// 「アプリから追加…」ピッカーシートの表示フラグ
    @State private var showingAppPickerSheet: Bool = false
    /// プリセットメモ編集用のローカル State。プリセット切替時に
    /// `currentPreset.memo` から読み戻し、変更時に PresetManager 経由で保存。
    @State private var memoText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preset picker
            HStack {
                Text(L("プリセット_96104a")).font(.caption).foregroundColor(.secondary)
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
                .help(L("新しいプリセット_7fefc6"))
                Button(action: deleteCurrentPreset) {
                    Image(systemName: "minus")
                }
                .disabled(presetManager.currentPreset?.name == "default")
                .help(L("現在のプリセットを削除_49de83"))
                Menu {
                    Button(L("名前を変更_1d1fd5"),        action: renameCurrentPreset)
                    Button(L("並べ替え_403f82"),          action: { showingPresetReorderSheet = true })
                    Divider()
                    Button(L("エクスポート_4dc7ff"),       action: exportCurrentPreset)
                    Button(L("全プリセットをエクスポート_9aa6b3"), action: exportAllPresets)
                    Button(L("インポート_c8bcdd"),         action: importPresets)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help(L("リネーム_並べ替え_エクスポート_インポート_174c89"))
            }

            // プリセットメモ
            HStack {
                Text(L("メモ_9490ad")).font(.caption).foregroundColor(.secondary)
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
                .help(L("このプリセットを使う前提条件_注意点を書いておくと_パネル上部のメモアイコンから参照できます_9337d8"))
            Text(L("使う前提_OS_設定_前面アプリ_クリップボード上書き等_を書いておくと_時間を空けて使い直す時にす_a3f291"))
                .font(.caption2)
                .foregroundColor(.secondary)

            // AI モード picker
            HStack {
                Text(L("AI_モード_fec4eb")).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Picker("", selection: Binding(
                get: { presetManager.appConfig?.controlAPI.agentMode ?? .normal },
                set: { presetManager.setAgentMode($0) }
            )) {
                Text(L("ノーマル_b7519e")).tag(AgentMode.normal)
                Text(L("テスト_自律_1f6a94")).tag(AgentMode.test)
                Text("Claude Code").tag(AgentMode.claudeCode)
            }
            .labelsHidden()
            .help(L("GET_manifest_で返すシステムプロンプトを切り替えます_767f36"))

            // AI 接続 設定 (旧称: Control API)
            HStack {
                Text(L("AI_接続_3d125f")).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Toggle(L("オン_22464d"), isOn: Binding(
                get: { presetManager.appConfig?.controlAPI.enabled ?? false },
                set: { presetManager.setControlAPIEnabled($0) }
            ))
            .help(L("オンにすると_AI_や外部ツールがこのアプリを操作できます_HTTP_API_をポートで公開_fe4270"))
            HStack(spacing: 4) {
                Text(L("ポート_4c1f86")).font(.caption).foregroundColor(.secondary)
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
            Text(L("変更後はアプリの再起動が必要です_0b37da"))
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
                Button(action: addGroup) {
                    Label(L("グループ追加_49d331"), systemImage: "plus.circle")
                }
                Button(action: addEmptyButton) {
                    Label(L("ボタン追加_ae8c89"), systemImage: "plus.circle")
                }
                .disabled(selectedGroupId == nil)
                Button(action: { showingAppPickerSheet = true }) {
                    Label(L("アプリから追加_d9418a"), systemImage: "app.badge")
                }
                .disabled(selectedGroupId == nil)
                .help(L("インストール済みアプリの一覧から起動ボタンを作成_f24f8d"))
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

    /// プリセット切替時に編集中の memoText を currentPreset から読み戻す。
    /// 同じプリセットの再描画では `memoText` が既に最新のはずなので何もしない。
    private func syncMemoFromCurrentPreset() {
        let next = presetManager.currentPreset?.memo ?? ""
        if memoText != next { memoText = next }
    }

    /// 編集中のメモを保存する。空文字列は nil に正規化されるため、
    /// 読み戻し時の "" との往復で保存ループにならない。
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
                        Label(L("複製_1fde1c"), systemImage: "plus.square.on.square")
                    }
                }

                Button {
                    renameGroup(group)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help(L("グループ名を変更_f69757"))

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
                .help(L("グループ削除_7d09ee"))
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
                        Label(L("複製_1fde1c"), systemImage: "plus.square.on.square")
                    }
                }
            }
        }
    }

    /// ドラッグ&ドロップのコア処理。
    /// - payload: `"g:<id>"` でグループ、`"b:<id>"` でボタン
    /// - ontoGroupId: ドロップ先グループ
    /// - beforeButtonId: 指定があればそのボタンの直前に挿入。nil ならグループ末尾。
    private func handleDrop(payload: String,
                            ontoGroupId destGroupId: String,
                            beforeButtonId: String?) -> Bool {
        guard let preset = presetManager.currentPreset else { return false }

        if payload.hasPrefix("b:") {
            let srcButtonId = String(payload.dropFirst(2))
            guard !srcButtonId.isEmpty else { return false }
            // 同じボタンに drop しても何もしない
            if let bid = beforeButtonId, bid == srcButtonId { return false }

            // 同一グループ内の並べ替えなら reorderButtons を、グループ跨ぎなら moveButton を使う
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
                // グループ跨ぎ: 行先グループ内での挿入位置を決める
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
            // グループは「ドロップ先グループの直前」に挿入
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
        alert.messageText = L("新しいプリセット_7fefc6")
        alert.informativeText = L("プリセット名を入力してください_自由入力_あとから変更可_984cd1")
        alert.addButton(withTitle: L("作成_4f8c0a"))
        alert.addButton(withTitle: L("キャンセル_6ef349"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = L("例_MidJourney_用_b050a8")
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
        alert.messageText = L("プリセット名を変更_2d5bf7")
        alert.informativeText = L("新しい表示名を入力してください_c5f18e")
        alert.addButton(withTitle: L("変更_fbcc6e"))
        alert.addButton(withTitle: L("キャンセル_6ef349"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = preset.displayName
        textField.placeholderString = L("表示名_ea5693")
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
        panel.title = L("プリセットをエクスポート_d51675")
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
        panel.title = L("全プリセットをエクスポート_dd2086")
        panel.nameFieldStringValue = "presets.fmpreset-bundle.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { presetManager.showTransientError(L_("export_failed", error.localizedDescription)) }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.title = L("プリセットをインポート_0e2962")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return }
        var total = 0
        for url in panel.urls {
            total += presetManager.importPresets(from: url)
        }
        if total == 0 {
            presetManager.showTransientError(L("インポートに失敗しました_0ca2b5"))
        }
    }

    private func addGroup() {
        let id = "g-\(Int.random(in: 1000...9999))"
        let group = ButtonGroup(id: id, label: L("新グループ_050f97"), buttons: [])
        _ = presetManager.addGroup(group)
        selectedGroupId = id
        selectedButtonId = nil
    }

    private func renameGroup(_ group: ButtonGroup) {
        let alert = NSAlert()
        alert.messageText = L("グループ名を変更_f69757")
        alert.informativeText = L("新しい名前を入力してください_4d4602")
        alert.addButton(withTitle: L("変更_fbcc6e"))
        alert.addButton(withTitle: L("キャンセル_6ef349"))

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
            id: id, label: L("新ボタン_d6206a"),
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
        )
        _ = presetManager.addButton(button, toGroupId: groupId)
        selectedButtonId = id
    }
}

// MARK: - Preset reorder sheet

/// プリセット表示順を DnD で並べ替えるシート。確定するまでメモリ上で
/// 編集し、「保存」で `presetManager.reorderPresets` を呼んで永続化する。
struct PresetReorderSheet: View {
    @ObservedObject var presetManager: PresetManager
    @Binding var isPresented: Bool

    @State private var workingOrder: [PresetEntry] = []
    @State private var dragSourceId: String?
    @State private var dropTargetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("プリセットの並べ替え_56a714"))
                .font(.headline)
            Text(L("行をドラッグして順序を変更し_保存_を押してください_e37583"))
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(workingOrder) { entry in
                        presetRow(entry)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 240, maxHeight: 480)
            .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            .cornerRadius(6)

            HStack {
                Button(L("キャンセル_6ef349")) {
                    isPresented = false
                }
                Spacer()
                Button(L("アルファベット順にリセット_eff49f")) {
                    workingOrder = presetManager.presetEntries.sorted { $0.name < $1.name }
                }
                Button(L("保存_be5fbb")) {
                    let ids = workingOrder.map { $0.name }
                    _ = presetManager.reorderPresets(ids: ids)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            workingOrder = presetManager.presetEntries
        }
    }

    private func presetRow(_ entry: PresetEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
            Text(entry.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(entry.name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(dropTargetId == entry.id
                      ? Color.accentColor.opacity(0.18)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(dragSourceId == entry.id
                        ? Color.accentColor.opacity(0.6)
                        : Color.clear,
                        lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onDrag {
            dragSourceId = entry.id
            return NSItemProvider(object: "p:\(entry.id)" as NSString)
        }
        .onDrop(of: [.text],
                delegate: PresetRowDropDelegate(
                    destId: entry.id,
                    workingOrder: $workingOrder,
                    dragSourceId: $dragSourceId,
                    dropTargetId: $dropTargetId
                ))
    }
}

/// プリセット並べ替えシート用の DropDelegate。テキストペイロード
/// `p:<id>` を読み取り、ソース行をドロップ先の直前に挿入する。
private struct PresetRowDropDelegate: DropDelegate {
    let destId: String
    @Binding var workingOrder: [PresetEntry]
    @Binding var dragSourceId: String?
    @Binding var dropTargetId: String?

    func dropEntered(info: DropInfo) {
        dropTargetId = destId
    }

    func dropExited(info: DropInfo) {
        if dropTargetId == destId { dropTargetId = nil }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text.identifier])
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetId = nil
        defer { dragSourceId = nil }
        guard let item = info.itemProviders(for: [UTType.text.identifier]).first else {
            return false
        }
        let dest = destId
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            let payload: String?
            if let s = data as? String { payload = s }
            else if let d = data as? Data, let s = String(data: d, encoding: .utf8) { payload = s }
            else { payload = nil }
            guard let payload, payload.hasPrefix("p:") else { return }
            let srcId = String(payload.dropFirst(2))
            DispatchQueue.main.async {
                guard srcId != dest,
                      let srcIdx = workingOrder.firstIndex(where: { $0.id == srcId }),
                      let dstIdx = workingOrder.firstIndex(where: { $0.id == dest })
                else { return }
                let item = workingOrder.remove(at: srcIdx)
                let insertAt = srcIdx < dstIdx ? dstIdx - 1 : dstIdx
                workingOrder.insert(item, at: insertAt)
            }
        }
        return true
    }
}
