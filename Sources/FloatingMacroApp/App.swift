import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import FloatingMacroCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Phase 3 で導入。複数フローティングパネルをまとめて管理するファサード。
    /// 旧 `panel` / `miniIcon` の単数フィールドはこの中に id ベースで格納される。
    private var panelManager: PanelManager?
    private var statusItem: NSStatusItem?
    private let presetManager = PresetManager()
    private var controlServer: ControlServer?
    private var controlHandlers: ControlHandlers?
    private var controlAPICancellable: AnyCancellable?
    private var presetEntriesCancellable: AnyCancellable?
    /// Phase 5: 「📱 デバイスに送信」ウィンドウのコントローラ。再表示で再利用。
    private var deviceSendController: DeviceSendWindowController?
    /// Phase 5: mDNS / Bonjour 公開。LAN 公開 ON のときだけ起動。
    private let bonjour = BonjourAdvertiser()
    /// Phase 5: LAN 公開中の App Nap 抑止トークン。
    /// `.accessory` アプリは長時間ユーザー操作がないと App Nap で suspend され、
    /// その間 HTTP リスナが応答できなくなる (= iPhone でリロードすると応答待ち
    /// になる)。`beginActivity` で明示的に「常に応答が必要」と OS に伝える。
    /// 解除は LAN OFF 時または終了時。
    private var lanActivityToken: NSObjectProtocol?
    /// Phase 3: appConfig.panels の差分 (add/remove) を監視して、
    /// PanelManager に NSWindow の生成・破棄を伝播させる。
    /// menu bar / Settings / Control API のいずれから panel を追加・削除しても
    /// 一元的に NSWindow が追従する。
    private var panelsReconcileCancellable: AnyCancellable?
    private var bgColorObserver: NSObjectProtocol?
    /// 直近の reconcile で観測した panel id 集合。Combine sink の Equatable
    /// 比較で `removeDuplicates` できないケース (panels 配列の中身は同じだが
    /// instance が違う場合) を見逃さないようにするための補助。
    private var lastReconciledPanelIDs: Set<String> = []

    /// プライマリパネル（panels[0]）の id。便利アクセサ。
    private var primaryPanelID: String? {
        return presetManager.appConfig?.panels.first?.id
    }
    private var primaryPanel: FloatingPanel? {
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
        manager.onDockBarDragged = { [weak self] id, origin in
            self?.presetManager.updateDockBarPosition(id: id, x: Double(origin.x), y: Double(origin.y))
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
                button.toolTip = "FloatingMacro — LAN 公開中 (Phase 5)"
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
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        // ── 人間操作ブロック ──
        menu.addItem(NSMenuItem(title: "表示 / 非表示", action: #selector(togglePanel), keyEquivalent: ""))

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

        // ── Phase 3: Panels サブメニュー ──
        // 「新しいパネル」を追加 → 既存パネルを一覧（クリックで表示トグル、
        // ⌥+クリックで削除）。複数パネル UX のメイン導線。
        let panelsMenu = NSMenu()
        panelsMenu.addItem(
            NSMenuItem(title: "新しいパネルを追加",
                       action: #selector(addNewPanel),
                       keyEquivalent: "")
        )
        panelsMenu.addItem(NSMenuItem.separator())
        let configPanels = presetManager.appConfig?.panels ?? []
        for cfgPanel in configPanels {
            let displayName: String
            if let preset = presetManager.preset(named: cfgPanel.presetName) {
                displayName = preset.displayName
            } else {
                displayName = cfgPanel.presetName
            }
            let isDocked = cfgPanel.dockedEdge != nil
            let isVisible = panelManager?.panel(id: cfgPanel.id)?.isVisible ?? false

            let title = isDocked
                ? "\(displayName)〔ドック中: \(cfgPanel.dockedEdge!.rawValue)〕"
                : displayName
            let item = NSMenuItem(
                title: title,
                action: #selector(togglePanelByID(_:)),
                keyEquivalent: ""
            )
            item.representedObject = cfgPanel.id
            item.state = isVisible ? .on : .off
            panelsMenu.addItem(item)

            // サブメニュー: ドック中 → 展開 + 別の辺に移動、通常 → 縁にドック
            if isDocked {
                let expandItem = NSMenuItem(
                    title: "  ↳ 展開",
                    action: #selector(undockPanelByID(_:)),
                    keyEquivalent: ""
                )
                expandItem.representedObject = cfgPanel.id
                panelsMenu.addItem(expandItem)

                let moveMenu = NSMenu()
                for edge in [DockEdge.left, .right, .top, .bottom] where edge != cfgPanel.dockedEdge {
                    let mi = NSMenuItem(title: edgeLabel(edge),
                                        action: #selector(dockPanelToEdge(_:)),
                                        keyEquivalent: "")
                    mi.representedObject = "\(cfgPanel.id)|\(edge.rawValue)"
                    moveMenu.addItem(mi)
                }
                let moveItem = NSMenuItem(title: "  ↳ 別の辺に移動", action: nil, keyEquivalent: "")
                moveItem.submenu = moveMenu
                panelsMenu.addItem(moveItem)

                if cfgPanel.dockBarPosition != nil {
                    let resetItem = NSMenuItem(
                        title: "  ↳ 位置をリセット",
                        action: #selector(resetDockBarPosition(_:)),
                        keyEquivalent: ""
                    )
                    resetItem.representedObject = cfgPanel.id
                    panelsMenu.addItem(resetItem)
                }
            } else {
                let dockMenu = NSMenu()
                for edge in [DockEdge.left, .right, .top, .bottom] {
                    let mi = NSMenuItem(title: edgeLabel(edge),
                                        action: #selector(dockPanelToEdge(_:)),
                                        keyEquivalent: "")
                    mi.representedObject = "\(cfgPanel.id)|\(edge.rawValue)"
                    dockMenu.addItem(mi)
                }
                let dockItem = NSMenuItem(title: "  ↳ 縁にドック", action: nil, keyEquivalent: "")
                dockItem.submenu = dockMenu
                panelsMenu.addItem(dockItem)
            }

            if configPanels.count > 1 {
                let removeItem = NSMenuItem(
                    title: "  ↳ 「\(displayName)」を閉じて削除",
                    action: #selector(removePanelByID(_:)),
                    keyEquivalent: ""
                )
                removeItem.representedObject = cfgPanel.id
                panelsMenu.addItem(removeItem)
            }
        }
        if configPanels.contains(where: { $0.dockedEdge != nil }) {
            panelsMenu.addItem(NSMenuItem.separator())
            panelsMenu.addItem(NSMenuItem(
                title: "ドックバーを集める",
                action: #selector(gatherAllDockBars),
                keyEquivalent: ""
            ))
        }
        let panelsItem = NSMenuItem(title: "パネル", action: nil, keyEquivalent: "")
        panelsItem.submenu = panelsMenu
        menu.addItem(panelsItem)

        menu.addItem(NSMenuItem(title: "編集...", action: #selector(openSettings), keyEquivalent: "e"))

        menu.addItem(NSMenuItem.separator())

        // ── AI ブロック ──
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

        let apiEnabled = presetManager.appConfig?.controlAPI.enabled ?? false
        let apiPort = presetManager.appConfig?.controlAPI.port ?? 17430
        let apiTitle = apiEnabled
            ? "AI 接続: オン (:\(apiPort))"
            : "AI 接続: オフ"
        let apiItem = NSMenuItem(title: apiTitle,
                                 action: #selector(toggleControlAPI),
                                 keyEquivalent: "")
        apiItem.state = apiEnabled ? .on : .off
        menu.addItem(apiItem)

        menu.addItem(NSMenuItem(title: "AI に接続...", action: #selector(openAIIntegration), keyEquivalent: ""))

        // Phase 5: スマホ / タブレットへの送信モーダル
        let sendItem = NSMenuItem(title: "📱 デバイスに送信...",
                                  action: #selector(openDeviceSendFromMenu),
                                  keyEquivalent: "")
        // ControlAPI が OFF だと意味がないので disabled にする (auto enable は
        // 後述: openDeviceSend 内で OS のお願いに沿った形にする方針もあるが、
        // 今は素直に「先に AI 接続を ON にしてください」)。
        sendItem.isEnabled = (presetManager.appConfig?.controlAPI.enabled ?? false)
        menu.addItem(sendItem)

        menu.addItem(NSMenuItem.separator())

        // ── システムブロック ──
        menu.addItem(NSMenuItem(title: "設定フォルダを開く", action: #selector(openConfigFolder), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "再読み込み", action: #selector(reloadConfig), keyEquivalent: "r"))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(presetManager: presetManager)
    }

    @objc private func openAIIntegration() {
        AIIntegrationWindowController.shared.show(presetManager: presetManager)
    }

    /// Phase 5: メニューバー「📱 デバイスに送信...」用の @objc セレクタエントリ。
    /// メニュー経由は panelID を指定せず、Web Panel が active preset を表示する。
    @objc private func openDeviceSendFromMenu() {
        openDeviceSend(panelID: nil)
    }

    /// Phase 5: メニューバーと各フローティングパネルの QR ボタンから共有される
    /// 実体。
    /// - Parameter panelID: フローティングパネルから呼ばれた場合、その panel の
    ///   `presetName` を URL に埋め込んで「このパネル専用 QR」を作る。
    ///   `nil` (= メニュー経由) のときは preset を埋め込まず、Web Panel が
    ///   active preset を表示する。
    func openDeviceSend(panelID: String?) {
        let lanExposed = presetManager.appConfig?.controlAPI.lanExposureEnabled ?? false
        let port = presetManager.appConfig?.controlAPI.port ?? 17430
        let token = lanExposed
            ? EphemeralLANTokenStore.shared.ensureIssued()
            : (EphemeralLANTokenStore.shared.current ?? "")

        // 指定 panelID から preset 名を引く。複数パネルが同じ preset を共有
        // していても、URL に preset 名だけ載せれば Web Panel が正しく描画できる。
        let presetName: String? = {
            guard let panelID = panelID else { return nil }
            return presetManager.appConfig?.panels
                .first(where: { $0.id == panelID })?.presetName
        }()

        let host = LANInterfaceFinder.bestIPv4Address() ?? "127.0.0.1"
        let url = WebPanelURLBuilder.make(host: host, port: port,
                                          token: token, preset: presetName)
        let qr = lanExposed
            ? (try? QRCodeGenerator.pngData(content: url, sizeInPixels: 480))
            : nil

        let bonjourReady = bonjour.state == .published

        if let existing = deviceSendController {
            existing.update(lanExposed: lanExposed, url: url, qrPNG: qr,
                            token: token, bonjourReady: bonjourReady,
                            presetName: presetName)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = DeviceSendWindowController(
            presetManager: presetManager,
            lanExposed: lanExposed,
            url: url,
            qrPNG: qr,
            token: token,
            bonjourReady: bonjourReady,
            presetName: presetName,
            onLANToggle: { [weak self] newValue in
                self?.setLANExposureEnabled(newValue)
            },
            onRotate: { [weak self] in
                self?.rotateEphemeralLANToken()
            }
        )
        deviceSendController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// LAN 公開モードを ON/OFF する。Settings 経由ではなく Device Send 画面から
    /// 直接トグルされるので、appConfig を書き換えるのみ (副作用は
    /// `restartControlServer` が拾う)。
    private func setLANExposureEnabled(_ enabled: Bool) {
        guard var cfg = presetManager.appConfig else { return }
        guard cfg.controlAPI.lanExposureEnabled != enabled else { return }
        cfg.controlAPI.lanExposureEnabled = enabled
        presetManager.appConfig = cfg
        // ON 直後は ensureIssued を呼んで最初のトークンを発行しておく。
        // restartControlServer も同じ処理をするが、Device Send 画面は
        // restart 完了より先に再描画されるので念のため。
        if enabled {
            EphemeralLANTokenStore.shared.ensureIssued()
            // Phase 5: スマホ初回接続時の同時ロードを軽くするため、
            // 全プリセットの全ボタンを背景でリサイズ + エンコードしてキャッシュ
            // に乗せる (icon=PNG, thumbnail=JPEG, 各 3 サイズバケット)。
            WebPanelIconRenderer.shared.prewarm(presetManager: presetManager)
            beginLANActivity()
        } else {
            endLANActivity()
        }
        // ウィンドウを最新化。
        refreshDeviceSendWindowIfOpen()
    }

    /// Phase 5: LAN 公開中の App Nap 抑止。.accessory アプリは長時間
    /// ユーザー操作なしで suspend されると HTTP 応答が止まり、iPhone から
    /// リロードしても無応答になる。`.userInitiated` + `.idleSystemSleep
    /// Disabled` を含めずに「アクティブ扱い」だけを宣言することで、
    /// システム sleep は妨げず App Nap だけ抑止する。
    private func beginLANActivity() {
        guard lanActivityToken == nil else { return }
        lanActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "FloatingMacro: serving Web Panel over LAN"
        )
        LoggerContext.shared.info("AppNap", "begin activity (LAN active)")
    }

    private func endLANActivity() {
        guard let token = lanActivityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        lanActivityToken = nil
        LoggerContext.shared.info("AppNap", "end activity (LAN inactive)")
    }

    private func rotateEphemeralLANToken() {
        _ = EphemeralLANTokenStore.shared.rotate()
        refreshDeviceSendWindowIfOpen()
    }

    private func refreshDeviceSendWindowIfOpen() {
        guard let controller = deviceSendController,
              controller.window?.isVisible == true else { return }
        let lanExposed = presetManager.appConfig?.controlAPI.lanExposureEnabled ?? false
        let port = presetManager.appConfig?.controlAPI.port ?? 17430
        let token = lanExposed
            ? EphemeralLANTokenStore.shared.ensureIssued()
            : (EphemeralLANTokenStore.shared.current ?? "")
        // 表示中のウィンドウが「特定 panel の QR」を出していた場合は、その
        // preset を保ったまま再描画する (token rotate / LAN トグル後も同じ
        // panel に紐づき続ける)。
        let presetName = controller.presetName
        let host = LANInterfaceFinder.bestIPv4Address() ?? "127.0.0.1"
        let url = WebPanelURLBuilder.make(host: host, port: port,
                                          token: token, preset: presetName)
        let qr = lanExposed
            ? (try? QRCodeGenerator.pngData(content: url, sizeInPixels: 480))
            : nil
        controller.update(lanExposed: lanExposed, url: url, qrPNG: qr,
                          token: token, bonjourReady: bonjour.state == .published,
                          presetName: presetName)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let value = num.doubleValue
        // Phase 3 移行期: メニューバーの透明度はプライマリパネル (panels[0]) に作用。
        presetManager.setOpacity(value)
        if let id = primaryPanelID {
            panelManager?.setOpacity(id: id, opacity: value)
        }
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

    // MARK: - Edge dock collapse / expand

    /// 指定 id のパネルを縁にドックする。パネル中心から最寄りの辺を自動判定。
    private func collapseToDock(panelID: String, edge: DockEdge? = nil) {
        guard let p = panelManager?.panel(id: panelID) else { return }
        let f = p.frame
        presetManager.updatePanelFrame(
            id: panelID,
            x: Double(f.origin.x),
            y: Double(f.origin.y),
            width: Double(f.size.width),
            height: Double(f.size.height)
        )
        let resolvedEdge: DockEdge
        if let edge {
            resolvedEdge = edge
        } else if let screen = NSScreen.main?.visibleFrame {
            let center = CGPoint(x: f.midX, y: f.midY)
            resolvedEdge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        } else {
            resolvedEdge = .right
        }

        let presetName = presetManager.appConfig?.panels.first(where: { $0.id == panelID })?.presetName ?? "default"
        let displayName = presetManager.preset(named: presetName)?.displayName ?? presetName
        let iconName = presetManager.preset(named: presetName)?.groups.first?.buttons.first?.icon

        let panelConfig = presetManager.appConfig?.panels.first(where: { $0.id == panelID })
        let customPos = panelConfig?.dockBarPosition.map { NSPoint(x: $0.x, y: $0.y) }
        panelManager?.collapseToDock(
            id: panelID,
            edge: resolvedEdge,
            label: displayName,
            iconName: iconName,
            customPosition: customPos
        )

        presetManager.dockPanel(id: panelID, edge: resolvedEdge)
    }

    /// ドックからパネルを展開する。旧 MiniIcon からの展開にも対応。
    private func expandFromDock(panelID: String) {
        panelManager?.expandFromDock(id: panelID)
        panelManager?.expandFromMini(id: panelID)
        presetManager.undockPanel(id: panelID)
    }

    // MARK: - Mini icon

    private func collapseToMiniIcon(panelID: String) {
        panelManager?.collapseToMini(id: panelID)
    }

    private func expandFromMiniIcon(panelID: String) {
        panelManager?.expandFromMini(id: panelID)
    }

    private func hidePanel(panelID: String) {
        panelManager?.panel(id: panelID)?.orderOut(nil)
    }

    @objc private func togglePanel() {
        guard let id = primaryPanelID, let p = panelManager?.panel(id: id) else { return }
        if p.isVisible {
            collapseToMiniIcon(panelID: id)
        } else if panelManager?.miniIcon(id: id)?.isVisible == true {
            expandFromMiniIcon(panelID: id)
        } else if panelManager?.dockBar(id: id)?.isVisible == true {
            expandFromDock(panelID: id)
        } else {
            p.orderFront(nil)
        }
    }

    @objc private func switchPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        presetManager.switchPreset(to: name)
        // メニューバー再構築
        setupStatusItem()
    }

    // MARK: - Phase 3: Panel menu actions

    /// 「新しいパネルを追加」: プライマリと同じプリセット名で 1 件追加。
    /// NSWindow の生成は `panelsReconcileCancellable` の sink が拾って自動で行う。
    @objc private func addNewPanel() {
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
    @objc private func togglePanelByID(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        guard let p = panelManager?.panel(id: id) else { return }
        if p.isVisible {
            collapseToMiniIcon(panelID: id)
        } else if panelManager?.miniIcon(id: id)?.isVisible == true {
            expandFromMiniIcon(panelID: id)
        } else if panelManager?.dockBar(id: id)?.isVisible == true {
            expandFromDock(panelID: id)
        } else {
            p.orderFront(nil)
        }
        setupStatusItem()
    }

    /// 「↳ ⋯ を閉じて削除」: 設定からパネル定義を削除。NSWindow の破棄は
    /// reconcile sink が自動で行うので、ここでは config 更新のみ。
    @objc private func removePanelByID(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        _ = presetManager.removePanel(id: id)
    }

    @objc private func dockPanelToEdge(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        let parts = payload.split(separator: "|")
        guard parts.count == 2,
              let edge = DockEdge(rawValue: String(parts[1])) else { return }
        let id = String(parts[0])
        collapseToDock(panelID: id, edge: edge)
        setupStatusItem()
    }

    @objc private func undockPanelByID(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        expandFromDock(panelID: id)
        setupStatusItem()
    }

    @objc private func resetDockBarPosition(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        panelManager?.resetDockBarPosition(id: id)
        presetManager.clearDockBarPosition(id: id)
    }

    @objc private func gatherAllDockBars() {
        panelManager?.resetAllDockBarPositions()
        presetManager.clearAllDockBarPositions()
    }

    private func edgeLabel(_ edge: DockEdge) -> String {
        switch edge {
        case .left:   return "左"
        case .right:  return "右"
        case .top:    return "上"
        case .bottom: return "下"
        }
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
    /// このパネルの永続 id (`PanelConfig.id`)。Phase 3 で導入。
    /// プリセットの参照・編集ターゲットの切替・各種 UI ルックアップに使う。
    let panelID: String
    /// Phase 5: パネル右上の QR アイコンが押されたとき、AppDelegate 側の
    /// `openDeviceSend(panelID:)` を呼び出してもらうコールバック。
    /// SwiftUI 内から直接 AppDelegate を参照しないことで Preview の壊れにくさを保つ。
    /// 引数の panelID で、QR にどのパネル / プリセットを埋め込むかを指示する。
    var onDeviceSendRequested: (String) -> Void = { _ in }
    @State private var confirmingPresetDelete = false
    @State private var showingPresetReorderSheet = false
    /// プリセットメモの折りたたみ展開状態。プリセット切替時はリセット
    /// （新しいプリセットのメモは「畳まれた状態で気付ける」のが望ましい）。
    @State private var memoExpanded: Bool = false
    /// アプリ/ファイルがパネル上にドラッグされている間 true。
    /// 視覚フィードバック（青枠ハイライト）の駆動に使う。
    @State private var isDropTargeted: Bool = false

    /// このパネルが現在表示しているプリセット。Phase 3 では panelID に紐づく
    /// `PanelConfig.presetName` を経由してキャッシュ (`PresetManager.loadedPresets`)
    /// から取得する。`@ObservedObject` 経由で `presetManager.appConfig` /
    /// `loadedPresets` の変化を観測しているので preset 切替 / 編集が即座に反映される。
    private var panelPreset: Preset? {
        presetManager.panelPreset(forPanelID: panelID)
    }

    /// このパネルが指している preset 名。`appConfig.panels` から逆引き。
    private var panelPresetName: String? {
        presetManager.appConfig?.panels.first(where: { $0.id == panelID })?.presetName
    }

    /// このパネルの保存済みスクロール位置 (アプリ再起動時の復元用)。
    /// `PanelScrollView.initialY` の供給源。`appConfig` が変わっても view が
    /// 再生成されないように `let initialY` でキャプチャしてから使う想定。
    private var panelScrollY: Double {
        presetManager.appConfig?.panels.first(where: { $0.id == panelID })?.scrollY ?? 0
    }

    /// SettingsWindowController を開く前に編集ターゲット (`currentPreset`) を
    /// このパネルのプリセットに切り替えるショートカット。複数パネルが別々の
    /// プリセットを表示しているとき、編集アクションが「このパネルのプリセット」
    /// に対して行われるようにする。
    private func openSettings(selectButtonId: String? = nil,
                              selectGroupId: String? = nil) {
        presetManager.setEditTarget(panelID: panelID)
        SettingsWindowController.shared.show(
            presetManager: presetManager,
            selectButtonId: selectButtonId,
            selectGroupId: selectGroupId
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 上端ヘッダー: 左にプリセット切替、右に AI 連携ウィンドウへの導線。
            // プリセット picker をここに常時出すことで、複数プリセットの
            // 切替を発見しやすくする (設定画面の picker と同期)。
            HStack(spacing: 4) {
                Menu {
                    ForEach(presetManager.presetEntries) { entry in
                        Button(action: {
                            presetManager.switchPanelPreset(panelID: panelID, to: entry.name)
                        }) {
                            if entry.name == panelPresetName {
                                Label(entry.displayName, systemImage: "checkmark")
                            } else {
                                Text(entry.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(panelPreset?.displayName ?? "—")
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
                .help("プリセットを切り替え (右クリックで編集/並べ替え/削除)")
                .contextMenu {
                    Button {
                        openSettings()
                    } label: {
                        Label("編集...", systemImage: "pencil")
                    }
                    .disabled(panelPreset == nil)

                    Button {
                        showingPresetReorderSheet = true
                    } label: {
                        Label("並べ替え...", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(presetManager.presetEntries.count < 2)

                    Divider()

                    Button(role: .destructive) {
                        confirmingPresetDelete = true
                    } label: {
                        Label("削除...", systemImage: "trash")
                    }
                    .disabled(
                        panelPreset == nil
                        || panelPreset?.name == "default"
                    )
                }
                .confirmationDialog(
                    "このプリセットを削除しますか?",
                    isPresented: $confirmingPresetDelete,
                    titleVisibility: .visible
                ) {
                    if let preset = panelPreset {
                        Button("「\(preset.displayName)」を削除", role: .destructive) {
                            _ = presetManager.deletePreset(name: preset.name)
                        }
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    if let preset = panelPreset {
                        let buttonCount = preset.groups.reduce(0) { $0 + $1.buttons.count }
                        Text("グループ \(preset.groups.count) 個・ボタン \(buttonCount) 個もすべて削除されます。この操作は元に戻せません。")
                    }
                }
                .sheet(isPresented: $showingPresetReorderSheet) {
                    PresetReorderSheet(
                        presetManager: presetManager,
                        isPresented: $showingPresetReorderSheet
                    )
                }

                Spacer(minLength: 4)

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("編集ウィンドウを開く…")

                // Phase 5: QR / デバイスに送信。このパネル単独の QR を出す。
                Button {
                    onDeviceSendRequested(panelID)
                } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("デバイスに送信…")

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

            // プリセットメモ（折りたたみ）。memo が空のプリセットでは描画しない。
            if let memo = panelPreset?.memo,
               !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                presetMemoBlock(memo)
            }

            // ボタン一覧
            if let preset = panelPreset {
                // PanelScrollView (NSScrollView ラッパー) を使うことで
                // アプリ再起動後にスクロール位置を復元できる。
                // 復元値はこのパネルの `PanelConfig.scrollY`。スクロール変化は
                // PresetManager が debounce 付きで永続化する。
                let initialY = CGFloat(panelScrollY)
                PanelScrollView(
                    initialY: initialY,
                    onScrollChange: { y in
                        presetManager.updatePanelScrollY(id: panelID, y: Double(y))
                    }
                ) {
                    VStack(spacing: 0) {
                        PresetView(
                            preset: preset,
                            onButtonTap: { button in
                                presetManager.executeButton(button)
                            },
                            onGroupEdit: { group in
                                openSettings(selectGroupId: group.id)
                            },
                            onGroupDelete: { group in
                                _ = presetManager.deleteGroup(id: group.id)
                            },
                            onButtonEdit: { button in
                                openSettings(selectButtonId: button.id)
                            },
                            onButtonDuplicate: { button in
                                _ = presetManager.duplicateButton(id: button.id)
                            },
                            onButtonDelete: { button in
                                _ = presetManager.deleteButton(id: button.id)
                            },
                            onButtonAdd: { group in
                                addNewButton(toGroupId: group.id)
                            },
                            onPasteButton: { group, afterButtonId in
                                pasteButtonToGroup(group.id, afterButtonId: afterButtonId)
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // Color.clear / 空 VStack 領域は contentShape を
                    // 付けないと右クリックを拾わない。Rectangle で全域を
                    // hit-testable にして、ボタン以外の場所でも contextMenu
                    // が反応するようにする。子の MacroButtonView /
                    // GroupView ヘッダーが持つ独自 contextMenu は
                    // そちらが優先される。
                    .contentShape(Rectangle())
                    .contextMenu {
                        panelContextMenu(preset: preset)
                    }
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
                // Self-restart recovery flow:
                //   1. tccutil reset → drop the (possibly stale) TCC entry
                //   2. Re-launch ourselves with --prompt-accessibility
                //   3. terminate the current process
                //   4. The new process, on startup, calls
                //      AXIsProcessTrustedWithOptions(prompt: true) → the OS
                //      shows its system "Allow FloatingMacro?" dialog and
                //      adds a fresh entry to the Accessibility list. The
                //      user just flips the switch.
                //
                // Same-process prompt: true は AXIsProcessTrusted() が stale
                // TRUE を返してバナーが誤って消える問題があるため、self-restart
                // でクリーン状態にしてから prompt: true を呼ぶ。
                let recover: () -> Void = {
                    // Self-restart recovery:
                    //   1. tccutil reset で stale TCC エントリを削除
                    //   2. NSWorkspace.openApplication で自身を
                    //      --prompt-accessibility 引数付きで再起動
                    //   3. completion ハンドラで現プロセスを terminate
                    //
                    // 同プロセスで prompt: true を呼ぶ「シンプル版」と違い、
                    // 新プロセスで AX キャッシュがクリーンな状態から
                    // prompt: true を呼ぶので、古いエントリ + stale TRUE
                    // で一覧追加が阻害される状況を回避できる。
                    //
                    // OpenConfiguration.arguments で argv に確実に
                    // --prompt-accessibility を渡す (Process + open --args
                    // 経由だと Launch Services が argv を落とすケースが
                    // あるため、現代的な API を使う)。
                    let logger = LoggerContext.shared
                    let bundleId = Bundle.main.bundleIdentifier ?? "com.veltrea.FloatingMacro"
                    logger.info("Accessibility", "recover requested", ["bundleId": bundleId])
                    TCCResetter.resetAccessibility(bundleId: bundleId)
                    let appURL = Bundle.main.bundleURL
                    let config = NSWorkspace.OpenConfiguration()
                    config.arguments = ["--prompt-accessibility"]
                    config.createsNewApplicationInstance = true
                    logger.info("Accessibility", "relaunching", ["appURL": appURL.path])
                    NSWorkspace.shared.openApplication(at: appURL, configuration: config) { runningApp, error in
                        if let error = error {
                            logger.error("Accessibility", "relaunch failed", [
                                "error": String(describing: error),
                            ])
                            // フォールバック: 設定画面だけでも開く
                            DispatchQueue.main.async {
                                AccessibilityChecker.openSystemPreferences()
                            }
                            return
                        }
                        let pidStr = runningApp.map { String($0.processIdentifier) } ?? "nil"
                        logger.info("Accessibility", "relaunch succeeded", ["newPid": pidStr])
                        DispatchQueue.main.async {
                            NSApp.terminate(nil)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    Text("アクセシビリティ権限が無効")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer(minLength: 4)
                    Button(action: recover) {
                        Text("修復")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("tccutil で TCC エントリをリセットし、--prompt-accessibility 付きで自身を再起動します。新プロセスが OS の許可ダイアログを呼び、一覧にエントリを追加するので、ユーザーはスイッチを ON にするだけで済みます。")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.95))
                .cornerRadius(4)
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
        // パネル全面でファイル/アプリのドロップを受け付け、ボタン化する。
        // .app は bundle id ベースの launch action、その他のファイルは
        // 絶対パスの launch action として登録される。
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedProviders(providers)
            return true
        }
        .overlay(
            // ドラッグ中の視覚フィードバック。Stream Deck と同じく「ここに
            // 落とせる」のが分かるようにアクセントカラーで縁を強調する。
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear,
                        lineWidth: 3)
                .allowsHitTesting(false)
        )
    }

    /// `.onDrop` のプロバイダから fileURL を取り出し、PanelDropHandler に渡す。
    /// NSItemProvider の loadItem はコールバックベースなので非同期で集めて
    /// 全件揃ったタイミングでメインスレッドからハンドラを呼ぶ。
    private func handleDroppedProviders(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var collected: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                              options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                } else {
                    url = nil
                }
                if let u = url {
                    lock.lock()
                    collected.append(u)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                await PanelDropHandler.handleDroppedURLs(
                    collected, presetManager: presetManager)
            }
        }
    }

    // MARK: - Panel context menu

    @ViewBuilder
    private func backgroundColorMenu() -> some View {
        Menu {
            let presetColors: [(String, String)] = [
                ("システム既定", ""),
                ("ダークネイビー", "#1a1a2e"),
                ("ディープパープル", "#2d1b4e"),
                ("ミッドナイトグリーン", "#0d2b2b"),
                ("チャコール", "#2b2b2b"),
                ("スレートブルー", "#1e2d3d"),
                ("ダークレッド", "#2e1a1a"),
                ("フォレストグリーン", "#1a2e1a"),
            ]
            let currentHex = presetManager.appConfig?.panels
                .first(where: { $0.id == panelID })?.window.backgroundColor
            ForEach(presetColors, id: \.1) { label, hex in
                Button {
                    let value = hex.isEmpty ? nil : hex
                    presetManager.updatePanelBackgroundColor(id: panelID, hex: value)
                    NotificationCenter.default.post(
                        name: .panelBackgroundColorChanged,
                        object: nil,
                        userInfo: ["id": panelID, "hex": value as Any]
                    )
                } label: {
                    HStack {
                        Text(label)
                        if (!hex.isEmpty && currentHex == hex)
                            || (hex.isEmpty && currentHex == nil) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                openColorPanel()
            } label: {
                Label("カスタム色...", systemImage: "paintpalette")
            }
        } label: {
            Label("背景色", systemImage: "paintbrush")
        }
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        let currentHex = presetManager.appConfig?.panels
            .first(where: { $0.id == panelID })?.window.backgroundColor
        if let hex = currentHex, hex.count >= 7, hex.hasPrefix("#"),
           let r = UInt8(hex.dropFirst().prefix(2), radix: 16),
           let g = UInt8(hex.dropFirst(3).prefix(2), radix: 16),
           let b = UInt8(hex.dropFirst(5).prefix(2), radix: 16) {
            panel.color = NSColor(
                srgbRed: CGFloat(r) / 255,
                green:   CGFloat(g) / 255,
                blue:    CGFloat(b) / 255,
                alpha:   1.0
            )
        }
        panel.setTarget(nil)
        panel.setAction(nil)
        let id = panelID
        let observer = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel, queue: .main
        ) { [weak presetManager] note in
            guard let cp = note.object as? NSColorPanel,
                  let srgb = cp.color.usingColorSpace(.sRGB) else { return }
            let r = Int((srgb.redComponent   * 255).rounded())
            let g = Int((srgb.greenComponent * 255).rounded())
            let b = Int((srgb.blueComponent  * 255).rounded())
            let hex = String(format: "#%02X%02X%02X", r, g, b)
            presetManager?.updatePanelBackgroundColor(id: id, hex: hex)
            NotificationCenter.default.post(
                name: .panelBackgroundColorChanged,
                object: nil,
                userInfo: ["id": id, "hex": hex]
            )
        }
        panel.orderFront(nil)
        objc_setAssociatedObject(panel, "bgColorObserver", observer, .OBJC_ASSOCIATION_RETAIN)
    }

    @ViewBuilder
    private func panelContextMenu(preset: Preset) -> some View {
        if preset.groups.isEmpty {
            Button {
                addNewGroup()
            } label: {
                Label("新規グループを追加", systemImage: "folder.badge.plus")
            }
            Button {
                pasteGroup()
            } label: {
                Label("グループを貼り付け", systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label("編集を開く...", systemImage: "gear")
            }
        } else if preset.groups.count == 1, let group = preset.groups.first {
            Button {
                addNewButton(toGroupId: group.id)
            } label: {
                Label("新規ボタンを追加", systemImage: "plus.circle")
            }
            Button {
                addNewGroup()
            } label: {
                Label("新規グループを追加", systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                pasteButtonToGroup(group.id)
            } label: {
                Label("ボタンを貼り付け", systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasButton())
            Button {
                pasteGroup()
            } label: {
                Label("グループを貼り付け", systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label("編集を開く...", systemImage: "gear")
            }
        } else {
            ForEach(preset.groups, id: \.id) { group in
                Button {
                    addNewButton(toGroupId: group.id)
                } label: {
                    Label("「\(group.label)」に追加", systemImage: "plus.circle")
                }
            }
            Divider()
            Button {
                addNewGroup()
            } label: {
                Label("新規グループを追加", systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                pasteButtonToGroup(preset.groups.last!.id)
            } label: {
                Label("ボタンを貼り付け", systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasButton())
            Button {
                pasteGroup()
            } label: {
                Label("グループを貼り付け", systemImage: "doc.on.clipboard")
            }
            .disabled(!PasteboardHelper.hasGroup())
            Divider()
            backgroundColorMenu()
            Divider()
            Button {
                openSettings()
            } label: {
                Label("編集を開く...", systemImage: "gear")
            }
        }
    }

    private func addNewButton(toGroupId groupId: String) {
        let id = "b-\(Int.random(in: 1000...9999))"
        let button = ButtonDefinition(
            id: id, label: "新ボタン",
            iconText: "✨",
            action: .text(content: "", pasteDelayMs: 120, restoreClipboard: true, appendMode: false)
        )
        // このパネルのプリセットを編集ターゲットに切り替えてから add → settings で選択。
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addButton(button, toGroupId: groupId)
        openSettings(selectButtonId: id)
    }

    private func addNewGroup() {
        let id = "g-\(Int.random(in: 1000...9999))"
        let group = ButtonGroup(
            id: id, label: "新グループ",
            iconText: "📁",
            buttons: []
        )
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addGroup(group)
        openSettings(selectGroupId: id)
    }

    private func pasteButtonToGroup(_ groupId: String, afterButtonId: String? = nil) {
        guard let btn = PasteboardHelper.pasteButton() else { return }
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addButton(btn, toGroupId: groupId, afterButtonId: afterButtonId)
    }

    private func pasteGroup() {
        guard let group = PasteboardHelper.pasteGroup() else { return }
        presetManager.setEditTarget(panelID: panelID)
        _ = presetManager.addGroup(group)
    }

    // MARK: - Preset memo block

    /// プリセット単位メモの折りたたみブロック。タイトル行は常時表示し、
    /// クリックで本文を展開／格納する。展開状態はプリセット切替で false に
    /// 戻すことで「新しいプリセットでも気付ける」設計にしている。
    @ViewBuilder
    private func presetMemoBlock(_ memo: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { memoExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                    Text("メモ")
                        .font(.system(size: 10, weight: .medium))
                    if !memoExpanded {
                        Text(memo.split(separator: "\n").first.map(String.init) ?? "")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: memoExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if memoExpanded {
                Text(memo)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
        .background(Color.yellow.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, 4)
        .onChange(of: panelPresetName) { _ in
            // このパネルのプリセットが切り替わったらメモ展開状態をリセット。
            memoExpanded = false
        }
    }

}
