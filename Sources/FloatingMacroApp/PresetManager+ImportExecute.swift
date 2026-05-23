import Foundation
import AppKit
import FloatingMacroCore

extension PresetManager {

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
            showTransientError(L("Failed to import: Unable to load file_cfb541"))
            return 0
        }
        let presets: [Preset]
        if let bundle = try? decoder.decode(PresetBundle.self, from: data) {
            presets = bundle.presets
        } else if let single = try? decoder.decode(Preset.self, from: data) {
            presets = [single]
        } else {
            showTransientError(L("Failed to import JSON format: Invalid JSON 6bbb96"))
            return 0
        }
        var imported = 0
        var importedNames: [String] = []
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
                importedNames.append(newName)
            } catch {
                LoggerContext.shared.error("PresetManager",
                    "Failed to save imported preset",
                    ["name": newName, "error": String(describing: error)])
            }
        }
        if imported > 0 {
            appendToPresetOrder(importedNames)
            refreshPresetEntries()
        }
        return imported
    }

    func deletePreset(name: String) -> Bool {
        let url = loader.presetsURL.appendingPathComponent("\(name).json")
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            showTransientError(L_("preset_delete_failed", error.localizedDescription))
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
                    msg = L_("button_cancelled_blocked_pattern", button.label, pattern)
                } else {
                    msg = L_("button_execution_failed", button.label, String(describing: error))
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
            case .text(let content, _, _, _):
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

        case .text(let content, let pasteDelayMs, let restoreClipboard, let appendMode):
            try TextActionExecutor.execute(
                content: content, pasteDelayMs: pasteDelayMs,
                restoreClipboard: restoreClipboard,
                appendMode: appendMode
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
