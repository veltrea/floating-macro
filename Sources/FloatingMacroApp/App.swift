import SwiftUI
import AppKit
import Combine
import FloatingMacroCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var miniIcon: MiniIconPanel?
    private var statusItem: NSStatusItem?
    private let presetManager = PresetManager()
    private var controlServer: ControlServer?
    private var controlHandlers: ControlHandlers?
    private var collapseObserver: NSObjectProtocol?
    private var controlAPICancellable: AnyCancellable?
    private var presetEntriesCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンを非表示
        NSApp.setActivationPolicy(.accessory)

        // ロギング: 他のすべてより先に設定する
        configureLogging()

        // バイナリ ID チェック - リビルド/アップデートで hash が変わって
        // いた場合は TCC エントリを自動 reset する。これは
        // AccessibilityChecker.isTrusted を呼ぶより**前に**走らせる必要が
        // ある (probe をキャッシュさせないため、また reset の効果を初回
        // probe で見るため)。
        let bundleId = Bundle.main.bundleIdentifier ?? "com.veltrea.FloatingMacro"
        BinaryIdentity.handleStartupCheck(bundleId: bundleId)

        // 権限チェック
        if !AccessibilityChecker.isTrusted(prompt: false) {
            showAccessibilityAlert()
        }

        // 設定読み込み
        presetManager.loadInitialConfig()

        // フローティングパネル作成
        setupPanel()

        // パネル折りたたみ通知を監視
        collapseObserver = NotificationCenter.default.addObserver(
            forName: .floatingPanelWantsCollapse,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.collapseToMiniIcon()
        }

        // .accessory アプリはメニューバーを持たないが、⌘A / ⌘Z 等の
        // テキスト編集ショートカットはシステムが mainMenu のキー等価を
        // 参照してディスパッチする。Edit メニューを設定しておかないと
        // Settings ウィンドウの TextField で ⌘A が効かなくなる。
        setupEditMenu()

        // メニューバー常駐
        setupStatusItem()

        // 制御 API (設定で有効になっていれば、バックグラウンドで起動)
        //
        // CLAUDE.md のメモリ「MCP サーバーは別スレッドで 1〜2秒以内に起動」方針に
        // 従い、メインスレッドでの初期化コストを ControlServer 側で抑え、
        // 失敗してもアプリ本体は通常起動する。
        if presetManager.appConfig?.controlAPI.enabled ?? false {
            startControlServer()
        }

        // Settings 画面での enabled/port 変更をリアルタイムに反映する。
        // dropFirst() で起動時の初期値を読み飛ばし、変化があったときだけ再起動する。
        controlAPICancellable = presetManager.$appConfig
            .compactMap { $0?.controlAPI }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                self?.restartControlServer(config: newConfig)
            }

        // プリセット一覧が変わったらメニューバーを再構築する。
        // SwiftUI の Picker は @Published で自動再描画されるが、AppKit の
        // NSMenu は明示的に作り直す必要がある。
        presetEntriesCancellable = presetManager.$presetEntries
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupStatusItem()
            }
    }

    /// .accessory アプリでもテキストフィールドの ⌘A / ⌘Z 等が機能するよう、
    /// Edit メニューを NSApp.mainMenu に登録する。
    /// メニューバー自体は表示されないが、キー等価のディスパッチには使われる。
    private func setupEditMenu() {
        let mainMenu = NSMenu()

        // アプリメニュー（空のプレースホルダー。macOS は先頭項目をアプリ名として扱う）
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        appItem.submenu = NSMenu()

        // Edit メニュー
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo",      action: #selector(UndoManager.undo),    keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo",      action: #selector(UndoManager.redo),    keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",       action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",      action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",     action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private func configureLogging() {
        let logsDir = ConfigLoader.defaultBaseURL.appendingPathComponent("logs")
        let logURL = logsDir.appendingPathComponent("floatingmacro.log")
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let file = try FileLogWriter(url: logURL, minimumLevel: .info)
            LoggerContext.shared = file
        } catch {
            // ログが開けなくても起動は継続する
            NSLog("FloatingMacro: log init failed: \(error)")
        }
    }

    private func restartControlServer(config: ControlAPIConfig) {
        controlServer?.stop()
        controlServer = nil
        controlHandlers = nil
        guard config.enabled else { return }
        startControlServer()
    }

    private func startControlServer() {
        guard let cfg = presetManager.appConfig else { return }
        let logURL = ConfigLoader.defaultBaseURL
            .appendingPathComponent("logs/floatingmacro.log")
        let handlers = ControlHandlers(
            presetManager: presetManager,
            panel: panel,
            logURL: logURL
        )
        self.controlHandlers = handlers

        // requireAuth かつ testMode でないときだけ Keychain からトークンを取得する。
        // Keychain 読み取り失敗時はログに残してトークンなし（認証スキップ）で起動する。
        let apiCfg = cfg.controlAPI
        let token: String?
        if apiCfg.requireAuth && !apiCfg.testMode {
            do {
                token = try TokenStore.loadOrCreate()
            } catch {
                LoggerContext.shared.error("ControlServer",
                                           "Keychain access failed; starting without auth",
                                           ["error": String(describing: error)])
                token = nil
            }
        } else {
            token = nil
        }

        let server = ControlServer(
            preferredPort: UInt16(clamping: apiCfg.port),
            maxPortProbes: 10,
            handler: wrapWithAuth(token: token, handler: handlers.makeHandler())
        )
        self.controlServer = server

        // 別スレッドで起動 (メインスレッドをブロックしない)
        DispatchQueue.global(qos: .userInitiated).async {
            switch server.start(timeout: 2.0) {
            case .success(let port):
                LoggerContext.shared.info("ControlServer",
                                          "Started on 127.0.0.1:\(port)")
            case .failure(let err):
                LoggerContext.shared.error("ControlServer",
                                           "Failed to start",
                                           ["error": String(describing: err)])
            }
        }
    }

    private func setupPanel() {
        let config = presetManager.appConfig?.window ?? WindowConfig()
        let frame = NSRect(x: config.x, y: config.y,
                           width: config.width, height: config.height)
        let p = FloatingPanel(contentRect: frame)

        let contentView = ContentHostView(presetManager: presetManager)
        p.contentView = NSHostingView(rootView: contentView)
        p.alphaValue = CGFloat(config.opacity)
        p.orderFront(nil)

        self.panel = p

        // ミニアイコンも起動時に作成しておき、表示/非表示の切り替えだけで運用する
        let mini = MiniIconPanel(near: frame)
        mini.onRestore = { [weak self] in self?.expandFromMiniIcon() }
        self.miniIcon = mini
        // 初期状態は非表示
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "FloatingMacro")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "表示 / 非表示", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // プリセット切替: 表示は displayName、ペイロードはファイル ID (name)。
        let presetsMenu = NSMenu()
        for entry in presetManager.presetEntries {
            let item = NSMenuItem(title: entry.displayName,
                                  action: #selector(switchPreset(_:)),
                                  keyEquivalent: "")
            item.representedObject = entry.name
            if entry.name == presetManager.appConfig?.activePreset {
                item.state = .on
            }
            presetsMenu.addItem(item)
        }
        let presetsItem = NSMenuItem(title: "プリセット", action: nil, keyEquivalent: "")
        presetsItem.submenu = presetsMenu
        menu.addItem(presetsItem)

        menu.addItem(NSMenuItem.separator())

        // 透明度サブメニュー
        let opacityMenu = NSMenu()
        let currentOpacity = presetManager.appConfig?.window.opacity ?? 1.0
        let opacityChoices: [(String, Double)] = [
            ("25%", 0.25), ("50%", 0.50), ("75%", 0.75), ("100%", 1.0),
        ]
        for (label, value) in opacityChoices {
            let item = NSMenuItem(title: label,
                                  action: #selector(setOpacity(_:)),
                                  keyEquivalent: "")
            item.representedObject = NSNumber(value: value)
            if abs(currentOpacity - value) < 0.01 {
                item.state = .on
            }
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        // AI モード切替
        let agentModeMenu = NSMenu()
        let currentMode = presetManager.appConfig?.controlAPI.agentMode ?? .normal
        let agentModeChoices: [(String, AgentMode)] = [
            ("ノーマル",       .normal),
            ("テスト（自律）", .test),
            ("Claude Code",    .claudeCode),
        ]
        for (label, mode) in agentModeChoices {
            let item = NSMenuItem(title: label,
                                  action: #selector(setAgentMode(_:)),
                                  keyEquivalent: "")
            item.representedObject = mode.rawValue
            if mode == currentMode { item.state = .on }
            agentModeMenu.addItem(item)
        }
        let agentModeItem = NSMenuItem(title: "AI モード", action: nil, keyEquivalent: "")
        agentModeItem.submenu = agentModeMenu
        menu.addItem(agentModeItem)

        // 制御 API 有効/無効トグル
        let apiEnabled = presetManager.appConfig?.controlAPI.enabled ?? false
        let apiPort = presetManager.appConfig?.controlAPI.port ?? 17430
        let apiTitle = apiEnabled
            ? "制御 API: 有効 (:\(apiPort))"
            : "制御 API: 無効"
        let apiItem = NSMenuItem(title: apiTitle,
                                 action: #selector(toggleControlAPI),
                                 keyEquivalent: "")
        apiItem.state = apiEnabled ? .on : .off
        menu.addItem(apiItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "ボタン編集...", action: #selector(openSettings), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "AI に接続...", action: #selector(openAIIntegration), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "設定フォルダを開く", action: #selector(openConfigFolder), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "再読み込み", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(presetManager: presetManager)
    }

    @objc private func openAIIntegration() {
        AIIntegrationWindowController.shared.show(presetManager: presetManager)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let value = num.doubleValue
        presetManager.setOpacity(value)
        panel?.alphaValue = CGFloat(value)
        setupStatusItem()  // チェック状態を再描画
    }

    @objc private func setAgentMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AgentMode(rawValue: raw) else { return }
        presetManager.setAgentMode(mode)
        setupStatusItem()  // チェック状態を再描画
    }

    @objc private func toggleControlAPI() {
        let current = presetManager.appConfig?.controlAPI.enabled ?? false
        presetManager.setControlAPIEnabled(!current)
        setupStatusItem()  // チェック状態を再描画
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let p = panel else { return }
        let f = p.frame
        presetManager.setPanelFrame(
            x: Double(f.origin.x),
            y: Double(f.origin.y),
            width: Double(f.size.width),
            height: Double(f.size.height)
        )
        controlServer?.stop()
        LoggerContext.shared.flush()
    }

    /// Accessory-style apps live in the menu bar and should keep running even
    /// when every visible window is closed. Without this, closing the
    /// Settings window makes macOS terminate the whole app (which also
    /// takes the FloatingPanel with it).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Re-show the floating panel. Called by SettingsWindowController when
    /// the user closes the settings window with the red × — otherwise
    /// macOS tends to orderOut the panel along with the other window,
    /// leaving a menu-bar-only zombie. The menu-bar "Show / Hide" item
    /// is a separate path and is preserved.
    func restoreFloatingPanel() {
        LoggerContext.shared.info("AppDelegate", "restoreFloatingPanel", [
            "panel_present": String(panel != nil),
            "visible_before": String(panel?.isVisible ?? false),
        ])
        expandFromMiniIcon()
        LoggerContext.shared.info("AppDelegate", "restoreFloatingPanel after", [
            "visible_after": String(panel?.isVisible ?? false),
        ])
    }

    // MARK: - Mini icon collapse / expand

    private func collapseToMiniIcon() {
        guard let p = panel, let mini = miniIcon else { return }
        // 閉じる瞬間にパネル位置を config.json に保存
        // (applicationWillTerminate と同じ仕組みで、次回起動時の復元に使う)
        let f = p.frame
        presetManager.setPanelFrame(
            x: Double(f.origin.x),
            y: Double(f.origin.y),
            width: Double(f.size.width),
            height: Double(f.size.height)
        )
        // ミニアイコン位置: 前回ユーザーが置いた場所があればそれ、無ければパネルに合わせる
        let size: CGFloat = 48
        let origin = MiniIconPanel.savedOrigin ?? NSPoint(
            x: f.origin.x,
            y: f.origin.y + f.size.height - size
        )
        mini.setFrameOrigin(origin)
        p.orderOut(nil)
        mini.orderFront(nil)
    }

    private func expandFromMiniIcon() {
        miniIcon?.orderOut(nil)
        panel?.orderFront(nil)
    }

    @objc private func togglePanel() {
        guard let p = panel else { return }
        if p.isVisible {
            // パネルが見えている → 折りたたむ
            collapseToMiniIcon()
        } else if miniIcon?.isVisible == true {
            // ミニアイコンが見えている → パネルに戻す
            expandFromMiniIcon()
        } else {
            // どちらも見えていない → パネルを表示
            p.orderFront(nil)
        }
    }

    @objc private func switchPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        presetManager.switchPreset(to: name)
        // メニューバー再構築
        setupStatusItem()
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(ConfigLoader.defaultBaseURL)
    }

    @objc private func reloadConfig() {
        presetManager.loadInitialConfig()
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility 権限が必要です"
        alert.informativeText = "FloatingMacro がキーボードショートカットを送出するには、Accessibility 権限が必要です。システム設定で許可してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "後で")

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityChecker.openSystemPreferences()
        }
    }
}

struct ContentHostView: View {
    @ObservedObject var presetManager: PresetManager

    var body: some View {
        VStack(spacing: 0) {
            // 上端ヘッダー: 左にプリセット切替、右に AI 連携ウィンドウへの導線。
            // プリセット picker をここに常時出すことで、複数プリセットの
            // 切替を発見しやすくする (設定画面の picker と同期)。
            HStack(spacing: 4) {
                Menu {
                    ForEach(presetManager.presetEntries) { entry in
                        Button(action: { presetManager.switchPreset(to: entry.name) }) {
                            if entry.name == presetManager.appConfig?.activePreset {
                                Label(entry.displayName, systemImage: "checkmark")
                            } else {
                                Text(entry.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(presetManager.currentPreset?.displayName ?? "—")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("プリセットを切り替え")

                Spacer(minLength: 4)

                Button {
                    AIIntegrationWindowController.shared.show(
                        presetManager: presetManager
                    )
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("AI に接続を設定…")
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // ボタン一覧
            if let preset = presetManager.currentPreset {
                ScrollView(.vertical, showsIndicators: false) {
                    PresetView(
                        preset: preset,
                        onButtonTap: { button in
                            presetManager.executeButton(button)
                        },
                        onGroupEdit: { group in
                            SettingsWindowController.shared.show(
                                presetManager: presetManager,
                                selectGroupId: group.id
                            )
                        },
                        onButtonEdit: { button in
                            SettingsWindowController.shared.show(
                                presetManager: presetManager,
                                selectButtonId: button.id
                            )
                        },
                        onButtonDuplicate: { button in
                            _ = presetManager.duplicateButton(id: button.id)
                        },
                        onButtonDelete: { button in
                            _ = presetManager.deleteButton(id: button.id)
                        },
                        onButtonAdd: { group in
                            addNewButton(toGroupId: group.id)
                        }
                    )
                    // ScrollView の余白部分を埋めてコンテキストメニューが反応する領域を確保する
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .contextMenu {
                    panelContextMenu(preset: preset)
                }
            } else {
                VStack {
                    Spacer()
                    Text("プリセットが読み込めません")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // エラーバナー
            if let error = presetManager.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(4)
                    .padding(4)
            }

            // Accessibility 権限喪失バッジ。CGEvent.post は権限がなくても
            // void で成功扱いを返してしまうため、ログだけ見ても気づけない
            // (= ユーザーが「テキストボタンが効かない」と感じる主因)。
            // ここに常時バッジを出すことで、リビルド後に権限が剥がれた
            // 状態を視覚的に必ず気づけるようにする。
            if !presetManager.accessibilityTrusted {
                Button {
                    // One-click recovery: tccutil reset for our bundle id,
                    // then open the Accessibility pane. After this the
                    // FloatingMacro entry is GONE from the list, so the
                    // user just needs to drag/+ the .app back in (and the
                    // newly-added entry will actually take effect, since
                    // the stale shadow record is gone).
                    let bundleId = Bundle.main.bundleIdentifier ?? "com.veltrea.FloatingMacro"
                    TCCResetter.resetAccessibility(bundleId: bundleId)
                    AccessibilityChecker.openSystemPreferences()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 11, weight: .semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("アクセシビリティ権限が無効")
                                .font(.system(size: 10, weight: .semibold))
                            Text("ここをクリック → リセット & 設定を開く → 再追加")
                                .font(.system(size: 9))
                                .opacity(0.85)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.95))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("クリックすると tccutil で TCC エントリを削除し、System Settings → アクセシビリティを開きます。リストから FloatingMacro が消えるので、'+' か Drag&Drop で .app を再追加してください。")
                .padding(4)
            }
        }
        // 最大サイズに上限を設けない。これまで maxWidth: 300, maxHeight: 600
        // でハードキャップしていたため、ユーザーが NSPanel をドラッグして
        // 広げてもコンテントが追従せず「縮小はできるが拡大できない」現象が
        // 起きていた。SwiftUI 側を .infinity にして NSPanel のリサイズに
        // フルで追従するようにする。
        .frame(minWidth: 180, maxWidth: .infinity,
               minHeight: 100, maxHeight: .infinity)
    }

    // MARK: - Panel context menu

    @ViewBuilder
    private func panelContextMenu(preset: Preset) -> some View {
        if preset.groups.isEmpty {
            // グループがない場合はボタン編集画面を開くだけ
            Button {
                SettingsWindowController.shared.show(presetManager: presetManager)
            } label: {
                Label("ボタン編集を開く...", systemImage: "gear")
            }
        } else if preset.groups.count == 1, let group = preset.groups.first {
            Button {
                addNewButton(toGroupId: group.id)
            } label: {
                Label("新規ボタンを追加", systemImage: "plus.circle")
            }
            Divider()
            Button {
                SettingsWindowController.shared.show(presetManager: presetManager)
            } label: {
                Label("ボタン編集を開く...", systemImage: "gear")
            }
        } else {
            // グループが複数ある場合はグループ別に列挙
            ForEach(preset.groups, id: \.id) { group in
                Button {
                    addNewButton(toGroupId: group.id)
                } label: {
                    Label("「\(group.label)」に追加", systemImage: "plus.circle")
                }
            }
            Divider()
            Button {
                SettingsWindowController.shared.show(presetManager: presetManager)
            } label: {
                Label("ボタン編集を開く...", systemImage: "gear")
            }
        }
    }

    private func addNewButton(toGroupId groupId: String) {
        let id = "b-\(Int.random(in: 1000...9999))"
        let button = ButtonDefinition(
            id: id, label: "新ボタン",
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true)
        )
        _ = presetManager.addButton(button, toGroupId: groupId)
        SettingsWindowController.shared.show(presetManager: presetManager, selectButtonId: id)
    }
}
