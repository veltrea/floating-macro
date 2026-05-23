import XCTest
@testable import FloatingMacroCore

/// Phase 5 (P5-3) - Unit test for the token store of LAN public mode restart invalidation.
final class EphemeralLANTokenStoreTests: XCTestCase {

    // Each test reusing shared should not leak state between tests.
    // Generate an independent instance directly for verification.
    private func makeStore() -> EphemeralLANTokenStore {
        return EphemeralLANTokenStore()
    }

    func testInitiallyNoTokenIssued() {
        let store = makeStore()
        XCTAssertNil(store.current)
        XCTAssertNil(store.lastRotatedAt)
    }

    func testEnsureIssuedCreatesAndPersistsAcrossCalls() {
        let store = makeStore()
        let first = store.ensureIssued()
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(store.current, first)

        // The second ensureIssued does not rotate existing tokens; it simply returns them as-is.
        let second = store.ensureIssued()
        XCTAssertEqual(first, second)
    }

    func testRotateReplacesPreviousToken() {
        let store = makeStore()
        let first = store.ensureIssued()
        let rotated = store.rotate()
        XCTAssertNotEqual(first, rotated, "rotate は必ず新しいトークンを発行する")
        XCTAssertEqual(store.current, rotated)
    }

    func testRevokeClearsToken() {
        let store = makeStore()
        _ = store.ensureIssued()
        store.revoke()
        XCTAssertNil(store.current)
        XCTAssertNil(store.lastRotatedAt)
    }

    func testMatchesAcceptsCurrentAndRejectsOthers() {
        let store = makeStore()
        let issued = store.ensureIssued()
        XCTAssertTrue(store.matches(issued))
        XCTAssertFalse(store.matches(""))
        XCTAssertFalse(store.matches("not-a-real-token"))
    }

    func testMatchesReturnsFalseWhenNoTokenIssued() {
        let store = makeStore()
        XCTAssertFalse(store.matches(""), "未発行状態では空文字も一致しない")
        XCTAssertFalse(store.matches("anything"))
    }

    func testRotateDoesNotMatchOldToken() {
        let store = makeStore()
        let old = store.ensureIssued()
        _ = store.rotate()
        XCTAssertFalse(store.matches(old),
                       "rotate 後は過去トークンが即座に無効化される")
    }

    func testGeneratedTokenIsHexAnd16Bytes() {
        let token = EphemeralLANTokenStore.generate()
        XCTAssertEqual(token.count, 32, "16 バイト = 32 hex 文字")
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(token.unicodeScalars.allSatisfy { hexCharSet.contains($0) },
                      "hex 文字以外が混入していないこと")
    }

    func testConstantTimeEqualsHandlesLengthDifference() {
        // Direct test of internal helpers: Do not crash if lengths differ, return false instead.
        XCTAssertFalse(EphemeralLANTokenStore.constantTimeEquals("abc", "abcd"))
        XCTAssertFalse(EphemeralLANTokenStore.constantTimeEquals("", "x"))
        XCTAssertTrue(EphemeralLANTokenStore.constantTimeEquals("same", "same"))
        XCTAssertTrue(EphemeralLANTokenStore.constantTimeEquals("", ""))
    }
}
