import Foundation
import FloatingMacroCore

final class PresetManager: ObservableObject {
    @Published var currentPreset: Preset?
    @Published var appConfig: AppConfig?
    @Published var errorMessage: String?
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

        // アクティブプリセット読み込み
        loadActivePreset()
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
            errorMessage = "編集に失敗: \(error.localizedDescription)"
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

    /// Create a new empty preset file.
    func createPreset(name: String, displayName: String) -> Bool {
        let preset = Preset(name: name, displayName: displayName, groups: [])
        do {
            try writer.savePreset(preset)
            return true
        } catch {
            errorMessage = "プリセット作成に失敗: \(error.localizedDescription)"
            return false
        }
    }

    func renamePreset(name: String, displayName: String) -> Bool {
        guard let p = (try? loader.loadPreset(name: name)) else { return false }
        let next = PresetEditor.renameDisplayName(displayName, of: p)
        do {
            try writer.savePreset(next)
            if currentPreset?.name == name { currentPreset = next }
            return true
        } catch {
            errorMessage = "プリセット名変更に失敗: \(error.localizedDescription)"
            return false
        }
    }

    func deletePreset(name: String) -> Bool {
        let url = loader.presetsURL.appendingPathComponent("\(name).json")
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            errorMessage = "プリセット削除に失敗: \(error.localizedDescription)"
            return false
        }
        if appConfig?.activePreset == name {
            appConfig?.activePreset = "default"
            if let c = appConfig { try? writer.saveAppConfig(c) }
            loadActivePreset()
        }
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
                    self.errorMessage = msg
                }
                // 3秒後にクリア
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.errorMessage = nil
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
