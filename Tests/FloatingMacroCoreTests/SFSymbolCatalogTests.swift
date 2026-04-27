import XCTest
@testable import FloatingMacroCore

final class SFSymbolCatalogTests: XCTestCase {

    func testCategoriesNotEmpty() {
        XCTAssertFalse(SFSymbolCatalog.categories.isEmpty)
        for category in SFSymbolCatalog.categories {
            XCTAssertFalse(category.symbols.isEmpty,
                           "category \(category.id) must have at least one symbol")
        }
    }

    func testCategoryIdsUnique() {
        let ids = SFSymbolCatalog.categories.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "category ids must be unique")
    }

    func testCategoryLabelsNotEmpty() {
        for category in SFSymbolCatalog.categories {
            XCTAssertFalse(category.label.isEmpty)
        }
    }

    func testAllIsDeduplicated() {
        let all = SFSymbolCatalog.all
        XCTAssertEqual(Set(all).count, all.count,
                       "all must contain no duplicates")
    }

    func testTotalCountIsReasonable() {
        // Keep the catalog focused — ~150 is a sensible upper bound for a
        // "picker of commonly-used symbols".
        XCTAssertGreaterThanOrEqual(SFSymbolCatalog.all.count, 100)
        XCTAssertLessThanOrEqual(SFSymbolCatalog.all.count, 250)
    }

    func testLookupById() {
        XCTAssertNotNil(SFSymbolCatalog.category(id: "general"))
        XCTAssertNil(SFSymbolCatalog.category(id: "no-such-category"))
    }

    func testReferenceStringUsesSfPrefix() {
        XCTAssertEqual(SFSymbolCatalog.reference(for: "star.fill"),
                       "sf:star.fill")
    }

    /// Regression guard: every symbol name should be a valid identifier
    /// shape (lowercase letters, digits, dot, non-empty). This catches
    /// typos where a trailing space or uppercase letter sneaks in.
    func testSymbolNamesAreWellFormed() {
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: ".-_"))
        for category in SFSymbolCatalog.categories {
            for name in category.symbols {
                XCTAssertFalse(name.isEmpty,
                               "empty symbol in \(category.id)")
                XCTAssertTrue(name.rangeOfCharacter(from: allowed.inverted) == nil,
                              "symbol \(name) in \(category.id) has unexpected characters")
            }
        }
    }
}
