import XCTest
@testable import FloatingMacroCore

final class AppEntryResolverTests: XCTestCase {

    // MARK: - Real system app

    func testResolveCalculator() throws {
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calc.path) else {
            throw XCTSkip("Calculator.app not present in this environment")
        }
        let entry = AppEntryResolver.resolve(at: calc)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.bundleIdentifier, "com.apple.calculator")
        XCTAssertEqual(entry?.url, calc)
        // Apple's display name may vary by locale; just assert it's non-empty
        // and looks reasonable.
        XCTAssertFalse(entry?.displayName.isEmpty ?? true)
    }

    // MARK: - Stub bundles (deterministic)

    func testResolveStubAppWithDisplayName() throws {
        let stub = try makeStubApp(
            named: "FmStub-DisplayName",
            plist: [
                "CFBundleIdentifier": "com.example.stub.display",
                "CFBundleDisplayName": "Pretty Name",
                "CFBundleName": "uglyName",
            ])
        defer { try? FileManager.default.removeItem(at: stub) }

        let entry = AppEntryResolver.resolve(at: stub)
        XCTAssertEqual(entry?.bundleIdentifier, "com.example.stub.display")
        XCTAssertEqual(entry?.displayName, "Pretty Name",
                       "CFBundleDisplayName must take precedence over CFBundleName")
    }

    func testResolveStubAppFallsBackToBundleName() throws {
        let stub = try makeStubApp(
            named: "FmStub-BundleName",
            plist: [
                "CFBundleIdentifier": "com.example.stub.bundlename",
                "CFBundleName": "BundleNameOnly",
            ])
        defer { try? FileManager.default.removeItem(at: stub) }

        let entry = AppEntryResolver.resolve(at: stub)
        XCTAssertEqual(entry?.displayName, "BundleNameOnly")
    }

    func testResolveAppWithoutPlistFallsBackToFilename() throws {
        let stub = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmBare-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: stub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stub) }

        let entry = AppEntryResolver.resolve(at: stub)
        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.bundleIdentifier)
        XCTAssertTrue(entry!.displayName.hasPrefix("FmBare-"),
                      "filename without .app should be the displayName fallback")
    }

    func testResolveEmptyPlistKeysAreTreatedAsAbsent() throws {
        let stub = try makeStubApp(
            named: "FmStub-EmptyKeys",
            plist: [
                "CFBundleIdentifier": "",
                "CFBundleDisplayName": "",
                "CFBundleName": "",
            ])
        defer { try? FileManager.default.removeItem(at: stub) }

        let entry = AppEntryResolver.resolve(at: stub)
        XCTAssertNil(entry?.bundleIdentifier, "empty string id should resolve to nil")
        XCTAssertTrue(entry!.displayName.hasPrefix("FmStub-"),
                      "empty display/bundle names should fall back to filename")
    }

    // MARK: - Negative cases

    func testRejectsNonAppExtension() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-app.txt")
        XCTAssertNil(AppEntryResolver.resolve(at: url))
    }

    func testRejectsMissingPath() {
        let url = URL(fileURLWithPath: "/Applications/__no_such_app__.app")
        XCTAssertNil(AppEntryResolver.resolve(at: url))
    }

    // MARK: - Helpers

    private func makeStubApp(named base: String, plist: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }
}
