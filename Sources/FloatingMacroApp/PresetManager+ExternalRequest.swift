import Foundation
import AppKit
import FloatingMacroCore

extension PresetManager {

    // MARK: - External color / commit requests

    /// Carries a color request from the control API to the active editor.
    /// `hex` = nil means "disable the color toggle".
    struct ColorRequest: Equatable {
        let hex: String?
        let nonce: Int
    }


    /// Monotonic counter that tells the active editor to call commit().

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

    func setControlAPILanPort(_ port: Int) {
        guard var cfg = appConfig else { return }
        let clamped = max(1024, min(65535, port))
        cfg.controlAPI.lanPort = clamped == cfg.controlAPI.port ? clamped + 1 : clamped
        appConfig = cfg
        try? writer.saveAppConfig(cfg)
    }

    /// Clamped to [0.25, 1.0] so users can't make the panel fully invisible.

}
