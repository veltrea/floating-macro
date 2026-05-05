import XCTest
@testable import FloatingMacroCore

final class ConfigLoaderTests: XCTestCase {
    func testButtonDefinitionRoundTripIncludesTextColor() throws {
        let btn = ButtonDefinition(
            id: "b-tc", label: "with colors",
            iconText: "🧠",
            backgroundColor: "#FF6B00",
            textColor: "#222222",
            width: 140, height: 36,
            action: .key(combo: "cmd+a")
        )
        let data = try JSONEncoder().encode(btn)
        let decoded = try JSONDecoder().decode(ButtonDefinition.self, from: data)
        XCTAssertEqual(decoded, btn)
        XCTAssertEqual(decoded.textColor, "#222222")
    }

    func testButtonDefinitionLegacyJSONWithoutTextColor() throws {
        // Pre-textColor configs must still decode (backward compat via decodeIfPresent).
        let json = #"""
        {
          "id": "legacy",
          "label": "old",
          "action": { "type": "key", "combo": "cmd+v" }
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ButtonDefinition.self, from: json)
        XCTAssertNil(decoded.textColor)
        XCTAssertNil(decoded.backgroundColor)
    }

    func testActionRoundTrip() throws {
        let actions: [Action] = [
            .key(combo: "cmd+v"),
            .text(content: "hello", pasteDelayMs: 120, restoreClipboard: true, appendMode: false),
            .text(content: "fragment, ", pasteDelayMs: 120, restoreClipboard: true, appendMode: true),
            .launch(target: "/Applications/Slack.app"),
            .terminal(app: "iTerm", command: "cd ~ && ls", newWindow: true, execute: true, profile: nil),
            .delay(ms: 500),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for action in actions {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(Action.self, from: data)
            XCTAssertEqual(action, decoded)
        }
    }

    func testMacroRoundTrip() throws {
        let macro = Action.macro(
            actions: [
                .key(combo: "cmd+a"),
                .delay(ms: 100),
                .text(content: "test", pasteDelayMs: 120, restoreClipboard: true, appendMode: false),
            ],
            stopOnError: true
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(macro)
        let decoded = try decoder.decode(Action.self, from: data)
        XCTAssertEqual(macro, decoded)
    }

    func testNestedMacroRejected() throws {
        let json = """
        {
            "type": "macro",
            "actions": [
                {
                    "type": "macro",
                    "actions": [
                        { "type": "key", "combo": "cmd+v" }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Action.self, from: json))
    }

    func testTextDefaults() throws {
        let json = """
        { "type": "text", "content": "hello" }
        """.data(using: .utf8)!

        let action = try JSONDecoder().decode(Action.self, from: json)
        if case .text(let content, let delay, let restore, let append) = action {
            XCTAssertEqual(content, "hello")
            XCTAssertEqual(delay, 120)
            XCTAssertTrue(restore)
            XCTAssertFalse(append, "appendMode must default to false for legacy preset files")
        } else {
            XCTFail("Expected text action")
        }
    }

    /// Decoding an explicit appendMode field round-trips and is preserved
    /// through encode → decode.
    func testTextAppendModeRoundTrip() throws {
        let original = Action.text(content: "anime, ", pasteDelayMs: 80,
                                   restoreClipboard: false, appendMode: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Action.self, from: data)
        XCTAssertEqual(decoded, original)

        // appendMode=false is omitted from the encoded JSON to keep older
        // preset files clean.
        let plain = Action.text(content: "x", pasteDelayMs: 120,
                                restoreClipboard: true, appendMode: false)
        let plainData = try JSONEncoder().encode(plain)
        let plainStr = String(data: plainData, encoding: .utf8) ?? ""
        XCTAssertFalse(plainStr.contains("appendMode"),
                       "appendMode=false should not be emitted")
    }

    func testTerminalDefaults() throws {
        let json = """
        { "type": "terminal", "command": "ls" }
        """.data(using: .utf8)!

        let action = try JSONDecoder().decode(Action.self, from: json)
        if case .terminal(let app, let command, let newWindow, let execute, let profile) = action {
            XCTAssertEqual(app, "Terminal")
            XCTAssertEqual(command, "ls")
            XCTAssertTrue(newWindow)
            XCTAssertTrue(execute)
            XCTAssertNil(profile)
        } else {
            XCTFail("Expected terminal action")
        }
    }

    func testPresetRoundTrip() throws {
        let preset = Preset(
            name: "test",
            displayName: "テスト",
            groups: [
                ButtonGroup(
                    id: "g1",
                    label: "Group 1",
                    buttons: [
                        ButtonDefinition(
                            id: "b1",
                            label: "Button 1",
                            iconText: "🔥",
                            action: .key(combo: "cmd+v")
                        )
                    ]
                )
            ]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(preset)
        let decoded = try decoder.decode(Preset.self, from: data)
        XCTAssertEqual(preset, decoded)
    }

    /// Phase 2 で追加した `ButtonGroup.displayType` が `wide` / `card` のとき
    /// JSON にエンコード → デコードしても値が保たれることを検証する。
    func testButtonGroupDisplayTypeRoundTrip() throws {
        for type in [GroupDisplayType.wide, .card] {
            let group = ButtonGroup(
                id: "g-thumb",
                label: "Group",
                displayType: type,
                buttons: [
                    ButtonDefinition(
                        id: "b1",
                        label: "Card B",
                        thumbnail: "/tmp/sample.png",
                        action: .text(content: "hi", pasteDelayMs: 100,
                                       restoreClipboard: true, appendMode: false)
                    )
                ]
            )
            let data = try JSONEncoder().encode(group)
            let decoded = try JSONDecoder().decode(ButtonGroup.self, from: data)
            XCTAssertEqual(decoded.displayType, type)
            XCTAssertEqual(decoded.buttons.first?.thumbnail, "/tmp/sample.png")
        }
    }

    /// `displayType: .icon` (既定値) はエンコード結果に出力されない。
    /// 既存プリセットファイルが意図せず差分扱いされない後方互換配慮。
    func testButtonGroupDefaultDisplayTypeOmittedFromEncoding() throws {
        let group = ButtonGroup(id: "g1", label: "G", buttons: [])
        let data = try JSONEncoder().encode(group)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(str.contains("displayType"),
                       "displayType=icon should not be emitted; got: \(str)")
    }

    /// 旧プリセット（displayType フィールドが無い JSON）をロードすると
    /// `.icon` にフォールバックする。
    func testButtonGroupLegacyJSONWithoutDisplayType() throws {
        let legacy = """
        {
            "id": "g-legacy",
            "label": "Legacy",
            "buttons": []
        }
        """.data(using: .utf8)!
        let group = try JSONDecoder().decode(ButtonGroup.self, from: legacy)
        XCTAssertEqual(group.displayType, .icon)
    }

    /// `ButtonDefinition.thumbnail` が JSON ラウンドトリップで保たれる。
    /// 旧プリセット（thumbnail フィールド無し）では nil でロードされる。
    func testButtonDefinitionThumbnailRoundTrip() throws {
        let original = ButtonDefinition(
            id: "b1",
            label: "L",
            thumbnail: "~/Pictures/x.jpg",
            action: .key(combo: "cmd+a")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ButtonDefinition.self, from: data)
        XCTAssertEqual(decoded.thumbnail, "~/Pictures/x.jpg")

        let legacy = """
        {
            "id": "b2",
            "label": "Legacy",
            "action": {"type": "key", "combo": "cmd+v"}
        }
        """.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(ButtonDefinition.self, from: legacy)
        XCTAssertNil(legacyDecoded.thumbnail)
    }

    func testAppConfigRoundTrip() throws {
        let config = AppConfig(
            version: 1,
            activePreset: "dev",
            window: WindowConfig(x: 200, y: 300, orientation: "horizontal")
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(AppConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testUnknownActionType() {
        let json = """
        { "type": "unknown_type" }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Action.self, from: json))
    }

    func testPresetFromSpecExample() throws {
        let json = """
        {
          "version": 1,
          "name": "default",
          "displayName": "デフォルト",
          "groups": [
            {
              "id": "group-1",
              "label": "AI",
              "collapsed": false,
              "buttons": [
                {
                  "id": "btn-ultrathink",
                  "label": "ultrathink",
                  "icon": null,
                  "iconText": "🧠",
                  "action": {
                    "type": "text",
                    "content": "ultrathink で次のタスクに取り組んでください。"
                  }
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let preset = try JSONDecoder().decode(Preset.self, from: json)
        XCTAssertEqual(preset.name, "default")
        XCTAssertEqual(preset.groups.count, 1)
        XCTAssertEqual(preset.groups[0].buttons.count, 1)
        XCTAssertEqual(preset.groups[0].buttons[0].id, "btn-ultrathink")
    }
}
