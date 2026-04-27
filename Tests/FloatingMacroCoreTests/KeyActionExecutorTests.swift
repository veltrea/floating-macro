import XCTest
import CoreGraphics
@testable import FloatingMacroCore

final class KeyActionExecutorTests: XCTestCase {

    private var mocks: TestMocks!

    override func setUp() {
        super.setUp()
        mocks = TestMocks()
    }

    override func tearDown() {
        mocks.restore()
        mocks = nil
        super.tearDown()
    }

    func testSimpleKeyDispatches() throws {
        let combo = try KeyCombo.parse("v")
        try KeyActionExecutor.execute(combo)
        XCTAssertEqual(mocks.synth.calls.count, 1)
        XCTAssertEqual(mocks.synth.calls[0].keyCode, 0x09)
        XCTAssertEqual(mocks.synth.calls[0].flags, CGEventFlags())
    }

    func testComboDispatchesWithFlags() throws {
        let combo = try KeyCombo.parse("cmd+shift+a")
        try KeyActionExecutor.execute(combo)
        XCTAssertEqual(mocks.synth.calls.count, 1)
        let call = mocks.synth.calls[0]
        XCTAssertEqual(call.keyCode, 0x00)
        XCTAssertTrue(call.flags.contains(.maskCommand))
        XCTAssertTrue(call.flags.contains(.maskShift))
        XCTAssertFalse(call.flags.contains(.maskAlternate))
        XCTAssertFalse(call.flags.contains(.maskControl))
    }

    func testAccessibilityDeniedPropagates() throws {
        mocks.synth.errorToThrow = ActionError.accessibilityDenied

        let combo = try KeyCombo.parse("cmd+v")
        XCTAssertThrowsError(try KeyActionExecutor.execute(combo)) { error in
            XCTAssertEqual(error as? ActionError, .accessibilityDenied)
        }
        // Mock recorded no call because it threw before appending.
        XCTAssertEqual(mocks.synth.calls.count, 0)
    }

    func testAllFourModifierFlagsTogether() throws {
        let combo = try KeyCombo.parse("cmd+ctrl+alt+shift+t")
        try KeyActionExecutor.execute(combo)
        let flags = mocks.synth.calls[0].flags
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskControl))
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertTrue(flags.contains(.maskShift))
    }
}
