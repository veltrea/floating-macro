import XCTest
@testable import FloatingMacroCore

final class PresetEditorTests: XCTestCase {

    // MARK: - Fixtures

    private func samplePreset() -> Preset {
        Preset(name: "t", displayName: "Test", groups: [
            ButtonGroup(id: "g1", label: "G1", buttons: [
                ButtonDefinition(id: "b1", label: "one", action: .key(combo: "a")),
                ButtonDefinition(id: "b2", label: "two", action: .key(combo: "b")),
            ]),
            ButtonGroup(id: "g2", label: "G2", buttons: [
                ButtonDefinition(id: "b3", label: "three", action: .key(combo: "c")),
            ]),
        ])
    }

    // MARK: - Groups

    func testAddGroup() throws {
        let preset = samplePreset()
        let newGroup = ButtonGroup(id: "g3", label: "G3", buttons: [])
        let updated = try PresetEditor.addGroup(newGroup, to: preset)
        XCTAssertEqual(updated.groups.count, 3)
        XCTAssertEqual(updated.groups.last?.id, "g3")
    }

    func testAddGroupRejectsDuplicateId() {
        let preset = samplePreset()
        let dup = ButtonGroup(id: "g1", label: "dup", buttons: [])
        XCTAssertThrowsError(try PresetEditor.addGroup(dup, to: preset)) { err in
            XCTAssertEqual(err as? PresetEditor.EditError, .duplicateId("g1"))
        }
    }

    func testUpdateGroupLabel() throws {
        let updated = try PresetEditor.updateGroup(groupId: "g1", in: samplePreset()) { g in
            g.label = "renamed"
        }
        XCTAssertEqual(updated.groups[0].label, "renamed")
        XCTAssertEqual(updated.groups[1].label, "G2") // untouched
    }

    func testUpdateGroupNotFound() {
        XCTAssertThrowsError(
            try PresetEditor.updateGroup(groupId: "missing", in: samplePreset()) { _ in }
        ) { err in
            XCTAssertEqual(err as? PresetEditor.EditError, .groupNotFound("missing"))
        }
    }

    func testDeleteGroup() throws {
        let updated = try PresetEditor.deleteGroup(groupId: "g1", from: samplePreset())
        XCTAssertEqual(updated.groups.count, 1)
        XCTAssertEqual(updated.groups[0].id, "g2")
    }

    func testReorderGroups() throws {
        let updated = try PresetEditor.reorderGroups(ids: ["g2", "g1"], in: samplePreset())
        XCTAssertEqual(updated.groups.map(\.id), ["g2", "g1"])
    }

    func testReorderGroupsWrongCount() {
        XCTAssertThrowsError(
            try PresetEditor.reorderGroups(ids: ["g1"], in: samplePreset())
        ) { err in
            XCTAssertEqual(err as? PresetEditor.EditError,
                           .reorderIdsMismatch(expected: 2, got: 1))
        }
    }

    // MARK: - Buttons

    func testAddButton() throws {
        let newBtn = ButtonDefinition(id: "bNew", label: "new",
                                      backgroundColor: "#ff0000",
                                      width: 120, height: 40,
                                      action: .key(combo: "z"))
        let updated = try PresetEditor.addButton(newBtn, toGroupId: "g1", in: samplePreset())
        XCTAssertEqual(updated.groups[0].buttons.count, 3)
        XCTAssertEqual(updated.groups[0].buttons.last?.backgroundColor, "#ff0000")
        XCTAssertEqual(updated.groups[0].buttons.last?.width, 120)
    }

    func testUpdateButtonByIdPatchesFields() throws {
        let updated = try PresetEditor.updateButton(buttonId: "b2", in: samplePreset()) { b in
            b.patch(label: "TWO", backgroundColor: "#00ff00", width: 200)
        }
        let btn = updated.groups[0].buttons[1]
        XCTAssertEqual(btn.label, "TWO")
        XCTAssertEqual(btn.backgroundColor, "#00ff00")
        XCTAssertEqual(btn.width, 200)
        XCTAssertNil(btn.height) // not touched
    }

    func testUpdateButtonNotFound() {
        XCTAssertThrowsError(
            try PresetEditor.updateButton(buttonId: "nope", in: samplePreset()) { _ in }
        ) { err in
            XCTAssertEqual(err as? PresetEditor.EditError, .buttonNotFound("nope"))
        }
    }

    func testDeleteButton() throws {
        let updated = try PresetEditor.deleteButton(buttonId: "b1", from: samplePreset())
        XCTAssertEqual(updated.groups[0].buttons.count, 1)
        XCTAssertEqual(updated.groups[0].buttons[0].id, "b2")
    }

    func testReorderButtonsWithinGroup() throws {
        let updated = try PresetEditor.reorderButtons(
            ids: ["b2", "b1"], inGroupId: "g1", in: samplePreset()
        )
        XCTAssertEqual(updated.groups[0].buttons.map(\.id), ["b2", "b1"])
    }

    func testMoveButtonBetweenGroups() throws {
        let updated = try PresetEditor.moveButton(
            buttonId: "b1", toGroupId: "g2", at: nil, in: samplePreset()
        )
        XCTAssertFalse(updated.groups[0].buttons.contains { $0.id == "b1" })
        XCTAssertTrue(updated.groups[1].buttons.contains { $0.id == "b1" })
    }

    func testMoveButtonToPosition() throws {
        let updated = try PresetEditor.moveButton(
            buttonId: "b1", toGroupId: "g2", at: 0, in: samplePreset()
        )
        XCTAssertEqual(updated.groups[1].buttons.first?.id, "b1")
    }

    // MARK: - Patch convenience

    func testPatchKeepsUnchangedFields() {
        var btn = ButtonDefinition(id: "x", label: "original",
                                   iconText: "🧠",
                                   action: .key(combo: "a"))
        btn.patch(label: "updated")
        XCTAssertEqual(btn.label, "updated")
        XCTAssertEqual(btn.iconText, "🧠") // unchanged
    }

    /// Passing `Optional<Optional<T>>.some(.none)` (i.e. `.some(nil)`)
    /// explicitly clears a field.
    func testPatchCanClearOptionalField() {
        var btn = ButtonDefinition(id: "x", label: "L",
                                   icon: "/path/to.png",
                                   action: .key(combo: "a"))
        btn.patch(icon: Optional<String?>.some(nil))
        XCTAssertNil(btn.icon)
    }
}
