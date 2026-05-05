import XCTest
@testable import FloatingMacroCore

final class AppDropClassifierTests: XCTestCase {

    func testClassifyCalculatorApp() throws {
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calc.path) else {
            throw XCTSkip("Calculator.app not present")
        }
        let candidate = AppDropClassifier.classify(calc)
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.kind, .app)
        XCTAssertEqual(candidate?.target, "com.apple.calculator",
                       "bundle id should be the launch target when resolvable")
        XCTAssertEqual(candidate?.iconSourcePath, calc.path)
        XCTAssertTrue(candidate?.tooltip.contains("com.apple.calculator") ?? false)
    }

    func testClassifyStubAppWithoutBundleIdFallsBackToPath() throws {
        let stub = try makeStubApp(bundleId: nil, displayName: "MyStub")
        defer { try? FileManager.default.removeItem(at: stub) }

        let candidate = AppDropClassifier.classify(stub)
        XCTAssertEqual(candidate?.kind, .app)
        XCTAssertEqual(candidate?.target, stub.path,
                       "absolute path is the launch target when bundle id is nil")
        XCTAssertEqual(candidate?.label, "MyStub")
        XCTAssertEqual(candidate?.tooltip, stub.path)
    }

    func testClassifyRegularFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmDropFile-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let candidate = AppDropClassifier.classify(tmp)
        XCTAssertEqual(candidate?.kind, .file)
        XCTAssertEqual(candidate?.target, tmp.path)
        XCTAssertEqual(candidate?.label, tmp.lastPathComponent)
    }

    func testClassifyFolder() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmDropFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let candidate = AppDropClassifier.classify(tmp)
        XCTAssertEqual(candidate?.kind, .folder)
        XCTAssertEqual(candidate?.target, tmp.path)
    }

    func testClassifyMissingPathReturnsNil() {
        let bogus = URL(fileURLWithPath: "/no/such/path/at/all/whatever")
        XCTAssertNil(AppDropClassifier.classify(bogus))
    }

    func testClassifyAppExtensionButMissingPathReturnsNil() {
        let bogus = URL(fileURLWithPath: "/Applications/__no_such_app__.app")
        XCTAssertNil(AppDropClassifier.classify(bogus))
    }

    // MARK: - Helpers

    private func makeStubApp(bundleId: String?, displayName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmDropStub-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleName": displayName]
        if let bid = bundleId { plist["CFBundleIdentifier"] = bid }
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }
}
