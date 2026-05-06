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

    func testButtonCardThumbnailModeRoundTrip() throws {
        let btn = ButtonDefinition(id: "b-fit", label: "Fit",
                                   cardThumbnailMode: .fit,
                                   action: .key(combo: "cmd+a"))
        let data = try JSONEncoder().encode(btn)
        let decoded = try JSONDecoder().decode(ButtonDefinition.self, from: data)
        XCTAssertEqual(decoded.cardThumbnailMode, .fit)
    }

    func testButtonCardThumbnailModeDefaultOmittedFromEncoding() throws {
        let btn = ButtonDefinition(id: "b1", label: "B",
                                   action: .key(combo: "cmd+a"))
        let data = try JSONEncoder().encode(btn)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(str.contains("cardThumbnailMode"),
                       "cardThumbnailMode=fill should not be emitted; got: \(str)")
    }

    func testButtonCardThumbnailModeLegacyFallback() throws {
        let legacy = """
        {"id": "b-old", "label": "Old", "action": {"type": "key", "combo": "cmd+a"}}
        """.data(using: .utf8)!
        let btn = try JSONDecoder().decode(ButtonDefinition.self, from: legacy)
        XCTAssertEqual(btn.cardThumbnailMode, .fill)
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

    // MARK: - Phase 3 (P3-1 / P3-2): PanelConfig & AppConfig.panels migration

    func testPanelConfigRoundTrip() throws {
        let panel = PanelConfig(
            id: "panel-launcher",
            presetName: "default",
            window: WindowConfig(x: 50, y: 60, width: 240, height: 400),
            dockedEdge: .right,
            visible: false
        )
        let data = try JSONEncoder().encode(panel)
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: data)
        XCTAssertEqual(panel, decoded)
        XCTAssertEqual(decoded.id, "panel-launcher")
        XCTAssertEqual(decoded.dockedEdge, .right)
        XCTAssertFalse(decoded.visible)
    }

    func testPanelConfigDecodesMinimalJSON() throws {
        let json = #"""
        { "id": "p1", "presetName": "default" }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertEqual(decoded.id, "p1")
        XCTAssertEqual(decoded.presetName, "default")
        XCTAssertEqual(decoded.window, WindowConfig())
        XCTAssertNil(decoded.dockedEdge)
        XCTAssertTrue(decoded.visible)
    }

    func testPanelConfigGeneratesIDWhenMissing() throws {
        // 手書き JSON で id を省いても UUID が割り当たる（書き戻しで永続化される想定）。
        let json = #"""
        { "presetName": "midjourney" }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertFalse(decoded.id.isEmpty)
        XCTAssertEqual(decoded.presetName, "midjourney")
    }

    func testAppConfigLegacyJSONMigratesToSinglePanel() throws {
        // v1 互換 JSON（panels フィールド無し）→ activePreset + window から 1 件の Panel を自動生成。
        let json = #"""
        {
          "version": 1,
          "activePreset": "midjourney",
          "window": { "x": 300, "y": 400, "width": 320, "height": 480, "orientation": "horizontal", "alwaysOnTop": true, "hideAfterAction": false, "opacity": 0.95 }
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.panels.count, 1)
        XCTAssertEqual(decoded.panels[0].presetName, "midjourney")
        XCTAssertEqual(decoded.panels[0].window.x, 300)
        XCTAssertEqual(decoded.panels[0].window.opacity, 0.95)
        XCTAssertNil(decoded.panels[0].dockedEdge)
        XCTAssertTrue(decoded.panels[0].visible)
        XCTAssertFalse(decoded.panels[0].id.isEmpty)
    }

    func testAppConfigEmptyPanelsArrayMigrates() throws {
        // 明示的に空配列で書かれた JSON も同じ移行ロジックに乗る。
        let json = #"""
        {
          "version": 1,
          "activePreset": "default",
          "window": { "x": 100, "y": 100, "orientation": "vertical", "alwaysOnTop": true, "hideAfterAction": false, "opacity": 1.0 },
          "panels": []
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.panels.count, 1)
        XCTAssertEqual(decoded.panels[0].presetName, "default")
    }

    func testAppConfigWithMultiplePanelsRoundTrips() throws {
        let panels = [
            PanelConfig(id: "p-launcher", presetName: "default",
                        window: WindowConfig(x: 50, y: 50)),
            PanelConfig(id: "p-mj", presetName: "midjourney-gallery",
                        window: WindowConfig(x: 600, y: 50, width: 400, height: 600),
                        visible: true),
            PanelConfig(id: "p-hidden", presetName: "accessibility",
                        window: WindowConfig(),
                        dockedEdge: .left, visible: false),
        ]
        let config = AppConfig(activePreset: "default", panels: panels)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.panels.count, 3)
        XCTAssertEqual(decoded.panels.map(\.id), ["p-launcher", "p-mj", "p-hidden"])
        XCTAssertEqual(decoded.panels[2].presetName, "accessibility")
        XCTAssertEqual(decoded.panels[2].dockedEdge, .left)
        XCTAssertFalse(decoded.panels[2].visible)
    }

    func testPanelConfigDockedEdgeMigrationFromBool() throws {
        let json = #"""
        { "id": "p1", "presetName": "default", "minimizedToEdge": true }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertEqual(decoded.dockedEdge, .right, "旧 minimizedToEdge: true は .right に移行")
    }

    func testPanelConfigDockedEdgeMigrationFalseBecomesNil() throws {
        let json = #"""
        { "id": "p1", "presetName": "default", "minimizedToEdge": false }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PanelConfig.self, from: json)
        XCTAssertNil(decoded.dockedEdge, "旧 minimizedToEdge: false は nil")
    }

    func testPanelConfigDockedEdgeNilOmitted() throws {
        let panel = PanelConfig(id: "p1", presetName: "default")
        let data = try JSONEncoder().encode(panel)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(obj["dockedEdge"], "dockedEdge が nil なら JSON キーを省略")
        XCTAssertNil(obj["minimizedToEdge"], "旧キーは書き出さない")
    }

    func testAppConfigExplicitPanelsTakePrecedenceOverLegacyFields() throws {
        // panels が明示的に指定されている場合は activePreset + window から
        // 自動生成される 1 件目を上書きしない（移行は空のときだけ）。
        let json = #"""
        {
          "version": 1,
          "activePreset": "default",
          "window": { "x": 999, "y": 999 },
          "panels": [
            { "id": "explicit-1", "presetName": "midjourney" }
          ]
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.panels.count, 1)
        XCTAssertEqual(decoded.panels[0].id, "explicit-1")
        XCTAssertEqual(decoded.panels[0].presetName, "midjourney")
        // 旧フィールド自体はそのまま残る（移行期の互換性のため）。
        XCTAssertEqual(decoded.activePreset, "default")
        XCTAssertEqual(decoded.window.x, 999)
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
