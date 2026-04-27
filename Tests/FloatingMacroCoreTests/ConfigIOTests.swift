import XCTest
@testable import FloatingMacroCore

/// Exercises ConfigLoader / ConfigWriter against a real temp directory so the
/// file system contract is verified (paths, JSON shape, round-trip through
/// disk, error conditions). Each test gets its own fresh temp directory.
final class ConfigIOTests: XCTestCase {

    private var tempBase: URL!

    override func setUpWithError() throws {
        tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmcfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let base = tempBase, FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
        tempBase = nil
    }

    private func makeLoader() -> ConfigLoader { ConfigLoader(baseURL: tempBase) }
    private func makeWriter() -> ConfigWriter { ConfigWriter(baseURL: tempBase) }

    // MARK: - Directory scaffolding

    func testEnsureDirectoriesCreatesPresetsAndLogs() throws {
        let loader = makeLoader()
        try loader.ensureDirectories()

        let fm = FileManager.default
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: loader.presetsURL.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        isDir = false
        XCTAssertTrue(fm.fileExists(
            atPath: tempBase.appendingPathComponent("logs").path,
            isDirectory: &isDir
        ))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - writeDefaultConfigIfNeeded

    func testWriteDefaultConfigCreatesConfigAndDefaultPreset() throws {
        let writer = makeWriter()
        try writer.writeDefaultConfigIfNeeded()

        let loader = makeLoader()
        let config = try loader.loadAppConfig()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.activePreset, "default")

        let preset = try loader.loadPreset(name: "default")
        XCTAssertEqual(preset.name, "default")
        XCTAssertEqual(preset.groups.first?.buttons.first?.id, "btn-ultrathink")
    }

    func testWriteDefaultConfigIsIdempotent() throws {
        let writer = makeWriter()
        try writer.writeDefaultConfigIfNeeded()

        // Mutate the config on disk.
        let loader = makeLoader()
        var cfg = try loader.loadAppConfig()
        cfg.activePreset = "custom"
        try writer.saveAppConfig(cfg)

        // Second call must NOT overwrite.
        try writer.writeDefaultConfigIfNeeded()
        let reloaded = try loader.loadAppConfig()
        XCTAssertEqual(reloaded.activePreset, "custom",
                       "writeDefaultConfigIfNeeded must not overwrite existing user config")
    }

    // MARK: - Round-trip AppConfig

    func testAppConfigDiskRoundTrip() throws {
        let writer = makeWriter()
        let loader = makeLoader()
        try loader.ensureDirectories()

        let original = AppConfig(
            version: 1,
            activePreset: "dev",
            window: WindowConfig(x: 123, y: 456,
                                 width: 250, height: 420,
                                 orientation: "horizontal",
                                 alwaysOnTop: false,
                                 hideAfterAction: true,
                                 opacity: 0.5)
        )
        try writer.saveAppConfig(original)

        let loaded = try loader.loadAppConfig()
        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.window.width, 250)
        XCTAssertEqual(loaded.window.height, 420)
    }

    /// Backward-compatibility: configs written before width/height were
    /// introduced must still load, falling back to the defaults (200×300).
    func testAppConfigLoadsLegacyFileWithoutWidthOrHeight() throws {
        let loader = makeLoader()
        try loader.ensureDirectories()
        let legacy = #"""
        {
          "version": 1,
          "activePreset": "default",
          "window": {
            "x": 50, "y": 60,
            "orientation": "vertical",
            "alwaysOnTop": true,
            "hideAfterAction": false,
            "opacity": 0.8
          }
        }
        """#
        try legacy.data(using: .utf8)!.write(to: loader.configURL)

        let loaded = try loader.loadAppConfig()
        XCTAssertEqual(loaded.window.x, 50)
        XCTAssertEqual(loaded.window.y, 60)
        XCTAssertEqual(loaded.window.width, 200)
        XCTAssertEqual(loaded.window.height, 300)
        XCTAssertEqual(loaded.window.opacity, 0.8)
    }

    /// Brand-new configs must initialize with sensible defaults, including
    /// width/height.
    func testWindowConfigDefaults() {
        let w = WindowConfig()
        XCTAssertEqual(w.x, 100)
        XCTAssertEqual(w.y, 100)
        XCTAssertEqual(w.width, 200)
        XCTAssertEqual(w.height, 300)
        XCTAssertEqual(w.orientation, "vertical")
        XCTAssertTrue(w.alwaysOnTop)
        XCTAssertFalse(w.hideAfterAction)
        XCTAssertEqual(w.opacity, 1.0)
    }

    // MARK: - Round-trip Preset

    func testPresetDiskRoundTripWithMacroAction() throws {
        let writer = makeWriter()
        let loader = makeLoader()
        try loader.ensureDirectories()

        let preset = Preset(
            name: "writing",
            displayName: "執筆モード",
            groups: [
                ButtonGroup(
                    id: "g-paste",
                    label: "定型",
                    collapsed: false,
                    buttons: [
                        ButtonDefinition(
                            id: "b-macro",
                            label: "4面展開",
                            iconText: "🚀",
                            action: .macro(
                                actions: [
                                    .terminal(app: "iTerm", command: "cd ~ && ls",
                                              newWindow: true, execute: true, profile: nil),
                                    .delay(ms: 300),
                                    .key(combo: "cmd+n"),
                                ],
                                stopOnError: true
                            )
                        )
                    ]
                )
            ]
        )
        try writer.savePreset(preset)

        let loaded = try loader.loadPreset(name: "writing")
        XCTAssertEqual(loaded, preset)
    }

    // MARK: - listPresets

    func testListPresetsReturnsSortedJSONBasenames() throws {
        let writer = makeWriter()
        let loader = makeLoader()
        try loader.ensureDirectories()

        try writer.savePreset(Preset(name: "zeta", displayName: "Z", groups: []))
        try writer.savePreset(Preset(name: "alpha", displayName: "A", groups: []))
        try writer.savePreset(Preset(name: "mid", displayName: "M", groups: []))

        // Drop a non-JSON file that should be ignored.
        let junk = loader.presetsURL.appendingPathComponent("readme.txt")
        try "ignore me".write(to: junk, atomically: true, encoding: .utf8)

        let names = try loader.listPresets()
        XCTAssertEqual(names, ["alpha", "mid", "zeta"])
    }

    func testListPresetsEmptyWhenNoPresetsDirectory() throws {
        let loader = makeLoader()
        // No ensureDirectories() call — directory does not exist.
        let names = try loader.listPresets()
        XCTAssertEqual(names, [])
    }

    // MARK: - findButton

    func testFindButtonLocatesAcrossGroups() throws {
        let writer = makeWriter()
        let loader = makeLoader()
        try loader.ensureDirectories()

        let preset = Preset(
            name: "test",
            displayName: "test",
            groups: [
                ButtonGroup(id: "g1", label: "G1", buttons: [
                    ButtonDefinition(id: "b-one", label: "one", action: .key(combo: "a")),
                ]),
                ButtonGroup(id: "g2", label: "G2", buttons: [
                    ButtonDefinition(id: "b-two", label: "two", action: .key(combo: "b")),
                    ButtonDefinition(id: "b-three", label: "three", action: .key(combo: "c")),
                ]),
            ]
        )
        try writer.savePreset(preset)

        XCTAssertEqual(try loader.findButton(presetName: "test", buttonId: "b-one")?.label, "one")
        XCTAssertEqual(try loader.findButton(presetName: "test", buttonId: "b-three")?.label, "three")
        XCTAssertNil(try loader.findButton(presetName: "test", buttonId: "does-not-exist"))
    }

    // MARK: - Error paths

    func testLoadAppConfigThrowsWhenFileMissing() {
        let loader = makeLoader()
        XCTAssertThrowsError(try loader.loadAppConfig())
    }

    func testLoadPresetThrowsWhenFileMissing() {
        let loader = makeLoader()
        XCTAssertThrowsError(try loader.loadPreset(name: "nonexistent"))
    }

    func testLoadAppConfigThrowsOnCorruptJSON() throws {
        let loader = makeLoader()
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        let url = tempBase.appendingPathComponent("config.json")
        try "{ not-valid json".data(using: .utf8)!.write(to: url)

        XCTAssertThrowsError(try loader.loadAppConfig())
    }

    func testLoadPresetThrowsOnSchemaMismatch() throws {
        let loader = makeLoader()
        let writer = makeWriter()
        try loader.ensureDirectories()
        let url = loader.presetsURL.appendingPathComponent("bad.json")
        // Missing required 'name' field.
        try #"{"version":1,"displayName":"Bad","groups":[]}"#
            .data(using: .utf8)!.write(to: url)
        _ = writer // silence unused warning in case linker complains

        XCTAssertThrowsError(try loader.loadPreset(name: "bad"))
    }

    // MARK: - JSON pretty-printed + stable output

    func testPrettyPrintedOutput() throws {
        let writer = makeWriter()
        let loader = makeLoader()
        try loader.ensureDirectories()

        try writer.saveAppConfig(AppConfig())
        let data = try Data(contentsOf: loader.configURL)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\n"), "output should be pretty-printed (contains newlines)")
    }

    // MARK: - Atomic write should not leave half-written file

    func testAtomicWriteSurvivesInterruption() throws {
        // We can't truly interrupt mid-write in unit tests, but verify the
        // file is always parseable after save() returns.
        let writer = makeWriter()
        let loader = makeLoader()
        try loader.ensureDirectories()

        for i in 0..<20 {
            try writer.saveAppConfig(AppConfig(
                version: 1,
                activePreset: "p-\(i)",
                window: WindowConfig()
            ))
            let reloaded = try loader.loadAppConfig()
            XCTAssertEqual(reloaded.activePreset, "p-\(i)")
        }
    }

    // MARK: - Default base URL

    func testDefaultBaseURLPointsAtAppSupportByDefault() {
        // Skip if the test environment already sets the override (e.g. when
        // running inside the smoke-test harness).
        if ProcessInfo.processInfo.environment[ConfigLoader.configDirEnvVar] != nil {
            return
        }
        let url = ConfigLoader.defaultBaseURL
        XCTAssertTrue(url.path.contains("Library/Application Support/FloatingMacro"),
                      "defaultBaseURL must point into ~/Library/Application Support")
    }

    func testDefaultBaseURLEnvVarOverrideExpandsTilde() {
        // We can't safely mutate process env in a test without affecting
        // siblings, so just document the shape of the override path logic.
        let sample = "~/.fm-test-config"
        let expanded = NSString(string: sample).expandingTildeInPath
        XCTAssertFalse(expanded.hasPrefix("~"), "tilde expansion must resolve to an absolute path")
    }
}
