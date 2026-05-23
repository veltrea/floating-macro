import XCTest
@testable import FloatingMacroCore

/// Phase 5 (P5-4): Static assets can be retrieved from the bundle.
/// Replacement of tokens in HTML templates and JavaScript escaping works as expected.
final class WebPanelAssetsTests: XCTestCase {

    // MARK: - Bundle access

    func testHTMLAssetIsBundled() {
        let data = WebPanelAssets.data(.html)
        XCTAssertNotNil(data, "panel.html がバンドルから読めること")
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    func testCSSAssetIsBundled() {
        let data = WebPanelAssets.data(.css)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    func testJSAssetIsBundled() {
        let data = WebPanelAssets.data(.js)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    // MARK: - Content types

    func testContentTypesAreCorrect() {
        XCTAssertTrue(WebPanelAssets.AssetKind.html.contentType.hasPrefix("text/html"))
        XCTAssertTrue(WebPanelAssets.AssetKind.css.contentType.hasPrefix("text/css"))
        XCTAssertTrue(WebPanelAssets.AssetKind.js.contentType.hasPrefix("application/javascript"))
    }

    // MARK: - Token rendering

    func testRenderHTMLSubstitutesToken() throws {
        let token = "deadbeef0123456789abcdef01234567"
        let data = try XCTUnwrap(WebPanelAssets.renderHTML(
            token: token, presetJSON: "null", presetDisplay: "test", ssrHTML: ""
        ))
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(html.contains(token), "実トークンが HTML に注入されること")
        XCTAssertFalse(html.contains("{{TOKEN}}"),
                       "プレースホルダが残っていないこと")
        XCTAssertFalse(html.contains("{{PRESET_JSON}}"))
        XCTAssertFalse(html.contains("{{SSR_HTML}}"))
    }

    func testRenderHTMLEscapesScriptTagInToken() throws {
        // It should be a hex token, but a token containing "</script>" was passed as an insurance.
        // Check that the entire HTML does not break (not escaping from JS literals).
        let evil = "abc</script><script>alert(1)</script>"
        let data = try XCTUnwrap(WebPanelAssets.renderHTML(
            token: evil, presetJSON: "null", presetDisplay: "test", ssrHTML: ""
        ))
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(html.contains("</script><script>alert"),
                       "エスケープなしで script タグを差し込ませてはいけない")
        // <>, &, and are being converted to Unicode escapes.
        XCTAssertTrue(html.contains("\\u003c") || html.contains("\\u003C"))
    }

    // MARK: - Sanitize unit

    func testSanitizeForJSONHandlesAllControlChars() {
        let s = "\\\"\n\r\t<>&"
        let out = WebPanelAssets.sanitizeForJSON(s)
        // Input: 8 characters ( " \n\r\t<>&) ) to be safely escaped in JavaScript literals.
        // Convert to an expression. To prevent misreading, assemble the expected value from components.
        let expected =
            "\\\\" +     // `\` → `\\` (2 characters)
            "\\\"" +     // → "        (2 characters)
            "\\n"  +     // LF -> \n (2 characters)
            "\\r"  +     // CR -> \r (2 characters)
            "\\t"  +     // tab → \t       (2 characters)
            "\\u003c" +  // <  → <    (6 characters)
            "\\u003e" +  // >    (6 characters)
            "\\u0026"    // &  → &    (6 characters)
        XCTAssertEqual(out, expected)
        XCTAssertEqual(out.count, 28)
    }

    func testSanitizeForJSONIsIdentityForHex() {
        let hex = "0123456789abcdef"
        XCTAssertEqual(WebPanelAssets.sanitizeForJSON(hex), hex)
    }
}
