import AppKit
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
    ///
    /// 初期値は false。AccessibilityChecker.isTrusted を init 時に評価すると、
    /// AXIsProcessTrusted() の stale TRUE キャッシュ (prompt: true 呼出後や
    /// tccutil reset 後に短時間続く) を拾って「許可済み」と誤判定し、
    /// 起動直後だけバナーが消える事故が起きる。3 秒の polling サイクルで
    /// すぐ実値に追従するので、初期値 false で開始する方が安全。
    @Published var accessibilityTrusted: Bool = false
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

    let loader: ConfigLoader
    let writer: ConfigWriter
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
            errorMessage = L_("config_init_failed", error.localizedDescription)
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

        // v0.16: 個人プリセットの保存場所が ~/Library/Application Support/
        // FloatingMacro/presets/ から ~/Documents/FloatingMacro/presets/ に
        // 移った。動作上は両方マージして読まれるので即時に困ることはないが、
        // PC 引っ越しやバックアップ時に旧フォルダ (Library 配下で隠しがち) を
        // 見落とすとデータロスに繋がる。既存ユーザーには 1 回だけアラートで
        // 知らせ、新規ユーザーにはデフォルトで何も出さない。
        showMigrationAlertIfNeeded()

        // アクティブプリセット読み込み
        loadActivePreset()
        refreshPresetEntries()
        startDirectoryWatcher()
        startAccessibilityPolling()
    }

    /// One-shot v0.16 migration alert. See `AppConfig.migrationAlertShown`
    /// for the show-once gating.
    private func showMigrationAlertIfNeeded() {
        guard var cfg = appConfig, cfg.migrationAlertShown == false else { return }
        let bundledIDs = Set(SeedPresetInstaller.bundledSeedPresets().map { $0.name })
        let seedIDs = bundledIDs.union(["default"])
        let legacy = (try? loader.listSeedPresets()) ?? []
        let candidates = legacy.filter { !seedIDs.contains($0) }
        // No personal-looking presets in the legacy area → silently mark
        // shown so we never re-trigger.
        guard !candidates.isEmpty else {
            cfg.migrationAlertShown = true
            try? writer.saveAppConfig(cfg)
            appConfig = cfg
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let alert = NSAlert()
            alert.messageText = L("migration_title")
            alert.informativeText = L_("migration_body", candidates.count)
            alert.addButton(withTitle: L("migration_open_finder"))
            alert.addButton(withTitle: L("migration_later"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [self.loader.seedPresetsURL]
                )
            }
            cfg.migrationAlertShown = true
            try? self.writer.saveAppConfig(cfg)
            self.appConfig = cfg
        }
    }

    /// First-run only: copy bundled seed presets into the user's directory
    /// and persist a `seedInstalled` marker on AppConfig so subsequent
    /// launches skip the pass. Errors are logged but never block app
    /// startup.
    ///
    /// The bundled install runs synchronously so the panel is never empty.
    /// After it succeeds we kick off a background refresh against the
    /// public preset catalog (`github.com/veltrea/floating-macro-preset`)
    /// to overwrite the just-installed bundled copies with whatever newer
    /// revisions the catalog ships. The refresh is best-effort: offline
    /// users keep the bundled copies and notice nothing.
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
            return
        }
        refreshSeedsFromCatalogInBackground()
    }

    /// Background catalog refresh. Runs once after the bundled seed install
    /// on first launch. Any failure is logged and ignored — the bundled
    /// seeds already on disk remain valid. UI is refreshed on the main
    /// thread once the refresh finishes (the directory watcher would also
    /// catch this, but an explicit refresh avoids racing with it).
    private func refreshSeedsFromCatalogInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let installer = SeedPresetInstaller()
            let refreshed = installer.refreshFromCatalog()
            guard !refreshed.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshPresetEntries()
                self.loadActivePreset()
            }
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
            showTransientError(L_("seed_preset_reinstall_failed", error.localizedDescription))
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

    // MARK: - Stored properties moved from extensions (Swift requires)

    @Published var loadedPresets: [String: Preset] = [:]

    @Published var externalBackgroundColorRequest: ColorRequest? = nil
    @Published var externalTextColorRequest: ColorRequest? = nil

    /// Monotonic counter that tells the active editor to call commit().
    @Published var commitNonce: Int = 0

    @Published var externalKeyComboRequest: KeyComboRequest? = nil
    @Published var externalActionValueRequest: ActionValueRequest? = nil

    /// Monotonic counter used to clear the button/group selection in Settings.
    @Published var clearSelectionNonce: Int = 0

    /// Monotonic counter used to dismiss any open picker sheet.
    @Published var dismissPickerNonce: Int = 0

    /// Per-panel debouncers for scroll-position persistence.
    var scrollYSaveDebouncers: [String: DispatchWorkItem] = [:]

}
