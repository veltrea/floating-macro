# Settings Test API — 設計仕様

テスト自動実行モード（`agentMode = test`）でAIがSettings画面のすべてのUI操作を自動化できるようにするための追加API設計。

## 背景

通常モードではバッチ操作（`button_add` × N）で十分だが、テスト自動化では以下が必要：
- 設定画面を開き、特定ボタン/グループをプログラムから選択する
- アプリアイコンピッカーを開く（SFピッカーは既存）
- `ButtonEditor` のアクションタブをプログラムから切り替える

`onChange(of: button)` はすでに実装済み（`SettingsDetail.swift`）。
これにより `button_update` 呼び出し後、設定画面のフォームが自動追従する。

---

## 実装タスク

### B: 設定画面でボタン/グループを選択する

#### 新規エンドポイント

```
POST /settings/select-button   { "id": "button-id" }
POST /settings/select-group    { "id": "group-id" }
```

#### 実装方針

`PresetManager` に `externalSelectButtonRequest` / `externalSelectGroupRequest` がすでにある。
`SettingsView.swift:30` でこれを監視済み。

1. `ControlHandlers.swift` にハンドラー2つ追加
   - `handleSettingsSelectButton(_ req)` → `presetManager.externalSelectButtonRequest = id`
   - `handleSettingsSelectGroup(_ req)` → `presetManager.externalSelectGroupRequest = id`
2. `ControlHandlers.swift` の `dispatch()` にルーティング追加
3. `ToolCatalog.swift` に2エントリ追加

---

### C: アプリアイコンピッカーを開く

#### 新規エンドポイント

```
POST /settings/open-app-icon-picker
```

#### 実装方針

SFシンボルピッカーと完全に同じ nonce 方式で実装する。

1. `PresetManager` に `appIconPickerRequestNonce: Int` プロパティを追加
   （`sfPickerRequestNonce` と同じ構造）
2. `ButtonEditor`（`SettingsDetail.swift`）に `.onChange(of: presetManager.appIconPickerRequestNonce)` を追加
   → `showingAppIconPicker = true`
3. `GroupEditor` にも同様に追加（グループにもアプリアイコン選択がある）
4. `ControlHandlers.swift` に `handleSettingsOpenAppIconPicker()` を追加
   → `presetManager.requestAppIconPicker()` を呼ぶ
5. `PresetManager` に `requestAppIconPicker()` メソッドを追加
6. `ControlHandlers.swift` の `dispatch()` にルーティング追加
7. `ToolCatalog.swift` に1エントリ追加

参照実装: `PresetManager` の `sfPickerRequestNonce` / `requestSFPicker()`

---

### D: アクションタブを切り替える

#### 新規エンドポイント

```
POST /settings/set-action-type   { "type": "text" | "key" | "launch" | "terminal" }
```

#### 実装方針

`ButtonEditor.actionType` は `@State` のローカル変数なので、nonce 方式で外部から操作する。

1. `PresetManager` に以下を追加：
   ```swift
   @Published public var externalActionTypeRequest: String? = nil
   ```
2. `ButtonEditor`（`SettingsDetail.swift`）に `.onChange` を追加：
   ```swift
   .onChange(of: presetManager.externalActionTypeRequest) { requested in
       guard let type = requested else { return }
       actionType = type
       presetManager.externalActionTypeRequest = nil
   }
   ```
3. `ControlHandlers.swift` に `handleSettingsSetActionType(_ req)` を追加
   → `presetManager.externalActionTypeRequest = type`
4. `ControlHandlers.swift` の `dispatch()` にルーティング追加
5. `ToolCatalog.swift` に1エントリ追加

---

## ToolCatalog に追加するエントリ（まとめ）

```swift
// MARK: - Settings window — test automation
.init(name: "settings_select_button",
      description: "Select a button in the Settings window by id. Opens Settings if not already open.",
      method: "POST", path: "/settings/select-button",
      inputSchema: object(["id": stringSchema()], required: ["id"])),

.init(name: "settings_select_group",
      description: "Select a group in the Settings window by id.",
      method: "POST", path: "/settings/select-group",
      inputSchema: object(["id": stringSchema()], required: ["id"])),

.init(name: "settings_open_app_icon_picker",
      description: "Open the app icon picker sheet in the Settings window (opens Settings if needed).",
      method: "POST", path: "/settings/open-app-icon-picker",
      inputSchema: emptyObject()),

.init(name: "settings_set_action_type",
      description: "Switch the action type tab in the button editor. type: text | key | launch | terminal",
      method: "POST", path: "/settings/set-action-type",
      inputSchema: object([
          "type": stringSchema(description: "text | key | launch | terminal")
      ], required: ["type"])),
```

---

## 既存の関連実装（参照用）

| 対象 | ファイル | 行 |
|---|---|---|
| `externalSelectButtonRequest` 監視 | `SettingsView.swift` | 30–35 |
| `externalSelectGroupRequest` 監視 | `SettingsView.swift` | 36–41 |
| `sfPickerRequestNonce` 監視 | `SettingsDetail.swift` | 307–309 |
| `requestSFPicker()` | `PresetManager`（要確認） | — |
| `handleSettingsOpenSFPicker()` | `ControlHandlers.swift` | 422–429 |
| `onChange(of: button)` 追加済み | `SettingsDetail.swift` | 308 |
| `onChange(of: group)` 追加済み | `SettingsDetail.swift` | 632 |
