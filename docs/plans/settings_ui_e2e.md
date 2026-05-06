# Settings UI を含めた E2E 検証の拡張

## 目的

現在の `text_inject_e2e.sh` は **ボタンを押した結果**（テキスト貼り付け / キー送出）しか検証していない。**Settings ウィンドウ側 UI**（ボタンエディター、特殊キーメニュー、各種ドロップダウン、ピッカー）の表示異常はカバー範囲外。

実際にユーザーが踏んだバグ（special key を選んでもインジケーターが text のままになる、ドロップダウンが変な位置に出る）はすべて Settings 側で発生している。E2E にここを取り込まないと同種のバグを再発させる。

## 既にある検証手段

- `/tools/call settings_select_button` — id 指定で Settings を開いて特定ボタンを選択状態にできる
- `/tools/call externalKeyComboRequest`（または `presetManager.externalKeyComboRequest`）— エディターに combo を流し込める
- `screencapture -x` — フルスクリーンスクリーンショット
- 私 (Claude) は Read ツールで PNG を視覚確認できる
- `Sources/FloatingMacroApp/ControlAPI/ControlHandlers.swift` の test API — 特殊キーメニューを開く / 値を取得する系のフックが既にあるかを確認する必要あり

## 追加したい検証ケース

### A. ボタンエディター: 種類変更とインジケーター連動
1. text ボタンを選択 (`settings_select_button`)
2. スクリーンショット — 初期状態 (`actionType = text` のはず)
3. `externalKeyComboRequest { combo: "delete" }` を投げる
4. スクリーンショット — **右上カプセルが "key" になっているか**を私が PNG で目視確認
5. 保存 → 再度開いて `actionType` が `key` のままかを確認

これで前回のバグ（私が直したやつ）の回帰を自動検出できる。

### B. 特殊キーメニュー（ドロップダウン）の位置
1. ボタンエディターを開く
2. 種類セグメントを `key` に切り替え
3. 「特殊キー…」メニューをマウスクリック相当で開く（System Events osascript or AX）
4. スクリーンショット — **ドロップダウンが画面外に飛び出したり親要素から大きくずれていないか**
5. 私が PNG を Read してアサーション（"メニューがエディター行の真下に出ている" など）

### C. SF Symbol / App Icon ピッカー
- 同様に開いて配置・スクロール・選択結果まで PNG で確認

### D. 確認ダイアログ / トースト
- confirm 付きボタン押下時のダイアログ位置・テキスト切れがないか
- トーストの重なりや表示崩れがないか

## 必要な実装

1. **Sources 側**
   - `presetManager.externalKeyComboRequest` 経由のテストフック相当が他の操作（種類セグメント切替・特殊キーメニュー開閉・コミット）でも揃っているか棚卸しし、足りない分を追加
   - 追加分は `ControlHandlers.swift` の test API として、認証必須で公開
2. **scripts 側**
   - `scripts/settings_ui_e2e.sh`（新規） — Settings 開閉まで含むケースを `text_inject_e2e.sh` と同じ流儀で書く
   - 既存の `shoot` ヘルパー（screencapture + sentinel ファイル名）はそのまま流用
3. **検証ロジック**
   - 私が PNG を Read で見て判断するのが現状のベストパス
   - 機械可読な assert を増やしたい場合は AXUIElement で「メニューの frame が想定矩形に収まっているか」を Swift 側でチェックして JSON 返却する API を追加

## 依存・前提

- `~/Library/Application Support/FloatingMacro/presets/debug.json` の test ボタン群（btn-test-key-* など）が存在していること
- `fm-test-target` は今回のケースでは不要（テキスト入力先ではない）。Settings ウィンドウ自身が観測対象
- スクリーンショットを PNG で保存 → 私 (Claude) が `Read` で読む流れで視覚異常を検出する。これは「ログだけで動作確認しない」運用の自然な拡張

## 着手前にユーザーに確認したいこと

- Settings ウィンドウの自動操作で OS から追加の Accessibility プロンプトが出る可能性。ad-hoc 署名 macOS アプリのため `/Volumes/DISK/dev/knowledge/macos_accessibility_permission.md` の罠を踏まないように、initial run は人がそばにいる時に
- 特殊キーメニューの開閉トリガーを「マウスクリック相当」にするか「専用テスト API」にするか — 前者は production 経路を全部踏むが Amical 等で奪われやすい。後者は内部状態を直接いじれるが production と乖離する
