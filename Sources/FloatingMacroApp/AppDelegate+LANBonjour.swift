import AppKit
import FloatingMacroCore

extension AppDelegate {

    func openDeviceSend(panelID: String?) {
        let lanExposed = presetManager.appConfig?.controlAPI.lanExposureEnabled ?? false
        let port = lanExposed
            ? (presetManager.appConfig?.controlAPI.lanPort ?? 17431)
            : (presetManager.appConfig?.controlAPI.port ?? 17430)
        let token = lanExposed
            ? EphemeralLANTokenStore.shared.ensureIssued()
            : (EphemeralLANTokenStore.shared.current ?? "")

        // Retrieve the preset name from a specified panel ID. Multiple panels can share the same preset.
        // Even if it's just the preset name on the URL, the web panel can be drawn correctly.
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

    /// Turn on/off LAN public mode. Not via Settings, but from the Device Send screen.
    /// Directly toggled, only rewrite appConfig (no side effects)
    /// Combine the LAN pipeline to pick up (`restartLANServer`).
    func setLANExposureEnabled(_ enabled: Bool) {
        guard var cfg = presetManager.appConfig else { return }
        guard cfg.controlAPI.lanExposureEnabled != enabled else { return }
        cfg.controlAPI.lanExposureEnabled = enabled
        presetManager.appConfig = cfg
        // Call ensureIssued immediately after ON to issue the first token.
        // restartControlServer also performs the same processing, but on the Device Send screen...
        // Redrawing occurs before restart is completed, so for caution.
        if enabled {
            EphemeralLANTokenStore.shared.ensureIssued()
            // Phase 5: To reduce simultaneous loading during the first connection of a smartphone,
            // Resize all preset buttons in the background, encode, and cache
            // Place on (icon=PNG, thumbnail=JPEG, each 3 size bucket).
            WebPanelIconRenderer.shared.prewarm(presetManager: presetManager)
            beginLANActivity()
        } else {
            endLANActivity()
        }
        // Refresh window.
        refreshDeviceSendWindowIfOpen()
    }

    /// Phase 5: LAN Public App Nap Suppression. The accessory app stays long-time
    /// Suspended without user operation, the HTTP response stops from iPhone.
    /// Reloads and becomes unresponsive. `.userInitiated` + `.idleSystemSleep`
    /// Declare only "active handling" without including "disabled".
    /// System sleep does not interfere, only suppress App Nap.
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
        let port = lanExposed
            ? (presetManager.appConfig?.controlAPI.lanPort ?? 17431)
            : (presetManager.appConfig?.controlAPI.port ?? 17430)
        let token = lanExposed
            ? EphemeralLANTokenStore.shared.ensureIssued()
            : (EphemeralLANTokenStore.shared.current ?? "")
        // If the window displayed contains a "specific panel's QR", output that.
        // Keep the preset unchanged while redrawing (token rotation/LAN toggle same)
        // Continues to be associated with the panel).
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
