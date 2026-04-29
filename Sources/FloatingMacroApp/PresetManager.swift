import Foundation
import FloatingMacroCore

/// User-facing summary of a preset on disk: the file ID (`name`) and the
/// human-readable label (`displayName`). UI code should iterate over these
/// rather than calling `listPresets()` and looking up display names by hand.
struct PresetEntry: Identifiable, Equatable {
    let name: String
    let displayName: String
    var id: String { name }
}

final class PresetManager: ObservableObject {
    @Published var currentPreset: Preset?
    @Published var appConfig: AppConfig?
    @Published var errorMessage: String?
    /// Cached list of (name, displayName) pairs for the preset directory.
    /// Refreshed on create / delete / rename and on initial load. UI binds
    /// to this so SwiftUI re-renders the picker when the set changes.
    @Published var presetEntries: [PresetEntry] = []
    /// True if the macOS Accessibility permission is currently granted to
    /// this binary. Polled (not pushed) because there is no notification
    /// when the user toggles the permission. Drives a persistent panel
    /// banner so the user notices the silent-failure state where logs say
    /// "Text injected" but CGEvent.post is dropped at the OS level.
    @Published var accessibilityTrusted: Bool = AccessibilityChecker.isTrusted(prompt: false)
    private var accessibilityPollTimer: Timer?
    /// Monotonic counter used to request the SF Symbol picker sheet from
    /// outside SwiftUI (e.g. from the control API). Any view that wants to
    /// react observes this and opens the picker on value change.
    @Published var sfPickerRequestNonce: Int = 0

    /// Monotonic counter for requesting the app icon picker sheet.
    @Published var appIconPickerRequestNonce: Int = 0

    /// Request the SettingsView to programmatically select a button. Set by
    /// SettingsWindowController.show(selectButtonId:) or by code paths that
    /// want to jump straight to "edit this particular button". Consumed by
    /// SettingsView, which clears it back to nil.
    @Published var externalSelectButtonRequest: String? = nil
    @Published var externalSelectGroupRequest: String? = nil

    /// Request to change the action type in ButtonEditor.
    /// Set to a value like "text", "key", "launch", "terminal" to trigger the change.
    @Published var externalActionTypeRequest: String? = nil

    private let loader: ConfigLoader
    private let writer: ConfigWriter
    private var directoryWatcher: PresetDirectoryWatcher?

    /// Monotonic token for the currently-displayed transient error. A new
    /// error increments this so a previously-scheduled clear cannot wipe out
    /// a fresher message.
    private var errorMessageNonce: Int = 0

    /// Set `errorMessage` and clear it after `seconds`. Use for one-shot
    /// failures (edit/CRUD/execute). Persistent failures should set
    /// `errorMessage` directly so they remain visible.
    func showTransientError(_ message: String, clearAfter seconds: TimeInterval = 4) {
        errorMessageNonce &+= 1
        let token = errorMessageNonce
        errorMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run { [weak self] in
                guard let self, self.errorMessageNonce == token else { return }
                self.errorMessage = nil
            }
        }
    }

    init() {
        self.loader = ConfigLoader()
        self.writer = ConfigWriter()
    }

    func loadInitialConfig() {
        // デフォルト設定がなければ作成
        do {
            try writer.writeDefaultConfigIfNeeded()
        } catch {
            errorMessage = "設定初期化に失敗: \(error.localizedDescription)"
        }

        // config.json 読み込み
        do {
            appConfig = try loader.loadAppConfig()
        } catch {
            appConfig = AppConfig()
        }

        // 同梱プリセット (MidJourney 用 / note.com ハッシュタグ等) を初回限り
        // ユーザーの presets/ にコピーする。同名ファイルが既にある場合は
        // 個別に skip するので、再インストールで残骸が残っているケースでも
        // ユーザーの編集を上書きしない。
        installSeedPresetsIfNeeded()

        // アクティブプリセット読み込み
        loadActivePreset()
        refreshPresetEntries()
        startDirectoryWatcher()
        startAccessibilityPolling()
    }

    /// First-run only: copy bundled seed presets into the user's
    /// directory and persist a `seedInstalled` marker on AppConfig so
    /// subsequent launches skip the pass. Errors are logged but never
    /// block app startup.
    private func installSeedPresetsIfNeeded() {
        guard var cfg = appConfig, cfg.seedInstalled == false else { return }
        let installer = SeedPresetInstaller()
        do {
            _ = try installer.install(force: false)
            cfg.seedInstalled = true
            try writer.saveAppConfig(cfg)
            appConfig = cfg
        } catch {
            LoggerContext.shared.error("PresetManager",
                "Seed install failed", ["error": String(describing: error)])
        }
    }

    /// Force-install bundled seed presets (e.g. user wiped MidJourney
    /// and wants the original back). Returns the (installed, skipped)
    /// pair. `force` overwrites existing files; the default false flag
    /// preserves user edits.
    @discardableResult
    func reinstallSeedPresets(force: Bool) -> SeedPresetInstaller.Result? {
        let installer = SeedPresetInstaller()
        do {
            let result = try installer.install(force: force)
            refreshPresetEntries()
            return result
        } catch {
            showTransientError("同梱プリセット再インストールに失敗: \(error.localizedDescription)")
            return nil
        }
    }

    /// Start watching the presets directory for external changes (Finder
    /// drag-and-drop, manual delete, etc.). Idempotent — safe to call
    /// Poll the OS Accessibility-trust state. There is no notification
    /// for grant/revoke transitions, so we sample on a coarse cadence —
    /// 3s is fast enough that a user toggling permission in System
    /// Settings sees the badge clear before they switch back.
    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0,
                                                      repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = AccessibilityChecker.isTrusted(prompt: false)
            if now != self.accessibilityTrusted {
                self.accessibilityTrusted = now
                LoggerContext.shared.info("Accessibility",
                    "trust state changed", ["trusted": String(now)])
            }
        }
    }

    /// multiple times during config reload.
    private func startDirectoryWatcher() {
        directoryWatcher?.stop()
        // Ensure the directory exists so open() succeeds. ensureDirectories
        // is also called by writeDefaultConfigIfNeeded but we play safe.
        try? loader.ensureDirectories()
        let watcher = PresetDirectoryWatcher(path: loader.presetsURL.path) { [weak self] in
            self?.handleDirectoryChange()
        }
        watcher.start()
        directoryWatcher = watcher
    }

    /// Called when the watcher detects a filesystem change. Re-scans the
    /// directory and falls back to `default` if the active preset's file
    /// disappeared (e.g. Finder delete).
    private func handleDirectoryChange() {
        refreshPresetEntries()
        if let active = appConfig?.activePreset,
           !presetEntries.contains(where: { $0.name == active }) {
            appConfig?.activePreset = "default"
            if let c = appConfig { try? writer.saveAppConfig(c) }
            loadActivePreset()
        } else {
            loadActivePreset()
        }
    }

    /// Re-scan the presets directory and refresh `presetEntries`. Loading
    /// each file just to extract `displayName` is acceptable for the
    /// expected preset count (tens, not thousands); cache invalidation on
    /// create / delete / rename keeps the UI in sync.
    func refreshPresetEntries() {
        let names = (try? loader.listPresets()) ?? []
        presetEntries = names.map { name in
            let display = (try? loader.loadPreset(name: name).displayName) ?? name
            return PresetEntry(name: name, displayName: display)
        }
    }

    /// Smallest unused `preset-N` (N starting at 1). Skips holes so that
    /// re-installs with leftover files still pick up clean numbering.
    func nextPresetName() -> String {
        let existing = Set(listPresets())
        var n = 1
        while existing.contains("preset-\(n)") {
            n += 1
        }
        return "preset-\(n)"
    }

    func loadActivePreset() {
        guard let config = appConfig else { return }
        do {
            currentPreset = try loader.loadPreset(name: config.activePreset)
        } catch {
            errorMessage = "プリセット読み込みに失敗: \(config.activePreset)"
        }
    }

    func listPresets() -> [String] {
        (try? loader.listPresets()) ?? []
    }

    func switchPreset(to name: String) {
        appConfig?.activePreset = name
        if let config = appConfig {
            try? writer.saveAppConfig(config)
        }
        loadActivePreset()
    }

    /// Public trigger used by the control API.
    func requestSFPicker() {
        sfPickerRequestNonce &+= 1
    }

    /// Public trigger for requesting the app icon picker sheet.
    func requestAppIconPicker() {
        appIconPickerRequestNonce &+= 1
    }

    /// Monotonic counter used to dismiss any open picker sheet.
    @Published var dismissPickerNonce: Int = 0

    /// Public trigger to close whichever picker sheet is currently open.
    func requestDismissPicker() {
        dismissPickerNonce &+= 1
    }

    // MARK: - External color / commit requests

    /// Carries a color request from the control API to the active editor.
    /// `hex` = nil means "disable the color toggle".
    struct ColorRequest: Equatable {
        let hex: String?
        let nonce: Int
    }

    @Published var externalBackgroundColorRequest: ColorRequest? = nil
    @Published var externalTextColorRequest: ColorRequest? = nil

    /// Monotonic counter that tells the active editor to call commit().
    @Published var commitNonce: Int = 0

    func requestSetBackgroundColor(hex: String?) {
        externalBackgroundColorRequest = ColorRequest(hex: hex, nonce: (externalBackgroundColorRequest?.nonce ?? 0) &+ 1)
    }

    func requestSetTextColor(hex: String?) {
        externalTextColorRequest = ColorRequest(hex: hex, nonce: (externalTextColorRequest?.nonce ?? 0) &+ 1)
    }

    func requestCommit() {
        commitNonce &+= 1
    }

    // MARK: - External key combo / action value requests

    struct KeyComboRequest: Equatable {
        let combo: String   // e.g. "cmd+shift+v"
        let nonce: Int
    }

    struct ActionValueRequest: Equatable {
        let type: String    // "text" | "launch" | "terminal"
        let value: String
        let nonce: Int
    }

    @Published var externalKeyComboRequest: KeyComboRequest? = nil
    @Published var externalActionValueRequest: ActionValueRequest? = nil

    func requestSetKeyCombo(combo: String) {
        externalKeyComboRequest = KeyComboRequest(
            combo: combo,
            nonce: (externalKeyComboRequest?.nonce ?? 0) &+ 1
        )
    }

    func requestSetActionValue(type: String, value: String) {
        externalActionValueRequest = ActionValueRequest(
            type: type, value: value,
            nonce: (externalActionValueRequest?.nonce ?? 0) &+ 1
        )
    }

    /// Monotonic counter used to clear the button/group selection in Settings,
    /// which closes the ButtonEditor / GroupEditor detail pane.
    @Published var clearSelectionNonce: Int = 0

    /// Public trigger to deselect the current button/group in the Settings window.
    func requestClearSelection() {
        clearSelectionNonce &+= 1
    }

    func setAgentMode(_ mode: AgentMode) {
        guard var cfg = appConfig else { return }
        cfg.controlAPI.agentMode = mode
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    func setControlAPIEnabled(_ enabled: Bool) {
        guard var cfg = appConfig else { return }
        cfg.controlAPI.enabled = enabled
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    func setControlAPIPort(_ port: Int) {
        guard var cfg = appConfig else { return }
        cfg.controlAPI.port = max(1024, min(65535, port))
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    /// Clamped to [0.25, 1.0] so users can't make the panel fully invisible.
    func setOpacity(_ value: Double) {
        guard var cfg = appConfig else { return }
        cfg.window.opacity = max(0.25, min(1.0, value))
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    /// Persist panel geometry so the window reopens where the user left it.
    /// Called on applicationWillTerminate and opportunistically after moves.
    func setPanelFrame(x: Double, y: Double, width: Double, height: Double) {
        guard var cfg = appConfig else { return }
        cfg.window.x = x
        cfg.window.y = y
        cfg.window.width = max(120, width)
        cfg.window.height = max(80, height)
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    // MARK: - Preset / group / button editing

    /// Apply a transform to the currently-active preset and persist.
    /// Errors bubble through `errorMessage` for the GUI, and the function
    /// returns whether the edit succeeded so HTTP callers can report it.
    @discardableResult
    func editActivePreset(_ transform: (Preset) throws -> Preset) -> Bool {
        guard let preset = currentPreset else { return false }
        do {
            let next = try transform(preset)
            try writer.savePreset(next)
            currentPreset = next
            return true
        } catch {
            showTransientError("編集に失敗: \(error.localizedDescription)")
            return false
        }
    }

    func addGroup(_ group: ButtonGroup) -> Bool {
        editActivePreset { try PresetEditor.addGroup(group, to: $0) }
    }

    func updateGroup(id: String, label: String? = nil,
                      icon: String?? = nil, iconText: String?? = nil,
                      backgroundColor: String?? = nil, textColor: String?? = nil,
                      tooltip: String?? = nil, collapsed: Bool? = nil) -> Bool {
        editActivePreset { preset in
            try PresetEditor.updateGroup(groupId: id, in: preset) { g in
                g.patch(label: label, icon: icon, iconText: iconText,
                        backgroundColor: backgroundColor, textColor: textColor,
                        tooltip: tooltip, collapsed: collapsed)
            }
        }
    }

    func deleteGroup(id: String) -> Bool {
        editActivePreset { try PresetEditor.deleteGroup(groupId: id, from: $0) }
    }

    func addButton(_ button: ButtonDefinition, toGroupId: String) -> Bool {
        editActivePreset { try PresetEditor.addButton(button, toGroupId: toGroupId, in: $0) }
    }

    func updateButton(id: String,
                      label: String?,
                      icon: String??,
                      iconText: String??,
                      backgroundColor: String??,
                      textColor: String??,
                      width: Double??,
                      height: Double??,
                      tooltip: String??,
                      action: Action?) -> Bool {
        editActivePreset { preset in
            try PresetEditor.updateButton(buttonId: id, in: preset) { b in
                b.patch(label: label,
                        icon: icon,
                        iconText: iconText,
                        backgroundColor: backgroundColor,
                        textColor: textColor,
                        width: width,
                        height: height,
                        tooltip: tooltip,
                        action: action)
            }
        }
    }

    func deleteButton(id: String) -> Bool {
        editActivePreset { try PresetEditor.deleteButton(buttonId: id, from: $0) }
    }

    /// Duplicate a button in-place. The copy is appended to the same group,
    /// gets a fresh id, and has " copy" appended to the label. Returns the
    /// new button's id if the operation succeeded, nil otherwise.
    @discardableResult
    func duplicateButton(id: String) -> String? {
        guard let preset = currentPreset else { return nil }
        // Find the source button and its group.
        var sourceGroup: ButtonGroup?
        var sourceButton: ButtonDefinition?
        for group in preset.groups {
            if let b = group.buttons.first(where: { $0.id == id }) {
                sourceGroup = group
                sourceButton = b
                break
            }
        }
        guard let group = sourceGroup, let src = sourceButton else { return nil }

        let newId = "b-\(Int.random(in: 10000...99999))"
        let copy = ButtonDefinition(
            id: newId,
            label: "\(src.label) のコピー",
            icon: src.icon,
            iconText: src.iconText,
            backgroundColor: src.backgroundColor,
            width: src.width,
            height: src.height,
            tooltip: src.tooltip,
            action: src.action
        )
        let ok = addButton(copy, toGroupId: group.id)
        return ok ? newId : nil
    }

    func reorderButtons(ids: [String], inGroupId: String) -> Bool {
        editActivePreset {
            try PresetEditor.reorderButtons(ids: ids, inGroupId: inGroupId, in: $0)
        }
    }

    func moveButton(id: String, toGroupId: String, at position: Int?) -> Bool {
        editActivePreset {
            try PresetEditor.moveButton(buttonId: id, toGroupId: toGroupId,
                                        at: position, in: $0)
        }
    }

    /// Create a new empty preset file. Refuses to overwrite an existing
    /// file — callers that want a fresh internal id should pass
    /// `nextPresetName()`.
    func createPreset(name: String, displayName: String) -> Bool {
        let url = loader.presetsURL.appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: url.path) {
            showTransientError("プリセット作成に失敗: \(name) は既に存在します")
            return false
        }
        let preset = Preset(name: name, displayName: displayName, groups: [])
        do {
            try writer.savePreset(preset)
            refreshPresetEntries()
            return true
        } catch {
            showTransientError("プリセット作成に失敗: \(error.localizedDescription)")
            return false
        }
    }

    func renamePreset(name: String, displayName: String) -> Bool {
        guard let p = (try? loader.loadPreset(name: name)) else { return false }
        let next = PresetEditor.renameDisplayName(displayName, of: p)
        do {
            try writer.savePreset(next)
            if currentPreset?.name == name { currentPreset = next }
            refreshPresetEntries()
            return true
        } catch {
            showTransientError("プリセット名変更に失敗: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Export / Import

    /// Encode a single preset as JSON bytes for export. Returns nil if the
    /// preset cannot be loaded.
    func exportPresetData(name: String) -> Data? {
        guard let preset = try? loader.loadPreset(name: name) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(preset)
    }

    /// Encode every preset as a `PresetBundle` JSON for backup or
    /// distribution. The `default` preset is included.
    func exportAllPresetsData() -> Data? {
        let names = (try? loader.listPresets()) ?? []
        let presets = names.compactMap { try? loader.loadPreset(name: $0) }
        let bundle = PresetBundle(presets: presets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(bundle)
    }

    /// Import one or more presets from a JSON file. Auto-detects whether
    /// the file is a single `Preset` or a `PresetBundle`. Each imported
    /// preset gets a fresh internal id via `nextPresetName()` so existing
    /// files are never overwritten. Returns the number of imported presets.
    @discardableResult
    func importPresets(from url: URL) -> Int {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: url) else {
            showTransientError("インポートに失敗: ファイルを読み込めません")
            return 0
        }
        let presets: [Preset]
        if let bundle = try? decoder.decode(PresetBundle.self, from: data) {
            presets = bundle.presets
        } else if let single = try? decoder.decode(Preset.self, from: data) {
            presets = [single]
        } else {
            showTransientError("インポートに失敗: JSON 形式が不正です")
            return 0
        }
        var imported = 0
        for source in presets {
            let newName = nextPresetName()
            let copy = Preset(
                version: source.version,
                name: newName,
                displayName: source.displayName,
                groups: source.groups
            )
            do {
                try writer.savePreset(copy)
                imported += 1
            } catch {
                LoggerContext.shared.error("PresetManager",
                    "Failed to save imported preset",
                    ["name": newName, "error": String(describing: error)])
            }
        }
        if imported > 0 { refreshPresetEntries() }
        return imported
    }

    func deletePreset(name: String) -> Bool {
        let url = loader.presetsURL.appendingPathComponent("\(name).json")
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            showTransientError("プリセット削除に失敗: \(error.localizedDescription)")
            return false
        }
        if appConfig?.activePreset == name {
            appConfig?.activePreset = "default"
            if let c = appConfig { try? writer.saveAppConfig(c) }
            loadActivePreset()
        }
        refreshPresetEntries()
        return true
    }

    func executeButton(_ button: ButtonDefinition) {
        let blacklist = appConfig?.commandBlacklist
        Task.detached {
            do {
                let onBlocked: MacroRunner.BlockedCommandHandler = { pattern, text in
                    await MainActor.run {
                        CommandConfirmation.askProceed(pattern: pattern, text: text)
                    }
                }
                try await Self.executeAction(button.action, blacklist: blacklist, onBlocked: onBlocked)
            } catch {
                let msg: String
                if case ActionError.commandBlocked(let pattern) = error {
                    msg = "\(button.label) — キャンセル: 禁止パターン「\(pattern)」"
                } else {
                    msg = "\(button.label) 実行失敗: \(error)"
                }
                await MainActor.run {
                    self.showTransientError(msg, clearAfter: 3)
                }
            }
        }
    }

    func setCommandBlacklistEnabled(_ enabled: Bool) {
        guard var cfg = appConfig else { return }
        cfg.commandBlacklist.enabled = enabled
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    func setCommandBlacklistPatterns(_ patterns: [String]) {
        guard var cfg = appConfig else { return }
        cfg.commandBlacklist.patterns = patterns
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    /// Enables autopilot mode after verifying the passphrase.
    /// Returns `false` if the passphrase is wrong or no password is set.
    @discardableResult
    func enableAutopilot(passphrase: String) -> Bool {
        guard var cfg = appConfig,
              let storedHash = cfg.commandBlacklist.autopilotPasswordHash else { return false }
        guard CommandConfirmation.verify(passphrase: passphrase, against: storedHash) else { return false }
        cfg.commandBlacklist.autopilotEnabled = true
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
        return true
    }

    func disableAutopilot() {
        guard var cfg = appConfig else { return }
        cfg.commandBlacklist.autopilotEnabled = false
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    /// Sets or changes the autopilot passphrase. Requires the old passphrase
    /// when one is already stored. Pass `nil` for `oldPassphrase` when setting
    /// for the first time.
    /// Returns `false` if `oldPassphrase` verification fails.
    @discardableResult
    func setAutopilotPassword(oldPassphrase: String?, newPassphrase: String) -> Bool {
        guard var cfg = appConfig else { return false }
        if let storedHash = cfg.commandBlacklist.autopilotPasswordHash {
            // A password is already set — require the old one.
            guard let old = oldPassphrase,
                  CommandConfirmation.verify(passphrase: old, against: storedHash) else { return false }
        }
        cfg.commandBlacklist.autopilotPasswordHash = CommandConfirmation.hash(newPassphrase)
        // Disable autopilot when password changes so the user must re-enable.
        cfg.commandBlacklist.autopilotEnabled = false
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
        return true
    }

    private static func executeAction(_ action: Action,
                                      blacklist: CommandBlacklist?,
                                      onBlocked: MacroRunner.BlockedCommandHandler?) async throws {
        // Blacklist check for direct terminal/text actions.
        // MacroRunner handles sub-actions of .macro via the same onBlocked closure.
        if let bl = blacklist, !bl.autopilotEnabled {
            switch action {
            case .terminal(_, let command, _, _, _):
                if let pattern = CommandGuard.check(command, against: bl) {
                    if let handler = onBlocked {
                        let proceed = await handler(pattern, command)
                        if !proceed { throw ActionError.commandBlocked(pattern: pattern) }
                    } else {
                        throw ActionError.commandBlocked(pattern: pattern)
                    }
                }
            case .text(let content, _, _):
                if let pattern = CommandGuard.check(content, against: bl) {
                    if let handler = onBlocked {
                        let proceed = await handler(pattern, content)
                        if !proceed { throw ActionError.commandBlocked(pattern: pattern) }
                    } else {
                        throw ActionError.commandBlocked(pattern: pattern)
                    }
                }
            default: break
            }
        }

        switch action {
        case .key(let combo):
            let kc = try KeyCombo.parse(combo)
            try KeyActionExecutor.execute(kc)

        case .text(let content, let pasteDelayMs, let restoreClipboard):
            try TextActionExecutor.execute(
                content: content, pasteDelayMs: pasteDelayMs,
                restoreClipboard: restoreClipboard
            )

        case .launch(let target):
            try LaunchActionExecutor.execute(target: target)

        case .terminal(let app, let command, let newWindow, let execute, let profile):
            try TerminalActionExecutor.execute(
                app: app, command: command, newWindow: newWindow,
                execute: execute, profile: profile
            )

        case .delay(let ms):
            try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)

        case .macro(let actions, let stopOnError):
            try await MacroRunner.run(actions: actions, stopOnError: stopOnError,
                                      blacklist: blacklist, onBlocked: onBlocked)
        }
    }
}
