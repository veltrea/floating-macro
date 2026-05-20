import XCTest
import CoreGraphics
@testable import FloatingMacroCore

final class KeyComboTests: XCTestCase {
    func testSimpleKey() throws {
        let combo = try KeyCombo.parse("v")
        XCTAssertEqual(combo.keyCode, 0x09)
        XCTAssertEqual(combo.modifiers, CGEventFlags())
    }

    func testCmdV() throws {
        let combo = try KeyCombo.parse("cmd+v")
        XCTAssertEqual(combo.keyCode, 0x09)
        XCTAssertTrue(combo.modifiers.contains(.maskCommand))
    }

    func testCmdShiftZ() throws {
        let combo = try KeyCombo.parse("cmd+shift+z")
        XCTAssertEqual(combo.keyCode, 0x06)
        XCTAssertTrue(combo.modifiers.contains(.maskCommand))
        XCTAssertTrue(combo.modifiers.contains(.maskShift))
    }

    func testCaseInsensitive() throws {
        let combo = try KeyCombo.parse("CMD+SHIFT+A")
        XCTAssertEqual(combo.keyCode, 0x00)
        XCTAssertTrue(combo.modifiers.contains(.maskCommand))
        XCTAssertTrue(combo.modifiers.contains(.maskShift))
    }

    func testCtrlAltDelete() throws {
        let combo = try KeyCombo.parse("ctrl+alt+delete")
        XCTAssertEqual(combo.keyCode, 0x33)
        XCTAssertTrue(combo.modifiers.contains(.maskControl))
        XCTAssertTrue(combo.modifiers.contains(.maskAlternate))
    }

    func testOptionAlias() throws {
        let combo = try KeyCombo.parse("option+a")
        XCTAssertTrue(combo.modifiers.contains(.maskAlternate))
    }

    func testFunctionKey() throws {
        let combo = try KeyCombo.parse("f5")
        XCTAssertEqual(combo.keyCode, 0x60)
    }

    func testEnterReturn() throws {
        let enter = try KeyCombo.parse("enter")
        let ret = try KeyCombo.parse("return")
        XCTAssertEqual(enter.keyCode, ret.keyCode)
    }

    func testEscapeAlias() throws {
        let esc = try KeyCombo.parse("esc")
        let escape = try KeyCombo.parse("escape")
        XCTAssertEqual(esc.keyCode, escape.keyCode)
    }

    func testArrowKeys() throws {
        XCTAssertEqual(try KeyCombo.parse("up").keyCode, 0x7E)
        XCTAssertEqual(try KeyCombo.parse("down").keyCode, 0x7D)
        XCTAssertEqual(try KeyCombo.parse("left").keyCode, 0x7B)
        XCTAssertEqual(try KeyCombo.parse("right").keyCode, 0x7C)
    }

    func testSpecialChars() throws {
        XCTAssertEqual(try KeyCombo.parse("space").keyCode, 0x31)
        XCTAssertEqual(try KeyCombo.parse("tab").keyCode, 0x30)
    }

    func testInvalidKeyCombo() {
        XCTAssertThrowsError(try KeyCombo.parse("")) { error in
            guard case ActionError.invalidKeyCombo = error else {
                XCTFail("Expected invalidKeyCombo error")
                return
            }
        }
    }

    func testUnknownKey() {
        XCTAssertThrowsError(try KeyCombo.parse("cmd+unknownkey")) { error in
            guard case ActionError.invalidKeyCombo = error else {
                XCTFail("Expected invalidKeyCombo error")
                return
            }
        }
    }

    func testMultipleBaseKeys() {
        XCTAssertThrowsError(try KeyCombo.parse("a+b")) { error in
            guard case ActionError.invalidKeyCombo = error else {
                XCTFail("Expected invalidKeyCombo error")
                return
            }
        }
    }

    func testModifierOnly() {
        XCTAssertThrowsError(try KeyCombo.parse("cmd+shift")) { error in
            guard case ActionError.invalidKeyCombo = error else {
                XCTFail("Expected invalidKeyCombo error")
                return
            }
        }
    }
}
