import XCTest
@testable import FloatingMacroCore

final class WebPanelURLBuilderTests: XCTestCase {

    // MARK: - make

    func testBuildBasicURL() {
        let url = WebPanelURLBuilder.make(
            host: "192.168.1.21", port: 17430,
            token: "deadbeef0123456789abcdef01234567"
        )
        XCTAssertEqual(url,
                       "http://192.168.1.21:17430/webpanel?token=deadbeef0123456789abcdef01234567")
    }

    func testBuildURLForMDNSHost() {
        let url = WebPanelURLBuilder.make(host: "floatingmacro.local",
                                          port: 17430, token: "abc")
        XCTAssertEqual(url, "http://floatingmacro.local:17430/webpanel?token=abc")
    }

    func testBuildURLBracketsIPv6() {
        let url = WebPanelURLBuilder.make(host: "fe80::1", port: 17430, token: "xx")
        XCTAssertTrue(url.contains("[fe80::1]"),
                      "IPv6 リテラルは [] で括る必要がある")
    }

    func testBuildURLWithPresetParameter() {
        let url = WebPanelURLBuilder.make(
            host: "192.168.1.21", port: 17430,
            token: "abc123", preset: "midjourney"
        )
        XCTAssertTrue(url.contains("token=abc123"))
        XCTAssertTrue(url.contains("preset=midjourney"))
    }

    func testBuildURLWithEmptyPresetSkipsParam() {
        let url = WebPanelURLBuilder.make(
            host: "192.168.1.21", port: 17430,
            token: "abc", preset: ""
        )
        XCTAssertFalse(url.contains("preset="),
                       "空文字 preset は URL に出さない")
    }

    func testBuildURLWithNilPresetSkipsParam() {
        let url = WebPanelURLBuilder.make(
            host: "192.168.1.21", port: 17430,
            token: "abc", preset: nil
        )
        XCTAssertFalse(url.contains("preset="))
    }

    func testPresetWithSpacesIsPercentEncoded() {
        let url = WebPanelURLBuilder.make(
            host: "h", port: 1, token: "t", preset: "my preset"
        )
        XCTAssertFalse(url.contains("my preset"))
        XCTAssertTrue(url.contains("preset=my%20preset") || url.contains("preset=my+preset"))
    }

    func testTokenWithSpecialCharsIsPercentEncoded() {
        // ephemeral token は hex 限定だが、将来別形式に切り替えたとき
        // 安全側に倒すため。
        let url = WebPanelURLBuilder.make(host: "127.0.0.1",
                                          port: 80,
                                          token: "a/b c")
        XCTAssertFalse(url.contains(" "), "URL に生のスペースが残っていない")
    }

    // MARK: - preferredHost

    func testPreferredHostWithMDNS() {
        XCTAssertEqual(
            WebPanelURLBuilder.preferredHost(localName: "floatingmacro"),
            "floatingmacro.local"
        )
    }

    func testPreferredHostWithMDNSAlreadyHasSuffix() {
        XCTAssertEqual(
            WebPanelURLBuilder.preferredHost(localName: "floatingmacro.local"),
            "floatingmacro.local"
        )
    }

    func testPreferredHostFallsBackToLAN() {
        XCTAssertEqual(
            WebPanelURLBuilder.preferredHost(localName: nil, lanIPv4: "192.168.1.21"),
            "192.168.1.21"
        )
    }

    func testPreferredHostFallsBackToLoopback() {
        XCTAssertEqual(
            WebPanelURLBuilder.preferredHost(localName: nil, lanIPv4: nil),
            "127.0.0.1"
        )
    }
}
