import XCTest
@testable import FloatingMacroCore

/// Phase 5 (P5-1) — `ControlAPIConfig.lanExposureEnabled` の追加に伴う
/// ラウンドトリップ / 後方互換 / デフォルト値の検証。
final class ControlAPIConfigTests: XCTestCase {

    // MARK: - Default

    func testDefaultLanExposureIsOff() {
        let cfg = ControlAPIConfig()
        XCTAssertFalse(cfg.lanExposureEnabled,
                       "LAN 公開は明示的にオンにしない限り常に OFF (Phase 5 セキュリティ要件)")
    }

    // MARK: - Round trip

    func testLanExposureEnabledRoundTrip() throws {
        let cfg = ControlAPIConfig(enabled: true,
                                   port: 17430,
                                   agentMode: .normal,
                                   requireAuth: true,
                                   testMode: false,
                                   lanExposureEnabled: true)
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(ControlAPIConfig.self, from: data)
        XCTAssertTrue(decoded.lanExposureEnabled)
        XCTAssertEqual(decoded.port, 17430)
        XCTAssertEqual(decoded.agentMode, .normal)
    }

    // MARK: - Backward compatibility

    func testLegacyJSONWithoutLanExposureDefaultsToOff() throws {
        // v0.12 以前に保存された JSON は lanExposureEnabled キーを含まない。
        // 既存ユーザーが LAN 公開モードに勝手に入らないことを保証する。
        let legacyJSON = """
        {
          "enabled": true,
          "port": 17430,
          "agentMode": "normal",
          "requireAuth": true,
          "testMode": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ControlAPIConfig.self, from: legacyJSON)
        XCTAssertFalse(decoded.lanExposureEnabled,
                       "lanExposureEnabled フィールドが無い旧 JSON は OFF にデコード")
        XCTAssertTrue(decoded.enabled)
    }

    func testLanExposureEnabledExplicitTrueDecodes() throws {
        let json = """
        {
          "enabled": true,
          "port": 17430,
          "lanExposureEnabled": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ControlAPIConfig.self, from: json)
        XCTAssertTrue(decoded.lanExposureEnabled)
    }

    func testEmptyJSONDecodesToAllDefaults() throws {
        // 完全に空のオブジェクトでも各フィールドのデフォルト値で埋まる。
        let empty = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ControlAPIConfig.self, from: empty)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.port, 17430)
        XCTAssertEqual(decoded.agentMode, .normal)
        XCTAssertTrue(decoded.requireAuth)
        XCTAssertFalse(decoded.testMode)
        XCTAssertFalse(decoded.lanExposureEnabled)
    }
}
