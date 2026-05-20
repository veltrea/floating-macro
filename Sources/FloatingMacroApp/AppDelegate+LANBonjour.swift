import AppKit
import FloatingMacroCore

extension AppDelegate {

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
    func setLANExposureEnabled(_ enabled: Bool) {
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
    func beginLANActivity() {
        guard lanActivityToken == nil else { return }
        lanActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "FloatingMacro: serving Web Panel over LAN"
        )
        LoggerContext.shared.info("AppNap", "begin activity (LAN active)")
    }

    func endLANActivity() {
        guard let token = lanActivityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        lanActivityToken = nil
        LoggerContext.shared.info("AppNap", "end activity (LAN inactive)")
    }

    func rotateEphemeralLANToken() {
        _ = EphemeralLANTokenStore.shared.rotate()
        refreshDeviceSendWindowIfOpen()
    }

    func refreshDeviceSendWindowIfOpen() {
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

}
