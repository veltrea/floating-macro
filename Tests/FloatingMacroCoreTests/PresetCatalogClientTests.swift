import XCTest
@testable import FloatingMacroCore

/// Local-only smoke tests for `PresetCatalogClient` and the catalog refresh
/// path of `SeedPresetInstaller`. The client treats the base URL opaquely,
/// so we point it at a temporary `file://` directory rather than spinning
/// up an HTTP server.
final class PresetCatalogClientTests: XCTestCase {

    private var catalogDir: URL!
    private var configDir:  URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        catalogDir = fm.temporaryDirectory.appendingPathComponent("fm-catalog-\(UUID().uuidString)")
        configDir  = fm.temporaryDirectory.appendingPathComponent("fm-config-\(UUID().uuidString)")
        try fm.createDirectory(at: catalogDir.appendingPathComponent("presets"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: configDir.appendingPathComponent("presets"),
                               withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: catalogDir)
        try? FileManager.default.removeItem(at: configDir)
    }

    // MARK: - Fixtures

    private func writeFixture() throws -> Preset {
        let preset = Preset(name: "midjourney", displayName: "MJ from catalog",
                            groups: [
                                ButtonGroup(id: "g1", label: "G1", buttons: [
                                    ButtonDefinition(id: "b1", label: "one",
                                                     action: .key(combo: "a")),
                                ]),
                            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let presetData = try encoder.encode(preset)
        try presetData.write(to: catalogDir.appendingPathComponent("presets/midjourney.json"))

        let indexJSON = """
        {
          "schemaVersion": 1,
          "defaults": ["midjourney"],
          "presets": [
            {
              "id": "midjourney",
              "displayName": "MJ from catalog",
              "summary": "smoke",
              "tags": ["t"],
              "file": "presets/midjourney.json"
            }
          ]
        }
        """
        try indexJSON.write(to: catalogDir.appendingPathComponent("index.json"),
                            atomically: true, encoding: .utf8)
        return preset
    }

    // MARK: - PresetCatalogClient

    func testFetchIndexDecodesSchema() throws {
        _ = try writeFixture()
        let client = PresetCatalogClient(baseURL: catalogDir, timeout: 3)
        let index = client.fetchIndex()
        XCTAssertNotNil(index)
        XCTAssertEqual(index?.schemaVersion, 1)
        XCTAssertEqual(index?.defaults, ["midjourney"])
        XCTAssertEqual(index?.presets.first?.id, "midjourney")
        XCTAssertEqual(index?.presets.first?.file, "presets/midjourney.json")
    }

    func testFetchPresetDecodesFile() throws {
        _ = try writeFixture()
        let client = PresetCatalogClient(baseURL: catalogDir, timeout: 3)
        let preset = client.fetchPreset(filePath: "presets/midjourney.json")
        XCTAssertEqual(preset?.name, "midjourney")
        XCTAssertEqual(preset?.displayName, "MJ from catalog")
    }

    func testFetchIndexReturnsNilOnUnreachableURL() {
        // Non-existent local directory — file:// fetch fails.
        let bogus = URL(fileURLWithPath: "/tmp/fm-nonexistent-\(UUID().uuidString)/")
        let client = PresetCatalogClient(baseURL: bogus, timeout: 1)
        XCTAssertNil(client.fetchIndex())
    }

    // MARK: - SeedPresetInstaller.refreshFromCatalog

    func testRefreshFromCatalogWritesPresetFile() throws {
        _ = try writeFixture()
        let client = PresetCatalogClient(baseURL: catalogDir, timeout: 3)
        let installer = SeedPresetInstaller(baseURL: configDir, catalogClient: client)

        let refreshed = installer.refreshFromCatalog()
        XCTAssertEqual(refreshed, ["midjourney"])

        let onDisk = configDir.appendingPathComponent("presets/midjourney.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: onDisk.path))

        let data = try Data(contentsOf: onDisk)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(decoded.displayName, "MJ from catalog")
    }

    func testRefreshFromCatalogIsBestEffortWhenIndexMissing() {
        // No fixture written → catalog returns nil → refresh skips silently.
        let bogus = URL(fileURLWithPath: "/tmp/fm-nonexistent-\(UUID().uuidString)/")
        let client = PresetCatalogClient(baseURL: bogus, timeout: 1)
        let installer = SeedPresetInstaller(baseURL: configDir, catalogClient: client)
        XCTAssertEqual(installer.refreshFromCatalog(), [])
    }
}
