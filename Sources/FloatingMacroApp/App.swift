import SwiftUI
import AppKit
import FloatingMacroCore

@main
struct FloatingMacroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 空のシーン — ウィンドウは AppDelegate で管理
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private let presetManager = PresetManager()
    private var controlServer: ControlServer?
    private var controlHandlers: ControlHandlers?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンを非表示
        NSApp.setActivationPolicy(.accessory)

        // ロギング: 他のすべてより先に設定する
        configureLogging()

        // 権限チェック
        if !AccessibilityChecker.isTrusted(prompt: false) {
            showAccessibilityAlert()
        }

        // 設定読み込み
        presetManager.loadInitialConfig()

        // フローティングパネル作成
        setupPanel()

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

        let server = ControlServer(
            preferredPort: UInt16(clamping: cfg.controlAPI.port),
            maxPortProbes: 10,
            handler: handlers.makeHandler()
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
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "FloatingMacro")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "表示 / 非表示", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // プリセット切替
        let presetsMenu = NSMenu()
        for name in presetManager.listPresets() {
            let item = NSMenuItem(title: name, action: #selector(switchPreset(_:)), keyEquivalent: "")
            item.representedObject = name
            if name == presetManager.appConfig?.activePreset {
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

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "ボタン編集...", action: #selector(openSettings), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "設定フォルダを開く", action: #selector(openConfigFolder), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "再読み込み", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(presetManager: presetManager)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let value = num.doubleValue
        presetManager.setOpacity(value)
        panel?.alphaValue = CGFloat(value)
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

    @objc private func togglePanel() {
        if let p = panel {
            if p.isVisible {
                p.orderOut(nil)
            } else {
                p.orderFront(nil)
            }
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
            // ヘッダー
            HStack {
                Text(presetManager.currentPreset?.displayName ?? "FloatingMacro")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            // ボタン一覧
            if let preset = presetManager.currentPreset {
                ScrollView(.vertical, showsIndicators: false) {
                    PresetView(preset: preset) { button in
                        presetManager.executeButton(button)
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
        }
        .frame(minWidth: 180, maxWidth: 300, minHeight: 100, maxHeight: 600)
    }
}
