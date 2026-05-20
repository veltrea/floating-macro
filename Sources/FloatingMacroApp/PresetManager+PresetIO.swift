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

    /// Phase 3 で導入。複数パネルが別々のプリセットを表示するためのオンデマンドキャッシュ。
    /// 1 つのプリセットは複数パネルから共有される可能性があり、編集 (`editActivePreset`)
    /// で更新されたら全パネルの ContentHostView が即座に再描画されるよう @Published。

    /// Reload preset content from disk. Phase 3 (v0.12) では複数パネルが
    /// 別々のプリセットを表示するため、`activePreset` だけでなく `loadedPresets`
    /// の全エントリを再読込する。`currentPreset` (編集ターゲット) は自身の
    /// 名前を維持し、その名前で再読込されたインスタンスに差し替える。これに
    /// より、panels[0] 以外のプリセットを編集 → 保存 → directory watcher が
    /// fire したとき、currentPreset が panels[0] のプリセットに勝手に
    /// 上書きされて編集中ボタンが見失われる Phase 3 バグを防ぐ。
    func loadActivePreset() {
        guard let config = appConfig else { return }
        // 再読込対象 = (現在キャッシュ中の名前) ∪ (panels[*].presetName) ∪ (activePreset)。
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

        // 編集ターゲット (`currentPreset`) はその名前のまま、新しい disk 内容に差し替える。
        // 名前自体が消えていたら `activePreset` にフォールバック。
        if let curName = currentPreset?.name, let reloaded = newCache[curName] {
            currentPreset = reloaded
        } else if let p = newCache[config.activePreset] {
            currentPreset = p
        } else {
            currentPreset = nil
        }

        // 失敗があれば一過性エラーとして残す (currentPreset が nil なら永続バナー)。
        if !loadFailures.isEmpty && currentPreset == nil {
            errorMessage = L_("preset_load_failed", loadFailures.joined(separator: ", "))
        }
    }

    /// 指定名のプリセットをキャッシュから返し、無ければディスクから読み込んで
    /// キャッシュに格納する。読み込みに失敗したら nil を返す（エラーは
    /// `errorMessage` に出さない — 複数パネル描画中の頻繁なルックアップで
    /// バナーが点滅するのを避けるため）。
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

    /// 指定パネルが現在表示すべきプリセットを返す。複数パネル描画用。
    func panelPreset(forPanelID id: String) -> Preset? {
        guard let cfg = appConfig,
              let panel = cfg.panels.first(where: { $0.id == id }) else { return nil }
        return preset(named: panel.presetName)
    }

    func listPresets() -> [String] {
        (try? loader.listPresets()) ?? []
    }

    /// 旧 API: プライマリパネル (panels[0]) のプリセットを切り替える。
    /// Phase 3 移行期は内部で `switchPanelPreset(primary)` に転送し、`currentPreset`
    /// (編集ターゲット) も同期更新する。新コードは `switchPanelPreset` 直接利用推奨。
    func switchPreset(to name: String) {
        guard let primaryID = appConfig?.panels.first?.id else { return }
        switchPanelPreset(panelID: primaryID, to: name)
    }

    /// 指定パネルが表示するプリセットを切り替えて永続化。プライマリパネル
    /// (panels[0]) を切り替えた場合は legacy `activePreset` と `currentPreset`
    /// (編集ターゲット) も同期する。
    func switchPanelPreset(panelID: String, to name: String) {
        guard let cfg = appConfig else { return }
        let next = cfg.settingPanelPreset(id: panelID, presetName: name)
        appConfig = next
        try? writer.saveAppConfig(next)
        // プリセット内容をキャッシュに読み込む。パネル描画・編集どちらでも使われる。
        if let preset = preset(named: name) {
            loadedPresets[name] = preset
            // プライマリパネルを切り替えた場合は `currentPreset` (編集ターゲット) も追従。
            if panelID == next.panels.first?.id {
                currentPreset = preset
            }
        }
    }

    /// 編集ターゲット (`currentPreset` / SettingsWindow) を指定パネルのプリセットに
    /// 切り替える。Phase 3 で「複数パネルが違うプリセットを表示している状態で
    /// 特定パネルの編集ボタンを押す」フローを成立させるためのフック。
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
