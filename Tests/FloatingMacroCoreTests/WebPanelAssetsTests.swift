import XCTest
@testable import FloatingMacroCore

/// Phase 5 (P5-4): バンドルから Web Panel 静的アセットが取り出せること、
/// HTML テンプレートのトークン置換と JS エスケープが期待通り動くこと。
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
        // hex token のはずだが、保険として `</script>` を含むトークンが渡された
        // ときに HTML 全体が壊れない (= JS リテラルから抜けない) ことを確認。
        let evil = "abc</script><script>alert(1)</script>"
        let data = try XCTUnwrap(WebPanelAssets.renderHTML(
            token: evil, presetJSON: "null", presetDisplay: "test", ssrHTML: ""
        ))
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(html.contains("</script><script>alert"),
                       "エスケープなしで script タグを差し込ませてはいけない")
        // < > & が unicode escape に変換されている
        XCTAssertTrue(html.contains("\\u003c") || html.contains("\\u003C"))
    }

    // MARK: - Sanitize unit

    func testSanitizeForJSONHandlesAllControlChars() {
        let s = "\\\"\n\r\t<>&"
        let out = WebPanelAssets.sanitizeForJSON(s)
        // 入力 8 文字 (\ " LF CR TAB < > &) を 1 つずつ JS リテラル安全な
        // 表現に変換する。誤読防止のため期待値を部品から組み立てる。
        let expected =
            "\\\\" +     // \  → \\        (2 文字)
            "\\\"" +     // "  → \"        (2 文字)
            "\\n"  +     // LF → \n        (2 文字)
            "\\r"  +     // CR → \r        (2 文字)
            "\\t"  +     // TAB → \t       (2 文字)
            "\\u003c" +  // <  → <    (6 文字)
            "\\u003e" +  // >  → >    (6 文字)
            "\\u0026"    // &  → &    (6 文字)
        XCTAssertEqual(out, expected)
        XCTAssertEqual(out.count, 28)
    }

    func testSanitizeForJSONIsIdentityForHex() {
        let hex = "0123456789abcdef"
        XCTAssertEqual(WebPanelAssets.sanitizeForJSON(hex), hex)
    }
}
