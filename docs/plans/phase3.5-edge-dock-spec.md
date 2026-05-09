# Phase 3.5 — 縁にドック最小化：仕様設計書

最終更新: 2026-05-06
状態: **設計完了・実装待ち**

---

## 0. 目的

フローティングパネルを画面端に「薄いバー」として格納する UI を追加する。
現在の MiniIconPanel (48×48 の丸アイコン) に対して：

- **どのパネルか一目でわかる**（アイコン + プリセット名を表示）
- **画面四辺に整理**される（複数パネルが重ならない）
- **AI からも操作可能**（`panel_dock` / `panel_undock` ツール）

既存の MiniIconPanel は**廃止しない**。× ボタンの挙動を「縁にドック」に変更し、
MiniIconPanel は互換のために残すが、新規導線はすべて縁ドックに向ける。

---

## 1. 用語

| 用語 | 意味 |
|---|---|
| **EdgeDockBar** | 画面端に張り付く細長いバー（新規 NSPanel サブクラス） |
| **展開状態** | 通常のフローティングパネルが表示されている状態 |
| **ドック状態** | パネルが画面端のバーに格納されている状態 |
| **ドック辺** | バーが張り付いている画面の辺（left / right / top / bottom） |

---

## 2. データモデル変更

### 2.1 PanelConfig の拡張

```swift
public struct PanelConfig: Codable, Equatable, Sendable {
    // 既存フィールド（変更なし）
    public let id: String
    public var presetName: String
    public var window: WindowConfig
    public var visible: Bool
    public var scrollY: Double

    // ── Phase 3.5 変更 ──

    /// 縁にドックされた状態。nil = 通常表示（展開中）。
    /// Phase 3 で Bool だった minimizedToEdge を DockEdge? に型変更。
    /// 旧 JSON (Bool) との後方互換は decoder で吸収。
    public var dockedEdge: DockEdge?
}
```

### 2.2 DockEdge enum（新規）

```swift
public enum DockEdge: String, Codable, Sendable {
    case left
    case right
    case top
    case bottom
}
```

### 2.3 旧 `minimizedToEdge: Bool` からの移行

Phase 3 で `minimizedToEdge: Bool` として保存されているデータとの互換：

```swift
// PanelConfig の init(from decoder:) 内
if let edge = try? container.decode(DockEdge.self, forKey: .dockedEdge) {
    self.dockedEdge = edge
} else if let legacy = try? container.decode(Bool.self, forKey: .minimizedToEdge),
          legacy == true {
    self.dockedEdge = .right   // 旧 true → デフォルトで右辺
} else {
    self.dockedEdge = nil
}
```

encode 時は `dockedEdge` のみ書き出す。`minimizedToEdge` キーは書かない。
`dockedEdge` が nil なら キー自体を省略（既存ファイルとの差分ゼロ）。

### 2.4 AppConfig+Panels.swift の変更

既存の `settingPanelMinimizedToEdge(id:minimizedToEdge:)` を以下に置換：

```swift
/// パネルをドック状態にする
public func dockingPanel(id: String, edge: DockEdge) -> AppConfig

/// パネルをドックから展開する
public func undockingPanel(id: String) -> AppConfig
```

---

## 3. EdgeDockBar の設計

### 3.1 外観

```
┌──────────────────────┐
│  🚀  ランチャー       │   ← 右辺 / 左辺の場合は縦書き
└──────────────────────┘
```

| 属性 | 値 |
|---|---|
| 背景 | パネルと同じ紫グラデーション、角丸 6pt |
| アイコン | プリセットの先頭グループの先頭ボタンの icon（16pt） |
| ラベル | プリセットの displayName（10pt、1行打ち切り） |
| 辺配置 | left / right → 縦長バー（幅 28pt、高さ可変）、top / bottom → 横長バー（高さ 26pt、幅可変） |

### 3.2 NSPanel 設定

MiniIconPanel と同じ基本設定：

```swift
styleMask: [.nonactivatingPanel, .fullSizeContentView]
level: .floating
collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
hidesOnDeactivate: false
canBecomeKey: false
canBecomeMain: false
backgroundColor: .clear
isOpaque: false
isMovableByWindowBackground: false   // ← 移動不可（位置は辺に固定）
```

### 3.3 サイズ計算

```
縦バー (left / right):
  幅 = 28pt
  高さ = max(80, アイコン(16) + 余白(8) + ラベル文字数 × 12 + 余白(8))
  最大高さ = 画面高さの 1/3

横バー (top / bottom):
  高さ = 26pt
  幅 = max(80, アイコン(16) + 余白(8) + ラベル幅 + 余白(8))
  最大幅 = 画面幅の 1/3
```

### 3.4 位置計算

画面端に密着配置。同一辺に複数バーがある場合は順番に並べる（重ならない）。

```
right 辺の例:
  screen.maxX に右端を揃え
  y = screen.midY を基準に、同一辺のバー群を中央寄せで配置
  バー間の隙間 = 4pt

left 辺の例:
  screen.minX に左端を揃え
  y = 同上

top 辺の例:
  screen.maxY - menuBarHeight に上端を揃え
  x = screen.midX を基準に中央寄せ

bottom 辺の例:
  screen.minY + dockHeight に下端を揃え
  x = 同上
```

**位置算出は Core 側に純粋関数として実装** → 単体テスト可能：

```swift
/// Core に配置
public struct EdgeDockLayout {
    /// 同一辺のバーの位置を計算する
    /// - screenFrame: NSScreen.visibleFrame (menuBar/Dock 除外済み)
    /// - bars: この辺にドックされているバーの (id, size) 配列
    /// - returns: 各 id に対応する origin (x, y)
    static func positions(
        edge: DockEdge,
        screenFrame: CGRect,
        bars: [(id: String, size: CGSize)]
    ) -> [(id: String, origin: CGPoint)]
}
```

---

## 4. 操作フロー

### 4.1 ドック化のトリガー

| トリガー | 動作 |
|---|---|
| **パネルの × ボタン** | 現在の MiniIconPanel 化 → **縁にドック**に変更 |
| **メニューバー → パネル → 「縁にドック ▸」サブメニュー** | 辺を選択してドック化 |
| **コンテキストメニュー（パネル右クリック）** | 「縁にドック ▸」サブメニュー |
| **Control API: `panel_dock`** | AI からの操作 |

### 4.2 展開のトリガー

| トリガー | 動作 |
|---|---|
| **EdgeDockBar を左クリック** | パネルを展開、バーを非表示 |
| **メニューバー → パネル → パネル名をクリック** | 既存の toggle と同じ（ドック中なら展開） |
| **Control API: `panel_undock`** | AI からの操作 |

### 4.3 EdgeDockBar の右クリック

コンテキストメニューを表示：

```
展開
──────
別の辺に移動 ▸
  ├ 左
  ├ 右
  ├ 上
  └ 下
──────
閉じて削除
```

### 4.4 ドック化アニメーション（任意・後回し可）

1. パネルが縮小しながら対象辺にスライド（0.25 秒、easeInOut）
2. EdgeDockBar がフェードイン（0.15 秒）

初期実装はアニメーションなし（即切替）でも可。

---

## 5. × ボタンの挙動変更

### 5.1 現在

```
× ボタン → floatingPanelWantsCollapse 通知 → PanelManager.collapseToMini
→ パネル orderOut → MiniIconPanel orderFront
```

### 5.2 Phase 3.5 後

```
× ボタン → floatingPanelWantsCollapse 通知 → PanelManager.collapseToDock
→ dockedEdge を自動決定（パネル中心から最寄りの辺）
→ パネル orderOut → EdgeDockBar orderFront
→ AppConfig 更新（dockedEdge = 決定した辺）
```

**最寄り辺の自動決定ロジック（Core 側に配置）：**

```swift
public struct EdgeDetector {
    /// パネルの中心座標から最寄りの画面辺を判定する
    static func nearestEdge(
        panelCenter: CGPoint,
        screenFrame: CGRect
    ) -> DockEdge {
        let distances: [(DockEdge, CGFloat)] = [
            (.left,   panelCenter.x - screenFrame.minX),
            (.right,  screenFrame.maxX - panelCenter.x),
            (.top,    screenFrame.maxY - panelCenter.y),
            (.bottom, panelCenter.y - screenFrame.minY),
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }
}
```

---

## 6. PanelManager の変更

### 6.1 Entry 拡張

```swift
private struct Entry {
    let panel: FloatingPanel
    let mini: MiniIconPanel       // 互換のため残す
    var dockBar: EdgeDockBar?     // Phase 3.5 で追加（遅延生成）
}
```

### 6.2 新規メソッド

```swift
/// パネルを縁にドックする
func collapseToDock(id: String, edge: DockEdge)

/// ドックからパネルを展開する
func expandFromDock(id: String)

/// すべての EdgeDockBar の位置を再計算する（同一辺の並び替え）
func relayoutDockBars()

/// 起動時のドック状態復元
func restoreDockedPanels(from configs: [PanelConfig])
```

### 6.3 collapseToMini との共存

- × ボタン → `collapseToDock`（新デフォルト）
- `collapseToMini` は残す（互換・オプション）
- `panel_hide` は従来通り（非表示化、ドック化ではない）

---

## 7. Control API ツール追加

### 7.1 `panel_dock`

```json
{
  "name": "panel_dock",
  "description": "Dock a panel to the nearest screen edge as a thin bar. The panel is hidden and replaced by a small label bar at the edge. Click the bar to expand.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id": { "type": "string", "description": "Panel ID" },
      "edge": {
        "type": "string",
        "enum": ["left", "right", "top", "bottom"],
        "description": "Screen edge to dock to. Omit to auto-detect nearest edge."
      }
    },
    "required": ["id"]
  },
  "method": "POST",
  "path": "/panel/dock"
}
```

### 7.2 `panel_undock`

```json
{
  "name": "panel_undock",
  "description": "Expand a docked panel back to its normal floating state.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "id": { "type": "string", "description": "Panel ID" }
    },
    "required": ["id"]
  },
  "method": "POST",
  "path": "/panel/undock"
}
```

### 7.3 既存ツールへの影響

- `panel_list`: レスポンスに `dockedEdge` フィールドを追加（null or "left"/"right"/"top"/"bottom"）。旧 `minimizedToEdge` は削除
- `panel_show`: ドック中のパネルに対して呼ばれたら `expandFromDock` → 通常表示
- `panel_move` / `panel_resize`: ドック中は無視してエラー返却（「先に undock してください」）

---

## 8. メニューバーの変更

### 8.1 パネルサブメニューの拡張

```
パネル
├ 新しいパネルを追加
├ ──────
├ ✓ ランチャー
│   ├ 縁にドック ▸
│   │   ├ 左
│   │   ├ 右
│   │   ├ 上
│   │   └ 下
│   └ 閉じて削除
├   Midjourney ギャラリー 〔ドック中: 右〕
│   ├ 展開
│   ├ 別の辺に移動 ▸
│   │   ├ 左
│   │   ├ 上
│   │   └ 下
│   └ 閉じて削除
```

ドック中のパネルは表示名の横に `〔ドック中: 右〕` などの注釈を付け、
サブメニューを「展開」「別の辺に移動」に切り替える。

---

## 9. 起動時の復元

`PanelManager.openInitial(from:)` の中で：

1. `dockedEdge != nil` のパネルは FloatingPanel を生成するが `orderOut` のまま
2. EdgeDockBar を生成して `orderFront`
3. `relayoutDockBars()` で同一辺のバー配置を計算

---

## 10. マルチモニタ対応

- ドック辺はパネルが**最後に表示されていたスクリーン**の辺に張り付く
- `EdgeDockLayout.positions()` はスクリーンの `visibleFrame` を受け取るので、モニタごとに独立して位置計算できる
- 将来的にモニタ間の移動が必要になったら `panel_dock` に `screenIndex` パラメータを追加

---

## 11. テスト計画

### 11.1 Core（単体テスト）

| テスト | 内容 |
|---|---|
| `DockEdgeRoundTrip` | DockEdge の encode/decode |
| `PanelConfigDockedEdgeMigration` | 旧 `minimizedToEdge: true` → `dockedEdge: .right` |
| `PanelConfigDockedEdgeNilOmitted` | `dockedEdge: nil` → JSON キー省略 |
| `AppConfigDockingPanel` | `dockingPanel(id:edge:)` の戻り値検証 |
| `AppConfigUndockingPanel` | `undockingPanel(id:)` の戻り値検証 |
| `EdgeDetectorNearest` | 四象限のパネル位置 → 期待される辺 |
| `EdgeDetectorCorner` | 角付近のパネル → 距離が近い辺 |
| `EdgeDockLayoutSingleBar` | 1本のバー → 辺の中央配置 |
| `EdgeDockLayoutMultipleBars` | 3本のバー → 中央寄せ・隙間 4pt |
| `EdgeDockLayoutScreenBounds` | バーが画面をはみ出さない |
| `ToolCatalogDockTools` | `panel_dock` / `panel_undock` がカタログに存在 |

### 11.2 App（実機テスト手順）

```bash
# ビルド & 起動
bash scripts/build-app.sh && bash scripts/rebuild-and-relaunch.sh

# トークン取得
TOKEN=$(cat ~/Library/Application\ Support/FloatingMacro/control_api_token)

# ドック化
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"panel_dock","arguments":{"id":"<PANEL_ID>","edge":"right"}}'

# 状態確認
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/tools/call \
  -d '{"name":"panel_list","arguments":{}}'
# → dockedEdge: "right" を確認

# 展開
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"panel_undock","arguments":{"id":"<PANEL_ID>"}}'

# × ボタンクリックでドック化されることを目視確認
# EdgeDockBar の左クリックで展開されることを目視確認
# EdgeDockBar の右クリックでメニューが出ることを目視確認
```

---

## 12. ファイル変更一覧（実装時のチェックリスト）

### Core 層（FloatingMacroCore）

| ファイル | 変更内容 |
|---|---|
| `Config/Preset.swift` | `DockEdge` enum 追加、`PanelConfig.minimizedToEdge` → `dockedEdge: DockEdge?` に型変更、decoder で旧 Bool 互換 |
| `Config/AppConfig+Panels.swift` | `dockingPanel` / `undockingPanel` 追加、旧 `settingPanelMinimizedToEdge` 削除 |
| `ControlAPI/ToolCatalog.swift` | `panel_dock` / `panel_undock` ツール定義追加、`panel_list` の schema 更新 |
| **新規** `UI/EdgeDockLayout.swift` | バー位置計算の純粋関数 |
| **新規** `UI/EdgeDetector.swift` | 最寄り辺判定の純粋関数 |

### App 層（FloatingMacroApp）

| ファイル | 変更内容 |
|---|---|
| **新規** `EdgeDockBar.swift` | NSPanel サブクラス。描画・クリック・右クリック処理 |
| `PanelManager.swift` | Entry に `dockBar` 追加、`collapseToDock` / `expandFromDock` / `relayoutDockBars` 追加 |
| `App.swift` | × ボタンのコールバックを `collapseToDock` に変更、メニュー構築に「縁にドック」サブメニュー追加、起動復元にドック状態を追加 |
| `ControlAPI/ControlHandlers.swift` | `panel_dock` / `panel_undock` ハンドラ追加、`panel_list` レスポンス更新 |
| `MiniIconPanel.swift` | 変更なし（互換のため残置） |

### Tests

| ファイル | 変更内容 |
|---|---|
| `ConfigLoaderTests.swift` | `dockedEdge` の encode/decode / 旧互換テスト追加 |
| `AppConfigPanelOpsTests.swift` | `dockingPanel` / `undockingPanel` テスト追加 |
| **新規** `EdgeDockLayoutTests.swift` | 位置計算テスト |
| **新規** `EdgeDetectorTests.swift` | 最寄り辺テスト |
| `ToolCatalogTests.swift` | ツール数の期待値更新 |

### ドキュメント

| ファイル | 変更内容 |
|---|---|
| `docs/AI_PROTOCOL.md` / `.ja.md` | `panel_dock` / `panel_undock` ツール記載 |
| `SPEC.md` | §6 PanelConfig に `dockedEdge` 追記、§17 に v0.13.x 章追加 |
| `CHANGELOG.md` | Phase 3.5 エントリ追加 |
| `docs/plans/visual-expansion-roadmap.md` | Phase 3.5 タスクにチェック |

---

## 13. 実装順序（推奨）

1. **Core: データモデル** — `DockEdge` enum、`PanelConfig.dockedEdge` 型変更、旧互換 decoder、`AppConfig+Panels` の操作関数 → テスト
2. **Core: 位置計算** — `EdgeDetector` + `EdgeDockLayout` → テスト
3. **Core: ToolCatalog** — `panel_dock` / `panel_undock` 定義 → テスト
4. **App: EdgeDockBar** — NSPanel サブクラス、描画、クリック/右クリック
5. **App: PanelManager 統合** — `collapseToDock` / `expandFromDock` / `relayoutDockBars`
6. **App: × ボタン変更** — `floatingPanelWantsCollapse` → `collapseToDock`
7. **App: メニュー変更** — 「縁にドック ▸」サブメニュー
8. **App: ControlHandlers** — `panel_dock` / `panel_undock` ハンドラ
9. **App: 起動復元** — ドック状態のパネルを EdgeDockBar として復元
10. **ドキュメント更新** — AI_PROTOCOL / SPEC / CHANGELOG / ロードマップ
11. **実機テスト** — `build-app.sh` + `rebuild-and-relaunch.sh` + curl 検証

---

## 14. スコープ外（やらないこと）

- アニメーション（初期は即切替。効果があれば後で追加）
- ドラッグでの辺変更（右クリックメニューの「別の辺に移動」で代替）
- マルチモニタ間のドック移動（将来の拡張ポイントとして設計は考慮済み）
- MiniIconPanel の廃止（互換のため残置）
- EdgeDockBar の auto-hide（ホバーで表示）— 別 Phase
