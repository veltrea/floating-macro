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
        case buttons  = "編集"
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
    @State private var portText = ""
    /// ドラッグ中のドロップ先ハイライト（グループ行用）
    @State private var dropTargetGroupId: String?
    /// ドラッグ中のドロップ先ハイライト（ボタン行用）
    @State private var dropTargetButtonId: String?

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
                    ForEach(presetManager.presetEntries) { entry in
                        Text(entry.displayName).tag(entry.name)
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
                Menu {
                    Button("名前を変更…",        action: renameCurrentPreset)
                    Divider()
                    Button("エクスポート…",       action: exportCurrentPreset)
                    Button("全プリセットをエクスポート…", action: exportAllPresets)
                    Button("インポート…",         action: importPresets)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help("リネーム / エクスポート / インポート")
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

            // AI 接続 設定 (旧称: Control API)
            HStack {
                Text("AI 接続").font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Toggle("オン", isOn: Binding(
                get: { presetManager.appConfig?.controlAPI.enabled ?? false },
                set: { presetManager.setControlAPIEnabled($0) }
            ))
            .help("オンにすると AI や外部ツールがこのアプリを操作できます (HTTP API をポートで公開)。")
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
                Button(action: addGroup) {
                    Label("グループ追加", systemImage: "plus.circle")
                }
                Button(action: addEmptyButton) {
                    Label("ボタン追加", systemImage: "plus.circle")
                }
                .disabled(selectedGroupId == nil)
            }
        }
        .padding(8)
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
                        Label("複製", systemImage: "plus.square.on.square")
                    }
                }

                Button {
                    renameGroup(group)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("グループ名を変更")

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
                        Label("複製", systemImage: "plus.square.on.square")
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
        alert.messageText = "新しいプリセット"
        alert.informativeText = "プリセット名を入力してください（自由入力・あとから変更可）"
        alert.addButton(withTitle: "作成")
        alert.addButton(withTitle: "キャンセル")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = "例: MidJourney 用"
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
        alert.messageText = "プリセット名を変更"
        alert.informativeText = "新しい表示名を入力してください"
        alert.addButton(withTitle: "変更")
        alert.addButton(withTitle: "キャンセル")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = preset.displayName
        textField.placeholderString = "表示名"
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
        panel.title = "プリセットをエクスポート"
        panel.nameFieldStringValue = "\(preset.displayName).fmpreset.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { presetManager.showTransientError("エクスポート失敗: \(error.localizedDescription)") }
    }

    private func exportAllPresets() {
        guard let data = presetManager.exportAllPresetsData() else { return }
        let panel = NSSavePanel()
        panel.title = "全プリセットをエクスポート"
        panel.nameFieldStringValue = "presets.fmpreset-bundle.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { presetManager.showTransientError("エクスポート失敗: \(error.localizedDescription)") }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.title = "プリセットをインポート"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return }
        var total = 0
        for url in panel.urls {
            total += presetManager.importPresets(from: url)
        }
        if total == 0 {
            presetManager.showTransientError("インポートに失敗しました")
        }
    }

    private func addGroup() {
        let id = "g-\(Int.random(in: 1000...9999))"
        let group = ButtonGroup(id: id, label: "新グループ", buttons: [])
        _ = presetManager.addGroup(group)
        selectedGroupId = id
        selectedButtonId = nil
    }

    private func renameGroup(_ group: ButtonGroup) {
        let alert = NSAlert()
        alert.messageText = "グループ名を変更"
        alert.informativeText = "新しい名前を入力してください"
        alert.addButton(withTitle: "変更")
        alert.addButton(withTitle: "キャンセル")

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
            id: id, label: "新ボタン",
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true)
        )
        _ = presetManager.addButton(button, toGroupId: groupId)
        selectedButtonId = id
    }
}
