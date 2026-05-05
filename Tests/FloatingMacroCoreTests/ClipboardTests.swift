import XCTest
import AppKit
@testable import FloatingMacroCore

/// Tests for the clipboard abstraction.
///
/// This suite covers two layers:
/// 1. `ClipboardSnapshot` as a plain value (no pasteboard access required).
/// 2. `SystemClipboard` round-trip behavior against `NSPasteboard.general`.
///
/// The `SystemClipboard` tests use the real system pasteboard. To avoid leaking
/// test data into the user's actual clipboard, each such test saves the current
/// pasteboard content before running and restores it in `tearDown`.
final class ClipboardTests: XCTestCase {

    // MARK: - Snapshot value semantics

    func testSnapshotHoldsMultipleItemsAndTypes() {
        let item1 = ClipboardItem(type: .string, data: "hello".data(using: .utf8)!)
        let item2 = ClipboardItem(type: .html,   data: "<b>hi</b>".data(using: .utf8)!)
        let snapshot = ClipboardSnapshot(items: [[item1, item2]])

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items[0].count, 2)
        XCTAssertEqual(snapshot.items[0][0].type, .string)
        XCTAssertEqual(snapshot.items[0][1].type, .html)
    }

    func testEmptySnapshot() {
        let snapshot = ClipboardSnapshot(items: [])
        XCTAssertTrue(snapshot.items.isEmpty)
    }

    // MARK: - SystemClipboard round-trip

    private var savedSnapshot: ClipboardSnapshot?

    override func setUp() {
        super.setUp()
        // Preserve the user's clipboard before each test.
        savedSnapshot = SystemClipboard.shared.save()
    }

    override func tearDown() {
        if let snapshot = savedSnapshot {
            SystemClipboard.shared.restore(snapshot)
        }
        savedSnapshot = nil
        super.tearDown()
    }

    func testSetStringAndSaveReturnsString() {
        let clipboard = SystemClipboard.shared

        clipboard.setString("floatingmacro-unit-test-\(UUID().uuidString)")
        let pasteboardString = NSPasteboard.general.string(forType: .string)

        XCTAssertTrue(pasteboardString?.hasPrefix("floatingmacro-unit-test-") ?? false)
    }

    func testSaveRestoreRoundTripSingleItem() {
        let clipboard = SystemClipboard.shared
        let marker = "round-trip-\(UUID().uuidString)"

        clipboard.setString(marker)
        let snapshot = clipboard.save()

        // Mutate
        clipboard.setString("overwritten")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "overwritten")

        // Restore
        clipboard.restore(snapshot)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), marker)
    }

    /// Ensures multi-item pasteboard snapshots round-trip faithfully.
    /// SPEC §7.2 requires save/restore to preserve ALL pasteboard items (not
    /// just a single string), because pasting a clipboard that contained e.g.
    /// images + RTF would otherwise silently drop data.
    func testRestorePreservesMultipleItems() {
        let pb = NSPasteboard.general
        let clipboard = SystemClipboard.shared

        // Seed the pasteboard with two items manually.
        pb.clearContents()
        let item1 = NSPasteboardItem()
        item1.setData("first-item-\(UUID().uuidString)".data(using: .utf8)!, forType: .string)
        let item2 = NSPasteboardItem()
        item2.setData("second-item-\(UUID().uuidString)".data(using: .utf8)!, forType: .string)
        pb.writeObjects([item1, item2])

        // Sanity: two items are on the pasteboard.
        XCTAssertEqual(pb.pasteboardItems?.count, 2)

        // Take a snapshot and clobber the pasteboard.
        let snapshot = clipboard.save()
        XCTAssertEqual(snapshot.items.count, 2, "snapshot must capture BOTH items")

        clipboard.setString("only-one")
        XCTAssertEqual(pb.pasteboardItems?.count, 1)

        // Restore — after the fix, both items should come back.
        clipboard.restore(snapshot)

        XCTAssertEqual(pb.pasteboardItems?.count, 2,
                       "restore must bring back all pasteboard items, not just the last one")
    }

    func testRestorePreservesMultipleUTIsOnSingleItem() {
        let pb = NSPasteboard.general
        let clipboard = SystemClipboard.shared

        pb.clearContents()
        let item = NSPasteboardItem()
        let stringData = "multi-type".data(using: .utf8)!
        let htmlData   = "<b>multi-type</b>".data(using: .utf8)!
        item.setData(stringData, forType: .string)
        item.setData(htmlData,   forType: .html)
        pb.writeObjects([item])

        let snapshot = clipboard.save()
        XCTAssertEqual(snapshot.items.first?.count, 2,
                       "a single pasteboard item with two UTIs must yield 2 ClipboardItems")

        clipboard.setString("replaced")

        clipboard.restore(snapshot)

        // After restore, both UTIs should be present on the first pasteboard item.
        let restoredItem = pb.pasteboardItems?.first
        XCTAssertNotNil(restoredItem?.data(forType: .string))
        XCTAssertNotNil(restoredItem?.data(forType: .html))
    }

    func testRestoreEmptySnapshotClearsPasteboard() {
        let pb = NSPasteboard.general
        let clipboard = SystemClipboard.shared

        clipboard.setString("some-content")
        XCTAssertNotNil(pb.string(forType: .string))

        clipboard.restore(ClipboardSnapshot(items: []))
        // After restoring an empty snapshot, no items should be present.
        XCTAssertTrue(pb.pasteboardItems?.isEmpty ?? true)
    }
}
