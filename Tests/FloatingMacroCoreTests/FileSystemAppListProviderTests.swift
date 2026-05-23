import XCTest
@testable import FloatingMacroCore

final class FileSystemAppListProviderTests: XCTestCase {

    // MARK: - Real environment

    func testListsCalculatorFromSystemApplications() throws {
        let provider = FileSystemAppListProvider(searchRoots: [
            URL(fileURLWithPath: "/System/Applications")
        ])
        let apps = try provider.availableApplications()
        guard !apps.isEmpty else {
            throw XCTSkip("/System/Applications is empty in this environment")
        }
        XCTAssertGreaterThan(apps.count, 5,
                             "Expected several system apps, got \(apps.count)")
        let calc = apps.first { $0.bundleIdentifier == "com.apple.calculator" }
        XCTAssertNotNil(calc, "Calculator.app should be discovered by bundle id")
    }

    func testEmptySearchRootsReturnEmpty() throws {
        let provider = FileSystemAppListProvider(searchRoots: [])
        XCTAssertEqual(try provider.availableApplications().count, 0)
    }

    func testMissingRootIsSkippedNotErrored() throws {
        let provider = FileSystemAppListProvider(searchRoots: [
            URL(fileURLWithPath: "/no/such/directory/at/all")
        ])
        XCTAssertEqual(try provider.availableApplications().count, 0,
                       "missing root should be silently skipped")
    }

    // MARK: - Stub roots (deterministic)

    func testStubRootWithMixedContent() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeStubApp(in: root, name: "Beta.app", bundleId: "com.example.beta", displayName: "Beta")
        try makeStubApp(in: root, name: "Alpha.app", bundleId: "com.example.alpha", displayName: "Alpha")
        // Non-app file should be ignored
        try Data().write(to: root.appendingPathComponent("readme.txt"))

        let provider = FileSystemAppListProvider(searchRoots: [root])
        let apps = try provider.availableApplications()

        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(apps.map(\.displayName), ["Alpha", "Beta"],
                       "results must be sorted by displayName, case-insensitive")
    }

    func testDuplicateBundleIdsAreDeduplicated() throws {
        let root1 = try makeTempRoot()
        let root2 = try makeTempRoot()
        defer {
            try? FileManager.default.removeItem(at: root1)
            try? FileManager.default.removeItem(at: root2)
        }

        try makeStubApp(in: root1, name: "Same.app",
                        bundleId: "com.example.same", displayName: "First")
        try makeStubApp(in: root2, name: "Same.app",
                        bundleId: "com.example.same", displayName: "Second")

        let provider = FileSystemAppListProvider(searchRoots: [root1, root2])
        let apps = try provider.availableApplications()

        XCTAssertEqual(apps.count, 1, "same bundle id across roots should be deduped")
        XCTAssertEqual(apps.first?.displayName, "First",
                       "first occurrence wins; root1 listed before root2")
    }

    func testAppsWithoutBundleIdAreKept() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Bundle without a plist at all: kept, displayName from filename.
        let bareURL = root.appendingPathComponent("Bare.app")
        try FileManager.default.createDirectory(at: bareURL, withIntermediateDirectories: true)
        // Bundle with bundle id: kept normally.
        try makeStubApp(in: root, name: "Withid.app",
                        bundleId: "com.example.withid", displayName: "Withid")

        let provider = FileSystemAppListProvider(searchRoots: [root])
        let apps = try provider.availableApplications()
        XCTAssertEqual(apps.count, 2)
        XCTAssertTrue(apps.contains { $0.displayName == "Bare" && $0.bundleIdentifier == nil })
        XCTAssertTrue(apps.contains { $0.bundleIdentifier == "com.example.withid" })
    }

    func testHiddenAppsSkippedByOption() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeStubApp(in: root, name: ".Hidden.app",
                        bundleId: "com.example.hidden", displayName: "Hidden")
        try makeStubApp(in: root, name: "Visible.app",
                        bundleId: "com.example.visible", displayName: "Visible")

        let provider = FileSystemAppListProvider(searchRoots: [root])
        let apps = try provider.availableApplications()
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.displayName, "Visible")
    }

    /// Also include apps in subfolders like `/Applications/Utilities/`.
    /// Enumerated. Skips package descendants with `.skipsPackageDescendants` for `.app` bundles.
    /// Sub-apps (.app under Frameworks, such as helpers) are excluded.
    func testListsAppsInsideSubdirectories() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Directly below the app
        try makeStubApp(in: root, name: "Top.app",
                        bundleId: "com.example.top", displayName: "Top")
        // Utilities Subfolder Inside the App
        let utilities = root.appendingPathComponent("Utilities")
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
        try makeStubApp(in: utilities, name: "Disk Doctor.app",
                        bundleId: "com.example.disk", displayName: "Disk Doctor")
        try makeStubApp(in: utilities, name: "Activity Watcher.app",
                        bundleId: "com.example.activity", displayName: "Activity Watcher")
        // Two-level nested vendor folders
        let vendor = root.appendingPathComponent("Vendor/Suite")
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        try makeStubApp(in: vendor, name: "Mega Editor.app",
                        bundleId: "com.example.mega", displayName: "Mega Editor")

        // Do not pick up nested .apps within the app bundle (to prevent false positives for helpers, etc.)
        let outer = root.appendingPathComponent("Top.app/Contents/Helpers")
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        try makeStubApp(in: outer, name: "Helper.app",
                        bundleId: "com.example.helper", displayName: "Helper")

        let provider = FileSystemAppListProvider(searchRoots: [root])
        let apps = try provider.availableApplications()
        let names = apps.map(\.displayName)
        XCTAssertTrue(names.contains("Top"), "top-level app must be listed")
        XCTAssertTrue(names.contains("Disk Doctor"),
                      "app under Utilities/ must be listed")
        XCTAssertTrue(names.contains("Activity Watcher"),
                      "app under Utilities/ must be listed")
        XCTAssertTrue(names.contains("Mega Editor"),
                      "app two levels deep under vendor folder must be listed")
        XCTAssertFalse(names.contains("Helper"),
                       "nested .app inside another .app bundle must be skipped")
    }

    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmAppList-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStubApp(in root: URL, name: String, bundleId: String, displayName: String) throws {
        let app = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleId,
            "CFBundleName": displayName,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    }
}
