# プリセット単位メモ機能の追加計画

## 背景

プリセットには「使う前提の運用上の注意」を残す手段がない。例:

- Studio One Pro 8 用プリセット → 「**システム設定 → キーボード → "F1, F2 などのキーを標準のファンクションキーとして使用" を ON にしないと F3/F4/F5 が macOS に吸われる**」
- AI 用プリセット → 「対象アプリを前面にしてから押す」「クリップボード履歴を上書きするので注意」

ユーザーが時間を空けて使い直す時、これらを忘れてボタンが効かない原因に悩む。
ボタン単位のヒントだけでは「プリセット全体の前提条件」を伝えにくい。

## 実装済みの部分（着手不要）

調査の結果、**ボタン単位のヒント（tooltip）は既に全部入っている**。

- `ButtonDefinition.tooltip: String?` ([ButtonDefinition.swift:22](../../Sources/FloatingMacroCore/Config/ButtonDefinition.swift))
- `ButtonGroup.tooltip: String?` ([Preset.swift:16](../../Sources/FloatingMacroCore/Config/Preset.swift))
- パネルでのホバー表示 ([ButtonView.swift:89-101](../../Sources/FloatingMacroApp/ButtonView.swift))
- 編集 UI のテキストフィールド ([SettingsDetail.swift:363, 775](../../Sources/FloatingMacroApp/Settings/SettingsDetail.swift))
- ACP の `button_add` / `button_update` / `group_add` / `group_update` でも受け付け済み（`ToolCatalog.swift` 要確認）

→ **新セッションでは「プリセット単位メモ」だけ作ればよい**。

## 新規実装

### 1. モデル拡張

[Sources/FloatingMacroCore/Config/Preset.swift](../../Sources/FloatingMacroCore/Config/Preset.swift) の `Preset` 構造体に `memo: String?` を追加。

```swift
public struct Preset: Codable, Equatable {
    public let version: Int
    public let name: String
    public var displayName: String
    public var memo: String?           // ← 追加
    public var groups: [ButtonGroup]
    // ...
}
```

- `decodeIfPresent` で読み、無ければ `nil`（既存プリセット JSON との後方互換 OK）
- `encode` 時、`nil` ならキー自体を出さない（JSON を肥大化させない）

### 2. PresetEditor / ConfigWriter

[Sources/FloatingMacroCore/Config/PresetEditor.swift](../../Sources/FloatingMacroCore/Config/PresetEditor.swift) に `updateMemo(_:)` を追加。
seed プリセット（[ConfigWriter.swift](../../Sources/FloatingMacroCore/Config/ConfigWriter.swift)）に memo 例を 1〜2 個埋めて、ユーザーが新規プリセットを作った時に「こういう書き方をすればいい」が伝わる状態にする。

### 3. パネル UI（表示）

候補は 3 つ:

- **A. パネル上部に折りたたみブロック**: タイトル横に 💬 アイコン → クリックで展開、Markdown 風（最低限 改行と `**bold**` 程度）。デフォルトは畳む。
- **B. ヘッダー右の ⓘ アイコン → ポップオーバー**: 占有面積ゼロ。気付かれにくい欠点。
- **C. パネル最下部にステータスバー風**: 一行だけ常時表示。長文は途中省略。

**推奨: A**。前提条件は「忘れた時に見たい」性質なので、たたんで横に出してる方が用途に合う。
画面幅をほぼ食わない縦パネル運用を考えると、フッター方向よりタイトル直下が違和感少ない。

### 4. 編集 UI

[Sources/FloatingMacroApp/Settings/SettingsView.swift](../../Sources/FloatingMacroApp/Settings/SettingsView.swift) のプリセット詳細ペイン（プリセット名・displayName を編集してる箇所）に `TextEditor`（複数行）を追加。

- ラベル: `メモ（このプリセットの使い方・前提条件）`
- 高さ: 100pt 程度の固定 + スクロール
- 空文字列は保存時に `nil` に正規化

### 5. ACP（HTTP API）拡張

[Sources/FloatingMacroCore/ControlAPI/ToolCatalog.swift](../../Sources/FloatingMacroCore/ControlAPI/ToolCatalog.swift) と [Sources/FloatingMacroApp/ControlAPI/ControlHandlers.swift](../../Sources/FloatingMacroApp/ControlAPI/ControlHandlers.swift):

- `preset_rename` に `memo` パラメータを追加（既存の `displayName` と同じ更新パスに乗せる）か、新規 `preset_set_memo` を切るか
  - **推奨: 既存 `preset_rename` を `preset_update` 相当に拡張** して `displayName` / `memo` を任意更新にする（互換のため `preset_rename` の名前は維持しつつ inputSchema に memo を追加）
- `preset_create` の inputSchema にも `memo` を任意で
- `preset_export` / `preset_export_bundle` は構造体 encode に追従するので自動

### 6. システムプロンプト

[Sources/FloatingMacroCore/Resources/agent_prompts.json](../../Sources/FloatingMacroCore/Resources/agent_prompts.json) に「プリセット作成時に memo を書く」ガイドを 1〜2 文追加。AI が自動でメモを生成・更新できるようにする。

例:
> プリセットを作る・編集する時は memo フィールドに **使う前提条件**（前面にすべきアプリ、必要な OS 設定、想定ユースケース）を書く。書かないと利用者が忘れて押せないキーが出る。

### 7. ドキュメント追従

ユーザーのフィードバックメモ「**バージョン更新は全部一緒に**」に従う。今回はメジャー機能追加なので:

- [CHANGELOG.md](../../CHANGELOG.md) に新項目
- [README.md](../../README.md) / [README.ja.md](../../README.ja.md) のスクリーンショット差し替え or 新節追加（「プリセットメモ」）
- [SPEC.md](../../SPEC.md) の Preset スキーマ説明に memo を追加
- [docs/AI_PROTOCOL.ja.md](../AI_PROTOCOL.ja.md) と [docs/AI_PROTOCOL.md](../AI_PROTOCOL.md) に memo 関連ツール変更を追記
- Info.plist のバージョン bump（`scripts/release.sh`）

## 想定スコープ感

| 領域 | 行数感 |
|---|---|
| モデル + Codable | 数十行 |
| PresetEditor + Writer | 数十行 |
| パネル UI（折りたたみブロック） | 100〜150 行（State 込み） |
| 編集 UI（TextEditor 追加） | 50 行 |
| ACP 拡張 | 50 行 |
| ドキュメント類 | 行数というより範囲広 |

合計 1 セッションで完了可能なサイズ。

## 着手手順

1. ブランチ切る: `git checkout -b feature/preset-memo`
2. モデル → PresetEditor → ACP の順で書き、まず `bash scripts/control_api_smoke.sh` 相当で API レイヤーが通る所まで確認
3. パネル UI → 編集 UI を入れて、`scripts/build-app.sh` で実機確認
4. seed プリセット（ai-onboarding 等）の memo 埋め
5. ドキュメント一式 + バージョン bump
6. コミット → PR

## 落とし穴メモ

- `Preset` 構造体に `Codable` 手書き init/encode があるなら、追加フィールドの decode/encode 漏れ注意（[Preset.swift:48 周辺](../../Sources/FloatingMacroCore/Config/Preset.swift) のパターンを踏襲）
- `PresetWatcher` がファイル変更を検知してリロードするので、編集 UI で memo を書いている最中に保存タイミングが衝突しないかは要確認（既存の displayName 編集と同じ問題なので、その実装に乗ればよい）
- 既存プリセット JSON が `~/Library/Application Support/FloatingMacro/presets/` に残っている。memo フィールドが無い JSON が読めることをユニットテストで保証
