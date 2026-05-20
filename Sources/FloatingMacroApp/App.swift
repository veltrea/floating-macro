import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import FloatingMacroCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Phase 3 で導入。複数フローティングパネルをまとめて管理するファサード。
    /// 旧 `panel` / `miniIcon` の単数フィールドはこの中に id ベースで格納される。
    var panelManager: PanelManager?
    var statusItem: NSStatusItem?
    let presetManager = PresetManager()
    var controlServer: ControlServer?
    var controlHandlers: ControlHandlers?
    var controlAPICancellable: AnyCancellable?
    var presetEntriesCancellable: AnyCancellable?
    /// Phase 5: 「📱 デバイスに送信」ウィンドウのコントローラ。再表示で再利用。
    var deviceSendController: DeviceSendWindowController?
    /// Phase 5: mDNS / Bonjour 公開。LAN 公開 ON のときだけ起動。
    let bonjour = BonjourAdvertiser()
    /// Phase 5: LAN 公開中の App Nap 抑止トークン。
    /// `.accessory` アプリは長時間ユーザー操作がないと App Nap で suspend され、
    /// その間 HTTP リスナが応答できなくなる (= iPhone でリロードすると応答待ち
    /// になる)。`beginActivity` で明示的に「常に応答が必要」と OS に伝える。
    /// 解除は LAN OFF 時または終了時。
    var lanActivityToken: NSObjectProtocol?
    /// Phase 3: appConfig.panels の差分 (add/remove) を監視して、
    /// PanelManager に NSWindow の生成・破棄を伝播させる。
    /// menu bar / Settings / Control API のいずれから panel を追加・削除しても
    /// 一元的に NSWindow が追従する。
    var panelsReconcileCancellable: AnyCancellable?
    var bgColorObserver: NSObjectProtocol?
    /// 直近の reconcile で観測した panel id 集合。Combine sink の Equatable
    /// 比較で `removeDuplicates` できないケース (panels 配列の中身は同じだが
    /// instance が違う場合) を見逃さないようにするための補助。
    var lastReconciledPanelIDs: Set<String> = []

    /// プライマリパネル（panels[0]）の id。便利アクセサ。
    var primaryPanelID: String? {
        return presetManager.appConfig?.panels.first?.id
    }
    var primaryPanel: FloatingPanel? {
        guard let id = primaryPanelID else { return nil }
        return panelManager?.panel(id: id)
    }

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

        // 権限チェック - 未許可状態の検出のみ。OS ダイアログは自分から
        // 呼ばない。
        //
        // 経緯: AXIsProcessTrustedWithOptions(prompt: true) を tccutil
        // reset 後に呼ぶと OS ダイアログがループする現象が観測された。
        // reset 直後は OS が自動で prompt を出すので、こちらから追加で
        // prompt: true を呼ぶと request が二重になりループの引き金に
        // なる。よって prompt: true は呼ばず、reset 直後のフローでは
        // OS の自動 prompt に任せ、reset を伴わない初回起動などでは
        // 修復ボタン (panel に常時表示されているバッジ) からユーザーに
        // 1 アクションだけお願いする。
        let promptAccessibility = CommandLine.arguments.contains("--prompt-accessibility")
        LoggerContext.shared.info("Accessibility", "startup", [
            "trusted": String(AccessibilityChecker.isTrusted(prompt: false)),
            "promptAccessibility": String(promptAccessibility),
        ])
        if !AccessibilityChecker.isTrusted(prompt: false) {
            // [修復] 経由 (--prompt-accessibility) の relaunch 時のみ
            // prompt: true を呼ぶ。これで OS が FloatingMacro を一覧に追加 +
            // ダイアログを表示する。OS ダイアログに含まれている
            // 「システム設定を開く」ボタンでユーザーは設定画面に行ける。
            // ここで openSystemPreferences や追加 alert を呼ぶと window
            // 取り合いで OS ダイアログが複数回再表示される副作用がある
            // ため、それらは呼ばない。
            if promptAccessibility {
                _ = AccessibilityChecker.isTrusted(prompt: true)
            }
        }

        // 設定読み込み
        presetManager.loadInitialConfig()

        // フローティングパネル作成（PanelManager が collapse 通知を内部購読する）
        setupPanel()

        // .accessory アプリはメニューバーを持たないが、⌘A / ⌘Z 等の
        // テキスト編集ショートカットはシステムが mainMenu のキー等価を
        // 参照してディスパッチする。Edit メニューを設定しておかないと
        // Settings ウィンドウの TextField で ⌘A が効かなくなる。
        setupEditMenu()

        // メニューバー常駐
        setupStatusItem()

        // /Applications 配下のアイコンをバックグラウンドで事前キャッシュ。
        // FloatingMacro はフローティングウィンドウとして常駐していて
        // ユーザー操作の合間に余裕があるので、そのタイミングで全アプリの
        // アイコンを取得・キャッシュしておく。これでアプリピッカーや
        // DnD でアプリを追加するときに「選んだ瞬間」アイコンが出る。
        //
        // 優先度 .utility (中程度): .background は OS のスロットリングが
        // 強くて起動直後に走り切らないことがあるため、ユーザーが起動から
        // 数十秒以内にピッカーを開く可能性を考えて少し上げている。
        // 並列度を 4 に絞っているので CPU/IO は食い荒らさない。
        Task.detached(priority: .utility) {
            await AppIconPrewarmer().prewarm(
                nsWorkspaceFallback: { url, size in
                    NSWorkspaceIconFallback.extractPNG(appURL: url, size: size)
                },
                size: 128,
                maxConcurrent: 4
            )
        }

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
        // Phase 5: LAN 公開トグルが変化していれば Bonjour 広報も連動させる。
        // start/stop は冪等。
        bonjour.stop()
        // メニューバーアイコンの色 / tooltip を再描画。
        setupStatusItem()
        // 表示中の Device Send ウィンドウも再描画 (URL / QR / トークンが変わる)。
        refreshDeviceSendWindowIfOpen()
        guard config.enabled else {
            // Control API が完全 OFF のときは ephemeral token も無効化。
            EphemeralLANTokenStore.shared.revoke()
            return
        }
        startControlServer()
    }

    private func startControlServer() {
        guard let cfg = presetManager.appConfig else { return }
        let logURL = ConfigLoader.defaultBaseURL
            .appendingPathComponent("logs/floatingmacro.log")
        // Phase 3: window_* (deprecated) はプライマリパネルに作用、panel_* は
        // panelManager 経由で id ベースに作用する。両方のために primaryPanel と
        // panelManager の両方をハンドラに渡す。
        let handlers = ControlHandlers(
            presetManager: presetManager,
            panel: primaryPanel,
            panelManager: panelManager,
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

        // Phase 5: LAN 公開時は ephemeral token も発行しておく (QR で配る用)。
        // 公開 OFF のときはトークンを破棄し、過去の QR は無効化する。
        if apiCfg.lanExposureEnabled {
            EphemeralLANTokenStore.shared.ensureIssued()
            // 起動時すでに LAN 公開 ON のときも prewarm を走らせる。スマホが
            // 起動直後にリクエストしてきても初回からキャッシュヒットになる。
            WebPanelIconRenderer.shared.prewarm(presetManager: presetManager)
            beginLANActivity()
        } else {
            EphemeralLANTokenStore.shared.revoke()
            endLANActivity()
        }

        let bindScope: ControlServer.BindScope = apiCfg.lanExposureEnabled ? .anyInterface : .loopback
        let server = ControlServer(
            preferredPort: UInt16(clamping: apiCfg.port),
            maxPortProbes: 10,
            bindScope: bindScope,
            handler: wrapWithAuth(token: token, handler: handlers.makeHandler())
        )
        self.controlServer = server

        // 別スレッドで起動 (メインスレッドをブロックしない)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch server.start(timeout: 2.0) {
            case .success(let port):
                let host = bindScope == .loopback ? "127.0.0.1" : "0.0.0.0"
                LoggerContext.shared.info("ControlServer",
                                          "Started on \(host):\(port)")
                // Phase 5: LAN 公開時のみ Bonjour で広報する。
                // bind が成功したポート番号を渡す (probe で +1 した可能性あり)。
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if apiCfg.lanExposureEnabled {
                        self.bonjour.start(port: Int(port))
                    } else {
                        self.bonjour.stop()
                    }
                }
            case .failure(let err):
                LoggerContext.shared.error("ControlServer",
                                           "Failed to start",
                                           ["error": String(describing: err)])
            }
        }
    }

    private func setupPanel() {
        let manager = PanelManager(
            contentBuilder: { [weak self] config in
                guard let self else { return NSView() }
                let view = ContentHostView(
                    presetManager: self.presetManager,
                    panelID: config.id,
                    onDeviceSendRequested: { [weak self] pid in
                        self?.openDeviceSend(panelID: pid)
                    }
                )
                return NSHostingView(rootView: view)
            },
            onCollapseRequested: { [weak self] id in
                self?.collapseToDock(panelID: id)
            },
            onHideRequested: { [weak self] id in
                self?.collapseToMiniIcon(panelID: id)
            },
            onExpandRequested: { [weak self] id in
                self?.expandFromDock(panelID: id)
            },
            onMiniMenuRequested: { [weak self] _, event in
                guard let self,
                      let view = self.panelManager?.miniIcon(id: self.primaryPanelID ?? "")?.contentView
                else { return }
                let menu = self.buildContextMenu()
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
        )
        manager.onDockBarDragged = { [weak self] id, origin, edge in
            self?.presetManager.updateDockBarPosition(id: id, x: Double(origin.x), y: Double(origin.y), edge: edge)
        }
        self.panelManager = manager

        // 設定の panels 配列を読んで初期表示。Phase 3 移行直後は 1 件のみ。
        if let configPanels = presetManager.appConfig?.panels {
            // 各パネルが参照するプリセットを事前ロードしてキャッシュに格納。
            // ContentHostView の最初の描画でディスク I/O によるカクつきを避ける。
            for panel in configPanels {
                _ = presetManager.preset(named: panel.presetName)
            }
            manager.openInitial(from: configPanels) { [weak self] config in
                guard let self else { return (label: config.presetName, iconName: nil) }
                let displayName = self.presetManager.preset(named: config.presetName)?.displayName ?? config.presetName
                let iconName = self.presetManager.preset(named: config.presetName)?.groups.first?.buttons.first?.icon
                return (label: displayName, iconName: iconName)
            }
            lastReconciledPanelIDs = Set(configPanels.map(\.id))
        }

        // Phase 3 (P3-9 関連): appConfig.panels の差分を監視。
        // Settings 画面・Control API・menu bar から add/remove されたとき、
        // どこ経由でも NSWindow が自動で追従する。
        panelsReconcileCancellable = presetManager.$appConfig
            .compactMap { $0?.panels }
            .sink { [weak self] newPanels in
                self?.reconcilePanels(newPanels)
            }

        bgColorObserver = NotificationCenter.default.addObserver(
            forName: .panelBackgroundColorChanged,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let id = info["id"] as? String else { return }
            let hex = info["hex"] as? String
            self?.panelManager?.setBackgroundColor(id: id, hex: hex)
        }
    }

    /// `appConfig.panels` を真実の源として PanelManager の NSWindow 群を一致させる。
    /// 追加された id は `openNew`、削除された id は `close`。
    /// frame / opacity / preset の変化は NSWindow を作り直さずそのまま流す
    /// (これらは個別 API で反映されるため reconcile では何もしない)。
    private func reconcilePanels(_ panels: [PanelConfig]) {
        guard let manager = panelManager else { return }
        let newIDs = Set(panels.map(\.id))

        // 追加: 既存 (lastReconciledPanelIDs) に無い id は openNew。
        for panel in panels where !lastReconciledPanelIDs.contains(panel.id) {
            // 念のため preset を warm-up してから window を出す。
            _ = presetManager.preset(named: panel.presetName)
            manager.openNew(config: panel)
        }
        // 削除: 既存にあったが新しい id 集合に無いものは close。
        for id in lastReconciledPanelIDs.subtracting(newIDs) {
            manager.close(id: id)
        }
        lastReconciledPanelIDs = newIDs
        // メニューバーの一覧も追従させる。
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // Phase 5: LAN 公開中は赤色のシンボル + tooltip で視覚警告。
            // 公開 OFF のときは template image (システムテーマ追従) に戻す。
            let lanExposed = presetManager.appConfig?.controlAPI.lanExposureEnabled ?? false
            if lanExposed {
                let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                let img = NSImage(systemSymbolName: "command.square.fill",
                                  accessibilityDescription: "FloatingMacro (LAN exposed)")?
                    .withSymbolConfiguration(cfg)
                img?.isTemplate = false
                button.image = img
                button.toolTip = L("FloatingMacro_LAN_公開中_Phase_5_140d2a")
            } else {
                let img = NSImage(systemSymbolName: "command.square",
                                  accessibilityDescription: "FloatingMacro")
                img?.isTemplate = true
                button.image = img
                button.toolTip = "FloatingMacro"
            }
        }
        statusItem?.menu = buildContextMenu()
    }

    /// ステータスバーとミニアイコン右クリックで共通利用するメニューを生成する。

    @objc func openSettings() {
        SettingsWindowController.shared.show(presetManager: presetManager)
    }

    @objc func openAIIntegration() {
        AIIntegrationWindowController.shared.show(presetManager: presetManager)
    }

    /// Phase 5: メニューバー「📱 デバイスに送信...」用の @objc セレクタエントリ。
    /// メニュー経由は panelID を指定せず、Web Panel が active preset を表示する。
    @objc func openDeviceSendFromMenu() {
        openDeviceSend(panelID: nil)
    }

    /// Phase 5: メニューバーと各フローティングパネルの QR ボタンから共有される
    /// 実体。
    /// - Parameter panelID: フローティングパネルから呼ばれた場合、その panel の
    ///   `presetName` を URL に埋め込んで「このパネル専用 QR」を作る。
    ///   `nil` (= メニュー経由) のときは preset を埋め込まず、Web Panel が
    ///   active preset を表示する。

    @objc func setOpacity(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let value = num.doubleValue
        // Phase 3 移行期: メニューバーの透明度はプライマリパネル (panels[0]) に作用。
        presetManager.setOpacity(value)
        if let id = primaryPanelID {
            panelManager?.setOpacity(id: id, opacity: value)
        }
        setupStatusItem()  // チェック状態を再描画
    }

    @objc func setAgentMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AgentMode(rawValue: raw) else { return }
        presetManager.setAgentMode(mode)
        setupStatusItem()  // チェック状態を再描画
    }

    @objc func toggleControlAPI() {
        let current = presetManager.appConfig?.controlAPI.enabled ?? false
        presetManager.setControlAPIEnabled(!current)
        setupStatusItem()  // チェック状態を再描画
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 全パネルの現在 frame を id 単位で書き戻して config.json に永続化。
        if let manager = panelManager {
            for (id, frame) in manager.currentFrames() {
                presetManager.updatePanelFrame(
                    id: id,
                    x: Double(frame.origin.x),
                    y: Double(frame.origin.y),
                    width: Double(frame.size.width),
                    height: Double(frame.size.height)
                )
            }
        }
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
            "panel_present": String(primaryPanel != nil),
            "visible_before": String(primaryPanel?.isVisible ?? false),
        ])
        if let id = primaryPanelID {
            expandFromMiniIcon(panelID: id)
        }
        LoggerContext.shared.info("AppDelegate", "restoreFloatingPanel after", [
            "visible_after": String(primaryPanel?.isVisible ?? false),
        ])
    }


    @objc func togglePanel() {
        guard let id = primaryPanelID, let p = panelManager?.panel(id: id) else { return }
        if p.isVisible {
            collapseToMiniIcon(panelID: id)
        } else if panelManager?.miniIcon(id: id)?.isVisible == true {
            expandFromMiniIcon(panelID: id)
        } else if panelManager?.dockBar(id: id)?.isVisible == true {
            expandFromDock(panelID: id)
        } else {
            expandFromMiniIcon(panelID: id)
        }
    }

    @objc func switchPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        presetManager.switchPreset(to: name)
        // メニューバー再構築
        setupStatusItem()
    }

    // MARK: - Phase 3: Panel menu actions

    /// 「新しいパネルを追加」: プライマリと同じプリセット名で 1 件追加。
    /// NSWindow の生成は `panelsReconcileCancellable` の sink が拾って自動で行う。
    @objc func addNewPanel() {
        guard let primaryID = primaryPanelID,
              let primaryPanel = panelManager?.panel(id: primaryID) else { return }
        let primaryFrame = primaryPanel.frame
        let presetName = presetManager.appConfig?.panels.first(where: { $0.id == primaryID })?.presetName
            ?? "default"
        let offset: CGFloat = 32
        let newWindow = WindowConfig(
            x: Double(primaryFrame.origin.x + offset),
            y: Double(primaryFrame.origin.y - offset),
            width: Double(primaryFrame.size.width),
            height: Double(primaryFrame.size.height),
            opacity: 1.0
        )
        _ = presetManager.addPanel(presetName: presetName, window: newWindow)
    }

    /// メニューバーのパネル一覧クリック: 該当パネルの表示/非表示をトグル。
    @objc func togglePanelByID(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        guard let p = panelManager?.panel(id: id) else { return }
        if p.isVisible {
            collapseToMiniIcon(panelID: id)
        } else if panelManager?.miniIcon(id: id)?.isVisible == true {
            expandFromMiniIcon(panelID: id)
        } else if panelManager?.dockBar(id: id)?.isVisible == true {
            expandFromDock(panelID: id)
        } else {
            expandFromMiniIcon(panelID: id)
        }
        setupStatusItem()
    }

    /// 「↳ ⋯ を閉じて削除」: 設定からパネル定義を削除。NSWindow の破棄は
    /// reconcile sink が自動で行うので、ここでは config 更新のみ。
    @objc func removePanelByID(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        _ = presetManager.removePanel(id: id)
    }

    @objc func dockPanelToEdge(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        let parts = payload.split(separator: "|")
        guard parts.count == 2,
              let edge = DockEdge(rawValue: String(parts[1])) else { return }
        let id = String(parts[0])
        collapseToDock(panelID: id, edge: edge)
        setupStatusItem()
    }

    @objc func undockPanelByID(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        expandFromDock(panelID: id)
        setupStatusItem()
    }

    @objc func resetDockBarPosition(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        panelManager?.resetDockBarPosition(id: id)
        presetManager.clearDockBarPosition(id: id)
    }

    @objc func gatherAllDockBars() {
        panelManager?.resetAllDockBarPositions()
        presetManager.clearAllDockBarPositions()
    }


    @objc func showAbout() {
        AboutWindowController.shared.show()
    }

    @objc func openConfigFolder() {
        NSWorkspace.shared.open(ConfigLoader.defaultBaseURL)
    }

    @objc func reloadConfig() {
        presetManager.loadInitialConfig()
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = L("Accessibility_権限が必要です_c1ef75")
        alert.informativeText = L("FloatingMacro_がキーボードショートカットを送出するには_Accessibility_権_df566b")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("システム設定を開く_ea27bb"))
        alert.addButton(withTitle: L("後で_1d5321"))

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityChecker.openSystemPreferences()
        }
    }
}
