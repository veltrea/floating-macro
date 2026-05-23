import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import FloatingMacroCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Introduced in Phase 3. Facade for managing multiple floating panels collectively.
    /// Old panel/miniIcon singular fields are stored here with ID-based storage.
    var panelManager: PanelManager?
    var statusItem: NSStatusItem?
    let presetManager = PresetManager()
    var acpServer: ControlServer?
    var lanServer: ControlServer?
    var controlHandlers: ControlHandlers?
    var acpConfigCancellable: AnyCancellable?
    var lanConfigCancellable: AnyCancellable?
    var presetEntriesCancellable: AnyCancellable?
    /// Phase 5: "Send to Device" Window Controller. Reusable on redisplay.
    var deviceSendController: DeviceSendWindowController?
    /// Phase 5: mDNS/Bonjour Public. Launch only when LAN Public is ON.
    let bonjour = BonjourAdvertiser()
    /// Phase 5: LAN Public App Nap Suppress Token.
    /// The `.accessory` app is suspended by App Nap if there are no user interactions for a long time,
    /// During that time, the HTTP listener becomes unresponsive (reload on iPhone waits for response)
    /// Indicates that a response is always required. Explicitly convey to the OS via `beginActivity` that a response is mandatory.
    /// Cancellation occurs at LAN OFF time or when the session ends.
    var lanActivityToken: NSObjectProtocol?
    /// Phase 3: Monitor differences in appConfig.panels (add/remove) and
    /// Propagate the creation and destruction of NSWindow to PanelManager.
    /// Add or remove a panel from any of the menu bar, Settings, or Control API.
    /// One-dimensionally follows NSWindow.
    var panelsReconcileCancellable: AnyCancellable?
    var bgColorObserver: NSObjectProtocol?
    /// Recent panel ID set observed in reconcile. Combine sink's Equatable
    /// Cannot remove duplicates in cases where (`removeDuplicates`) panels array contents are the same but
    /// Auxiliary to ensure that different instances are not overlooked.
    var lastReconciledPanelIDs: Set<String> = []

    /// Primary panel (panel[0]) ID. Convenient accessor.
    var primaryPanelID: String? {
        return presetManager.appConfig?.panels.first?.id
    }
    var primaryPanel: FloatingPanel? {
        guard let id = primaryPanelID else { return nil }
        return panelManager?.panel(id: id)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide Dock Icon
        NSApp.setActivationPolicy(.accessory)

        // Logging: Set before all others
        configureLogging()

        // Binary ID check - Hash changes during rebuild/update
        // If the case is, automatically reset the TCC entry. This means
        // Call AccessibilityChecker.isTrusted before running it must be necessary
        // A certain (to prevent the probe from being cached, also to take advantage of the effect of reset on the first call)
        // For viewing with probe).
        let bundleId = Bundle.main.bundleIdentifier ?? "com.veltrea.FloatingMacro"
        BinaryIdentity.handleStartupCheck(bundleId: bundleId)

        // Permission check - only detects unauthorized state. OS dialog is self-initiated.
        // Not called.
        //
        // Background: AXIsProcessTrustedWithOptions(prompt: true) to tccutil
        // A loop occurs where an OS dialog is called after reset.
        // After reset, the OS automatically prompts for a password, so we need to add one here.
        // When prompt is true, request becomes duplicated and triggers the loop.
        // Therefore, prompt: true is not called, and the flow after reset.
        // At the first launch without reset, rely on OS's automatic prompts.
        // Repair button (badge always displayed on panel) from user
        // Please perform only one action.
        let promptAccessibility = CommandLine.arguments.contains("--prompt-accessibility")
        LoggerContext.shared.info("Accessibility", "startup", [
            "trusted": String(AccessibilityChecker.isTrusted(prompt: false)),
            "promptAccessibility": String(promptAccessibility),
        ])
        if !AccessibilityChecker.isTrusted(prompt: false) {
            // [Repair] Only during relaunch via (--prompt-accessibility)
            // Call true to add FloatingMacro to the list in the OS.
            // Display a dialog. Included in the OS dialog.
            // Opening the "System Settings" button allows the user to access the settings screen.
            // Here is the translation:
Here, calling openSystemPreferences or adding an additional alert will cause a window to appear.
            // There is a side effect that the OS dialog appears multiple times due to repeated interactions.
            // Because they don't call them.
            if promptAccessibility {
                _ = AccessibilityChecker.isTrusted(prompt: true)
            }
        }

        // Setting loading
        presetManager.loadInitialConfig()

        // Floating panel creation (PanelManager subscribes internally to collapse notifications)
        setupPanel()

        // The accessory app does not have a menu bar, but it supports shortcuts like ⌘A and ⌘Z.
        // Text editing shortcuts are system keys equivalent to the main menu.
        // Dispatch to reference. The Edit menu must be set up beforehand.
        // The ⌘A shortcut does not work in the TextField of the Settings window.
        setupEditMenu()

        // Always Running in Menu Bar
        setupStatusItem()

        // Cache icons under Applications in the background.
        // FloatingMacro is always resident as a floating window.
        // At the opportune moment between user interactions, perform a full scan of all applications.
        // Get and cache icons. This allows for app picker and...
        // When adding an app in DnD, the "selected moment" icon appears.
        //
        // Priority: Utility (.medium): Background is when the OS throttles...
        // Because it may not finish running immediately after launch due to being too strong, the user from startup...
        // Considering the possibility of opening the picker within a few dozen seconds.
        // Parallelism is narrowed to 4, so CPU/IO will not be devoured.
        Task.detached(priority: .utility) {
            await AppIconPrewarmer().prewarm(
                nsWorkspaceFallback: { url, size in
                    NSWorkspaceIconFallback.extractPNG(appURL: url, size: size)
                },
                size: 128,
                maxConcurrent: 4
            )
        }

        // Control API (enabled in settings, starts in background)
        //
        // The memory of CLAUDE.md states that the "MCP server starts in another thread within 1-2 seconds" approach.
        // Following this, reduce the initialization cost on the main thread for ControlServer.
        // Even if there is a failure, the application itself normally launches.
        if presetManager.appConfig?.controlAPI.enabled ?? false {
            startControlServers()
        }

        // Monitor only changes to ACP-related fields and restart the ACP server.
        acpConfigCancellable = presetManager.$appConfig
            .compactMap { $0?.controlAPI }
            .map { ACPConfigProjection(enabled: $0.enabled, port: $0.port,
                                       agentMode: $0.agentMode, requireAuth: $0.requireAuth,
                                       testMode: $0.testMode) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] proj in
                self?.restartACPServer(enabled: proj.enabled)
            }

        // Monitor changes only in LAN-related fields and restart the LAN server.
        lanConfigCancellable = presetManager.$appConfig
            .compactMap { $0?.controlAPI }
            .map { LANConfigProjection(enabled: $0.enabled,
                                       lanExposureEnabled: $0.lanExposureEnabled,
                                       lanPort: $0.lanPort) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] proj in
                self?.restartLANServer(enabled: proj.enabled && proj.lanExposureEnabled)
            }

        // If the preset list changes, rebuild the menu bar.
        // SwiftUI's Picker automatically redraws when using @Published, but AppKit's
        // The NSMenu needs to be explicitly recreated.
        presetEntriesCancellable = presetManager.$presetEntries
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupStatusItem()
            }
    }

    /// In the accessory app, make text fields function like ⌘A and ⌘Z.
    /// Register the menu to NSApp.mainMenu.
    /// The menu bar itself is not displayed, but it is used for key-equivalent dispatch.
    private func setupEditMenu() {
        let mainMenu = NSMenu()

        // App menu (empty placeholder. macOS treats the first item as the app name).
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        appItem.submenu = NSMenu()

        // Edit Menu
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
            // Launch continues even if the log cannot be opened
            NSLog("FloatingMacro: log init failed: \(error)")
        }
    }

    // MARK: - Combine projection structs

    private struct ACPConfigProjection: Equatable {
        let enabled: Bool
        let port: Int
        let agentMode: AgentMode
        let requireAuth: Bool
        let testMode: Bool
    }

    private struct LANConfigProjection: Equatable {
        let enabled: Bool
        let lanExposureEnabled: Bool
        let lanPort: Int
    }

    // MARK: - Dual-server lifecycle

    private func startControlServers() {
        guard let cfg = presetManager.appConfig else { return }
        let apiCfg = cfg.controlAPI
        setupControlHandlers()
        startACPServer()
        if apiCfg.lanExposureEnabled {
            startLANServer()
        }
    }

    private func setupControlHandlers() {
        guard controlHandlers == nil else { return }
        let logURL = ConfigLoader.defaultBaseURL
            .appendingPathComponent("logs/floatingmacro.log")
        controlHandlers = ControlHandlers(
            presetManager: presetManager,
            panel: primaryPanel,
            panelManager: panelManager,
            logURL: logURL
        )
    }

    private func resolveKeychainToken() -> String? {
        guard let cfg = presetManager.appConfig else { return nil }
        let apiCfg = cfg.controlAPI
        guard apiCfg.requireAuth && !apiCfg.testMode else { return nil }
        do {
            return try TokenStore.loadOrCreate()
        } catch {
            LoggerContext.shared.error("ControlServer",
                                       "Keychain access failed; starting without auth",
                                       ["error": String(describing: error)])
            return nil
        }
    }

    // MARK: ACP server (loopback, stable)

    private func startACPServer() {
        guard let cfg = presetManager.appConfig else { return }
        setupControlHandlers()
        guard let handlers = controlHandlers else { return }
        let apiCfg = cfg.controlAPI
        let token = resolveKeychainToken()

        let server = ControlServer(
            preferredPort: UInt16(clamping: apiCfg.port),
            maxPortProbes: 10,
            bindScope: .loopback,
            handler: wrapWithAuth(token: token, handler: handlers.makeHandler())
        )
        server.healthFailureHandler = { [weak self] in
            DispatchQueue.main.async { self?.restartACPServer(enabled: true) }
        }
        self.acpServer = server

        DispatchQueue.global(qos: .userInitiated).async {
            switch server.start(timeout: 2.0) {
            case .success(let port):
                LoggerContext.shared.info("ControlServer",
                                          "ACP started on 127.0.0.1:\(port)")
            case .failure(let err):
                LoggerContext.shared.error("ControlServer",
                                           "ACP failed to start",
                                           ["error": String(describing: err)])
            }
        }
    }

    private func restartACPServer(enabled: Bool) {
        guard let server = acpServer else {
            if enabled { startACPServer() }
            return
        }
        server.stop { [weak self] in
            DispatchQueue.main.async {
                self?.acpServer = nil
                self?.setupStatusItem()
                guard enabled else { return }
                self?.startACPServer()
            }
        }
    }

    // MARK: LAN server (anyInterface, togglable)

    private func startLANServer() {
        guard let cfg = presetManager.appConfig else { return }
        setupControlHandlers()
        guard let handlers = controlHandlers else { return }
        let apiCfg = cfg.controlAPI

        EphemeralLANTokenStore.shared.ensureIssued()
        WebPanelIconRenderer.shared.prewarm(presetManager: presetManager)
        beginLANActivity()

        let server = ControlServer(
            preferredPort: UInt16(clamping: apiCfg.lanPort),
            maxPortProbes: 10,
            bindScope: .anyInterface,
            handler: wrapWithAuth(token: nil, handler: handlers.makeHandler())
        )
        server.healthFailureHandler = { [weak self] in
            DispatchQueue.main.async { self?.restartLANServer(enabled: true) }
        }
        self.lanServer = server

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch server.start(timeout: 2.0) {
            case .success(let port):
                LoggerContext.shared.info("ControlServer",
                                          "LAN started on 0.0.0.0:\(port)")
                DispatchQueue.main.async {
                    self?.bonjour.start(port: Int(port))
                    self?.setupStatusItem()
                    self?.refreshDeviceSendWindowIfOpen()
                }
            case .failure(let err):
                LoggerContext.shared.error("ControlServer",
                                           "LAN failed to start",
                                           ["error": String(describing: err)])
            }
        }
    }

    private func restartLANServer(enabled: Bool) {
        guard let server = lanServer else {
            if enabled { startLANServer() }
            return
        }
        server.stop { [weak self] in
            DispatchQueue.main.async {
                self?.lanServer = nil
                self?.bonjour.stop()
                self?.setupStatusItem()
                self?.refreshDeviceSendWindowIfOpen()
                guard enabled else {
                    EphemeralLANTokenStore.shared.revoke()
                    self?.endLANActivity()
                    return
                }
                self?.startLANServer()
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

        // Read the array of panels and display initially. After migration to Phase 3, there is only one.
        if let configPanels = presetManager.appConfig?.panels {
            // Preload presets referenced by each panel and cache them.
            // Avoid jitter due to disk I/O during the first draw of ContentHostView.
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

        // Monitor the differences in appConfig.panels.
        // When added/removed from the Settings screen, Control API, and menu bar,
        // NSWindow automatically follows via any path.
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

    /// Match the group of NSWindows in PanelManager to `appConfig.panels` as the true source.
    /// Added ID is `openNew`, removed ID is `close`.
    /// change in frame, opacity, and preset does not recreate the NSWindow but passes it through unchanged.
    /// These are reflected by separate APIs, so nothing is done in reconcile.
    private func reconcilePanels(_ panels: [PanelConfig]) {
        guard let manager = panelManager else { return }
        let newIDs = Set(panels.map(\.id))

        // Add: Existing (lastReconciledPanelIDs) without id opens new.
        for panel in panels where !lastReconciledPanelIDs.contains(panel.id) {
            // For safety's sake, perform a warm-up with preset before displaying the window.
            _ = presetManager.preset(named: panel.presetName)
            manager.openNew(config: panel)
        }
        // Delete: Existing ones that were not in the new ID set are closed.
        for id in lastReconciledPanelIDs.subtracting(newIDs) {
            manager.close(id: id)
        }
        lastReconciledPanelIDs = newIDs
        // Also follow the list in the menu bar.
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            // Phase 5: LAN open is a red symbol with tooltip for visual warning.
            // When off, return to template image (system theme follows).
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

    /// Generate a common menu used by the status bar and right-click mini-icon.

    @objc func openSettings() {
        SettingsWindowController.shared.show(presetManager: presetManager)
    }

    @objc func openAIIntegration() {
        AIIntegrationWindowController.shared.show(presetManager: presetManager)
    }

    /// Phase 5: The @objc selector entry for the menu bar "📱 Sending to Device..."
    /// Menu-based display of the active preset without specifying a panelID.
    @objc func openDeviceSendFromMenu() {
        openDeviceSend(panelID: nil)
    }

    /// Phase 5: Shared between menu bar and each floating panel's QR button
    /// actual entity
    /// Parameter panelID: When called from a floating panel, the panel of that
    /// Embed `presetName` into the URL to create a "QR for this panel only".
    /// When `nil` (= via menu), do not embed the preset, and the Web Panel is
    /// Display active preset.

    @objc func setOpacity(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let value = num.doubleValue
        // Phase 3 Migration Period: The transparency of the menu bar affects the primary panel (panels[0]).
        presetManager.setOpacity(value)
        if let id = primaryPanelID {
            panelManager?.setOpacity(id: id, opacity: value)
        }
        setupStatusItem()  // Redraw check state
    }

    @objc func setAgentMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AgentMode(rawValue: raw) else { return }
        presetManager.setAgentMode(mode)
        setupStatusItem()  // Redraw check state
    }

    @objc func toggleControlAPI() {
        let current = presetManager.appConfig?.controlAPI.enabled ?? false
        presetManager.setControlAPIEnabled(!current)
        setupStatusItem()  // Redraw check state
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Write back the current frames of all panels in ID units and persist to config.json.
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
        acpServer?.stop()
        lanServer?.stop()
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
        // Menu bar reconstruction
        setupStatusItem()
    }

    // MARK: - Phase 3: Panel menu actions

    /// Add a new panel with the same preset name as the primary.
    /// The creation of NSWindow is automatically handled by the sink of `panelsReconcileCancellable`.
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

    /// Menu bar panel list click: Toggle display of corresponding panel.
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

    /// "Close and delete panel definition": Remove the panel definition from settings. The destruction of NSWindow is
    /// Reconcile sink performs updates automatically, so here we only update the configuration.
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
