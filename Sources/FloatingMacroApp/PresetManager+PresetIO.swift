import Foundation
import AppKit
import FloatingMacroCore

extension PresetManager {

    /// Re-scan the presets directory and refresh `presetEntries`. Loading
    /// each file just to extract `displayName` is acceptable for the
    /// expected preset count (tens, not thousands); cache invalidation on
    /// create / delete / rename keeps the UI in sync.
    ///
    /// The display order is composed from `appConfig.presetOrder` first
    /// (filtering out any names that no longer exist on disk), then any
    /// names not in that list appended in alphabetical order. This keeps
    /// externally added presets (Finder drop, manual file copy) visible
    /// without losing the user's explicit ordering.
    /// If the on-disk order needed normalization (stale or missing entries),
    /// `appConfig.presetOrder` is self-healed and persisted.
    func refreshPresetEntries() {
        let onDisk = (try? loader.listPresets()) ?? []
        let onDiskSet = Set(onDisk)
        let saved = appConfig?.presetOrder ?? []

        var ordered: [String] = []
        var seen = Set<String>()
        for name in saved where onDiskSet.contains(name) && !seen.contains(name) {
            ordered.append(name)
            seen.insert(name)
        }
        for name in onDisk.sorted() where !seen.contains(name) {
            ordered.append(name)
            seen.insert(name)
        }

        presetEntries = ordered.map { name in
            let display = (try? loader.loadPreset(name: name).displayName) ?? name
            return PresetEntry(name: name, displayName: display)
        }

        // Self-heal: persist the normalized order if it diverged from what was
        // saved (stale entries removed, externally added presets appended).
        if var cfg = appConfig, cfg.presetOrder != ordered {
            cfg.presetOrder = ordered
            appConfig = cfg
            try? writer.saveAppConfig(cfg)
        }
    }

    /// Persist a new preset display order. Names not present on disk are
    /// dropped; missing-on-disk names are appended in alphabetical order so
    /// the saved order always reflects reality. Returns true on success.
    @discardableResult
    func reorderPresets(ids: [String]) -> Bool {
        guard var cfg = appConfig else { return false }
        let onDisk = Set((try? loader.listPresets()) ?? [])
        var normalized: [String] = []
        var seen = Set<String>()
        for name in ids where onDisk.contains(name) && !seen.contains(name) {
            normalized.append(name)
            seen.insert(name)
        }
        for name in onDisk.sorted() where !seen.contains(name) {
            normalized.append(name)
            seen.insert(name)
        }
        cfg.presetOrder = normalized
        do {
            try writer.saveAppConfig(cfg)
            appConfig = cfg
            refreshPresetEntries()
            return true
        } catch {
            showTransientError(L_("preset_reorder_failed", error.localizedDescription))
            return false
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

    /// Introduced in Phase 3. On-demand cache for displaying multiple panels with separate presets.
    /// One preset may be shared among multiple panels, and editing (editActivePreset)
    /// When updated, all ContentHostViews in all panels will be immediately redrawn via @Published.

    /// Reload preset content from disk. Phase 3 (v0.12) multiple panels are
    /// To display separate presets, not only `activePreset` but also `loadedPresets`
    /// Reload all entries. `currentPreset` (edit target) is its own
    /// Replace with an instance reloaded under the same name. This is
    /// more, edit presets other than panels[0], save, directory watcher is
    /// When fire is called, currentPreset automatically switches to the preset of panels[0].
    /// To prevent the edit button from being lost in overwritten phase 3 bug.
    func loadActivePreset() {
        guard let config = appConfig else { return }
        // reloadTarget = (current cache name) ∪ (panels[*].presetName) ∪ (activePreset)。
        var names: Set<String> = Set(loadedPresets.keys)
        names.insert(config.activePreset)
        for panel in config.panels { names.insert(panel.presetName) }
        if let curName = currentPreset?.name { names.insert(curName) }

        var newCache: [String: Preset] = [:]
        var loadFailures: [String] = []
        for name in names {
            if let p = try? loader.loadPreset(name: name) {
                newCache[name] = p
            } else {
                loadFailures.append(name)
            }
        }
        loadedPresets = newCache

        // The edit target (currentPreset) is replaced with its name in the new disk content.
        // If the name itself has disappeared, fall back to `activePreset`.
        if let curName = currentPreset?.name, let reloaded = newCache[curName] {
            currentPreset = reloaded
        } else if let p = newCache[config.activePreset] {
            currentPreset = p
        } else {
            currentPreset = nil
        }

        // If there is a failure, leave it as a transient error and show a persistent banner if currentPreset is nil.
        if !loadFailures.isEmpty && currentPreset == nil {
            errorMessage = L_("preset_load_failed", loadFailures.joined(separator: ", "))
        }
    }

    /// Return the preset with the specified name from the cache, otherwise load it from disk.
    /// Store in cache. Return nil if loading fails (errors are not handled).
    /// Do not display the error message - for frequent lookups during multi-panel drawing
    /// To avoid the banner flashing (to prevent this).
    func preset(named name: String) -> Preset? {
        if let cached = loadedPresets[name] { return cached }
        do {
            let p = try loader.loadPreset(name: name)
            loadedPresets[name] = p
            return p
        } catch {
            return nil
        }
    }

    /// Returns the preset currently displayed by the specified panel. Used for drawing multiple panels.
    func panelPreset(forPanelID id: String) -> Preset? {
        guard let cfg = appConfig,
              let panel = cfg.panels.first(where: { $0.id == id }) else { return nil }
        return preset(named: panel.presetName)
    }

    func listPresets() -> [String] {
        (try? loader.listPresets()) ?? []
    }

    /// Switch preset of primary panel (panels[0]).
    /// Phase 3 migration period is transferred internally to `switchPanelPreset(primary)`, and `currentPreset`
    /// Edit target should also be synchronized. New code recommended to directly use `switchPanelPreset`.
    func switchPreset(to name: String) {
        guard let primaryID = appConfig?.panels.first?.id else { return }
        switchPanelPreset(panelID: primaryID, to: name)
    }

    /// Switch to persistently save the preset displayed by the specified panel. Primary panel.
    /// Switching to (panels[0]) will result in legacy activePreset and currentPreset.
    /// The editing target synchronizes.
    func switchPanelPreset(panelID: String, to name: String) {
        guard let cfg = appConfig else { return }
        let next = cfg.settingPanelPreset(id: panelID, presetName: name)
        appConfig = next
        try? writer.saveAppConfig(next)
        // Load preset content into cache. Used for both panel drawing and editing.
        if let preset = preset(named: name) {
            loadedPresets[name] = preset
            // When switching to the primary panel, `currentPreset` (edit target) also follows.
            if panelID == next.panels.first?.id {
                currentPreset = preset
            }
        }
    }

    /// Edit target (currentPreset / SettingsWindow) to preset of specified panel
    /// Switch. In Phase 3, display multiple panels with different presets simultaneously.
    /// Hook to establish the flow for pressing the edit button of a specific panel.
    func setEditTarget(panelID: String) {
        guard let preset = panelPreset(forPanelID: panelID) else { return }
        currentPreset = preset
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

    /// Public trigger to close whichever picker sheet is currently open.
    func requestDismissPicker() {
        dismissPickerNonce &+= 1
    }

}
