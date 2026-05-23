import XCTest
@testable import FloatingMacroCore

/// Addition of ControlAPIConfig.lanExposureEnabled
/// Round trip compatibility / Backward compatibility / Validation of default values.
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
        // JSON saved before v0.12 does not contain the `lanExposureEnabled` key.
        // Guarantee that existing users cannot arbitrarily enter the LAN public mode.
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
        // Even an entirely empty object is filled with default values for each field.
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
