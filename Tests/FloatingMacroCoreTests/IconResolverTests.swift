import XCTest
@testable import FloatingMacroCore

final class IconResolverTests: XCTestCase {

    func testEmptyRejected() {
        switch IconResolver.resolve("") {
        case .failure(.empty): break
        default: XCTFail("expected .empty")
        }
        switch IconResolver.resolve("   ") {
        case .failure(.empty): break
        default: XCTFail("whitespace-only must also be .empty")
        }
    }

    func testBundleIdentifier() {
        switch IconResolver.resolve("com.apple.Safari") {
        case .success(.bundleIdentifier(let bid)):
            XCTAssertEqual(bid, "com.apple.Safari")
        default: XCTFail("expected bundle id")
        }
    }

    func testAppBundle() throws {
        // Safari is present on every Mac.
        switch IconResolver.resolve("/Applications/Safari.app") {
        case .success(.appBundle(let url)):
            XCTAssertEqual(url.path, "/Applications/Safari.app")
        case .failure:
            throw XCTSkip("Safari.app not present in this environment")
        default: XCTFail("expected app bundle")
        }
    }

    func testImageFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("icon-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tmp) // PNG signature bytes
        defer { try? FileManager.default.removeItem(at: tmp) }

        switch IconResolver.resolve(tmp.path) {
        case .success(.imageFile(let url)):
            XCTAssertEqual(url.path, tmp.path)
        default: XCTFail("expected imageFile")
        }
    }

    func testTildeExpansion() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let file = home.appendingPathComponent(".fmtest-icon-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        defer { try? fm.removeItem(at: file) }

        let tildePath = "~/\(file.lastPathComponent)"
        switch IconResolver.resolve(tildePath) {
        case .success(.imageFile(let url)):
            XCTAssertEqual(url.path, file.path)
        default: XCTFail("expected imageFile after tilde expansion")
        }
    }

    func testNonExistentFileRejected() {
        switch IconResolver.resolve("/definitely/not/here-\(UUID().uuidString).png") {
        case .failure(.fileNotFound): break
        default: XCTFail("expected fileNotFound")
        }
    }

    func testUnknownExtensionTreatedAsImage() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("icon-\(UUID().uuidString).foo")
        try Data([0x00]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        switch IconResolver.resolve(tmp.path) {
        case .success(.imageFile): break
        default: XCTFail("unknown extension should still yield imageFile (NSImage decides)")
        }
    }

    // MARK: - sf: prefix (SF Symbols)

    func testSFSymbolPrefix() {
        switch IconResolver.resolve("sf:star.fill") {
        case .success(.systemSymbol(let name)):
            XCTAssertEqual(name, "star.fill")
        default: XCTFail("expected systemSymbol")
        }
    }

    func testSFSymbolPrefixWithWhitespace() {
        switch IconResolver.resolve("sf: command.square ") {
        case .success(.systemSymbol(let name)):
            XCTAssertEqual(name, "command.square")
        default: XCTFail("expected systemSymbol")
        }
    }

    func testSFSymbolEmptyNameRejected() {
        switch IconResolver.resolve("sf:") {
        case .failure(.empty): break
        default: XCTFail("empty name after sf: should be rejected")
        }
    }

    // MARK: - lucide: prefix (bundled SVG)

    func testLucidePrefix() {
        switch IconResolver.resolve("lucide:star") {
        case .success(.bundledIcon(let pack, let name)):
            XCTAssertEqual(pack, "lucide")
            XCTAssertEqual(name, "star")
        default: XCTFail("expected bundledIcon")
        }
    }

    func testLucidePrefixKeepsHyphens() {
        // Lucide uses kebab-case names like "arrow-up-right" or "circle-check".
        switch IconResolver.resolve("lucide:arrow-up-right") {
        case .success(.bundledIcon(let pack, let name)):
            XCTAssertEqual(pack, "lucide")
            XCTAssertEqual(name, "arrow-up-right")
        default: XCTFail("expected bundledIcon")
        }
    }

    func testLucideEmptyNameRejected() {
        switch IconResolver.resolve("lucide:") {
        case .failure(.empty): break
        default: XCTFail("empty name after lucide: should be rejected")
        }
    }

    // MARK: - Prefix precedence over other rules

    func testPrefixBeatsBundleIdHeuristic() {
        // "sf:com.apple.foo" would normally look like a bundle id after the
        // prefix is stripped — but the prefix itself takes priority.
        switch IconResolver.resolve("sf:com.apple.foo") {
        case .success(.systemSymbol(let name)):
            XCTAssertEqual(name, "com.apple.foo")
        default: XCTFail("sf: prefix must win over bundle-id heuristic")
        }
    }
}
