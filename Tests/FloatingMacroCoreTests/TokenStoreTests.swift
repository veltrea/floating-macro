import XCTest
@testable import FloatingMacroCore

final class TokenStoreTests: XCTestCase {

    func test_generate_returns64CharHex() {
        let token = TokenStore.generate()
        XCTAssertEqual(token.count, 64)
        XCTAssertTrue(token.allSatisfy { $0.isHexDigit },
                      "generate() must return lowercase hex characters only")
    }

    func test_generate_isUnique() {
        let a = TokenStore.generate()
        let b = TokenStore.generate()
        XCTAssertNotEqual(a, b, "generate() should produce unique tokens each call")
    }
}
