import XCTest
@testable import FloatingMacroCore

/// Unit tests for ImageIOIconExtractor. Real `.app` bundles are used as
/// fixtures because constructing a synthetic icns is more work than
/// it's worth — Calculator.app exists on every Mac. Tests for apps
/// that aren't always installed (Slack, VS Code) use XCTSkip.
final class ImageIOIconExtractorTests: XCTestCase {

    /// PNG magic bytes: 89 50 4E 47.
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    func testExtractCalculatorIcon() throws {
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calc.path) else {
            throw XCTSkip("Calculator.app not present in this environment")
        }
        let extractor = ImageIOIconExtractor()
        let data = try extractor.extractPNG(from: calc, size: 256)
        XCTAssertGreaterThan(data.count, 1000,
                             "PNG should be meaningfully sized (got \(data.count) bytes)")
        XCTAssertEqual(Array(data.prefix(4)), Self.pngSignature,
                       "Output should start with PNG signature")
    }

    func testExtractSlackIconIfPresent() throws {
        let slack = URL(fileURLWithPath: "/Applications/Slack.app")
        guard FileManager.default.fileExists(atPath: slack.path) else {
            throw XCTSkip("Slack.app not installed in this environment")
        }
        let extractor = ImageIOIconExtractor()
        let data = try extractor.extractPNG(from: slack, size: 128)
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(Array(data.prefix(4)), Self.pngSignature)
    }

    func testMissingAppThrows() {
        let bogus = URL(fileURLWithPath: "/Applications/__no_such_app_for_floatingmacro_test__.app")
        let extractor = ImageIOIconExtractor()
        XCTAssertThrowsError(try extractor.extractPNG(from: bogus, size: 64)) { err in
            guard case .appBundleMissing = err as? ImageIOIconExtractor.ExtractError else {
                XCTFail("expected .appBundleMissing, got: \(err)")
                return
            }
        }
    }

    func testAppWithoutIcnsThrows() throws {
        // Construct a stub `.app` bundle with an empty Info.plist and no
        // icns file in Resources/. The extractor should fail with
        // .noIcnsFound listing the candidate names it tried.
        let stub = FileManager.default.temporaryDirectory
            .appendingPathComponent("FmStub-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: stub.appendingPathComponent("Contents/Resources"),
            withIntermediateDirectories: true)
        let plistURL = stub.appendingPathComponent("Contents/Info.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [:] as [String: Any],
            format: .xml,
            options: 0)
        try plistData.write(to: plistURL)
        defer { try? FileManager.default.removeItem(at: stub) }

        let extractor = ImageIOIconExtractor()
        XCTAssertThrowsError(try extractor.extractPNG(from: stub, size: 64)) { err in
            guard case .noIcnsFound(let candidates) = err as? ImageIOIconExtractor.ExtractError else {
                XCTFail("expected .noIcnsFound, got: \(err)")
                return
            }
            XCTAssertTrue(candidates.contains("AppIcon.icns"),
                          "fallback should always include AppIcon.icns")
        }
    }

    func testAsyncExtractCalculatorIcon() async throws {
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calc.path) else {
            throw XCTSkip("Calculator.app not present in this environment")
        }
        let extractor = ImageIOIconExtractor()
        let data = try await extractor.extractPNGAsync(from: calc, size: 128)
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(Array(data.prefix(4)), Self.pngSignature)
    }
}
