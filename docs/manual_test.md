# FloatingMacro — 手動テスト チェックリスト

このチェックリストは **自動テストで網羅できない部分** を人の目と手で確認するためのものです。
自動テスト（`swift test`・`scripts/fmcli_smoke.sh`）が全て緑になってから、この手順を実施してください。

## 自動テストでカバー済み（このドキュメントで再確認不要）

- `FloatingMacroCore` のロジック全般（Action JSON、KeyCombo パーサ、各 Executor のフロー、MacroRunner）
- Clipboard の save/restore 正確性
- Config の読み書きと既定値生成
- CLI (`fmcli`) の permission-free サブコマンド（help / config / preset list / launch shell: / permissions check / エラー exit コード）

## このドキュメントでカバーする部分

1. 実際の **キーイベント / テキスト注入 / ターミナル起動** の挙動（macOS Accessibility & Automation 権限が必要）
2. **NSPanel / SwiftUI の UI** の見た目と操作性（自動化しづらい）
3. **クリップボード復元** の視覚確認

---

## 事前準備

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` が成功すること
2. 以下のどちらかの方法でビルド成果物を用意:
   - **CLI のみ使う場合**: `swift build --product fmcli`
   - **GUI を含めて確認する場合**: `swift build --product FloatingMacro` でその場ビルド、または `swift run FloatingMacro`
3. Accessibility 権限（`fmcli` または `FloatingMacro` バイナリに対して）
   - システム設定 → プライバシーとセキュリティ → アクセシビリティ で該当バイナリを ON
4. 設定ディレクトリを汚したくない場合は、ターミナルで次のように環境変数を設定してから起動:
   ```
   export FLOATINGMACRO_CONFIG_DIR=/tmp/fmtest-$$
   ```
   （`$$` はシェルが自動的に PID に置換するので、実行するだけでユニークな一時パスになる）

---

## 1. CLI: `fmcli action` シリーズ（Accessibility 要）

テキストエディタ（例: TextEdit）を開き、空の新規ドキュメントにカーソルを置いた状態で以下を実施。

### 1-1. `fmcli action key`

| 手順 | 期待 |
|---|---|
| `fmcli action key "cmd+shift+4"` を実行 | スクリーンショット撮影のレチクルが出る |
| `fmcli action key "f5"` を実行 | F5 が押されたのと同じ挙動になる |
| `fmcli action key "cmd+space"` を実行 | Spotlight が開く（環境依存） |

### 1-2. `fmcli action text`

| 手順 | 期待 |
|---|---|
| TextEdit に何か適当な文字列をコピー（例: "PRE-TEST"）しておく | クリップボードに "PRE-TEST" が入る |
| `fmcli action text "こんにちは 🌏"` を実行 | カーソル位置に「こんにちは 🌏」が貼り付けられる |
| Cmd+V をもう一度押す | **"PRE-TEST"** が出る（クリップボード復元確認） |
| `fmcli action text "line1\nline2"` を実行（※シェル上では `printf` 等で改行を渡す） | 2行に分かれて貼り付けられる |

### 1-3. `fmcli action terminal`

| 手順 | 期待 |
|---|---|
| `fmcli action terminal --app Terminal --command "echo hello"` | Terminal.app が開き "echo hello" が実行されて "hello" が表示される |
| `fmcli action terminal --app iTerm --command "ls ~"` | iTerm2 がインストールされていれば、新規ウィンドウで `ls ~` が実行される |
| `fmcli action terminal --app Terminal --command "date" --no-execute` | Terminal に "date" が入力されるが **Enter は押されない**（カーソル末尾で停止） |

### 1-4. `fmcli preset run`

`fmcli config init` で既定プリセットを作成後:

| 手順 | 期待 |
|---|---|
| TextEdit にフォーカス | — |
| `fmcli preset run default btn-ultrathink` | "ultrathink で次のタスクに取り組んでください。" が貼り付けられる |
| `fmcli preset run default btn-stop-loop` | 「止まって」系の定型文が貼り付けられる |

---

## 2. GUI: フローティングパネル

`swift run FloatingMacro` でアプリを起動。

### 2-1. 初回起動 / 権限

- [ ] 起動後、Dock にアイコンが出ない（`LSUIElement = YES` 相当）
- [ ] メニューバーに `command.square` SF Symbol のアイコンが表示される
- [ ] Accessibility 権限が未許可の場合、モーダルが出る
- [ ] モーダルの「システム設定を開く」でプライバシーパネルが開く

### 2-2. ウィンドウの基本挙動

- [ ] フローティングパネルが画面に現れる（既定位置 x=100, y=100）
- [ ] 他のアプリをクリックしても **パネルは前面に残る**（`.floating` レベル）
- [ ] パネルをクリックしても **現在アクティブなアプリのフォーカスが奪われない**（`.nonactivatingPanel`）
  - 確認方法: TextEdit をアクティブにしてカーソルを置く → パネルをクリック → TextEdit に文字入力できる

### 2-3. ドラッグ

- [ ] パネルの空白（ボタン以外）を掴んで画面内で自由に動かせる
- [ ] 画面端を超えて移動できない（macOS 標準挙動）
- [ ] アプリ再起動後、最後の位置が保持される（`setFrameAutosaveName` による）

### 2-4. ボタン操作

- [ ] 既定プリセットの「ultrathink」ボタンが表示される
- [ ] ホバーすると背景色がうっすら変わる
- [ ] TextEdit にフォーカスを置いて「ultrathink」を押すと定型文が貼り付けられる
- [ ] グループヘッダ（「AI」）をクリックすると折りたたみ / 展開される

### 2-5. メニューバー

- [ ] アイコンをクリックすると「表示/非表示」「プリセット切替」「設定フォルダを開く」「再読み込み」「終了」が表示
- [ ] 「表示/非表示」で パネルの可視状態が切り替わる
- [ ] 「設定フォルダを開く」で `~/Library/Application Support/FloatingMacro` が Finder で開く
- [ ] 「終了」でアプリが正しく終了する

### 2-6. プリセット切替

1. `~/Library/Application Support/FloatingMacro/presets/` に次の内容で `writing.json` を作成:
   ```json
   {
     "version": 1,
     "name": "writing",
     "displayName": "執筆",
     "groups": [
       { "id": "g1", "label": "素材", "buttons": [
         { "id": "b1", "label": "挨拶", "iconText": "✍️",
           "action": { "type": "text", "content": "こんにちは、今日もよろしくお願いします。" }
         }
       ]}
     ]
   }
   ```
2. メニューバー → 「再読み込み」を押す
3. メニューバー → 「プリセット」→「writing」を選択
- [ ] パネルの表示が「執筆」に切り替わり、「挨拶」ボタンだけになる
- [ ] 「default」に戻すと元のボタン群が復帰する

### 2-7. エラーバナー

1. プリセットに存在しないキーコンボ（例: `{"type":"key","combo":"cmd+xyz"}`）を書いたボタンを追加
2. 再読み込み → そのボタンをクリック
- [ ] 赤いエラーバナーが出る
- [ ] 3 秒後にバナーが自動的に消える

---

## 3. セキュリティ確認（重要）

- [ ] `fmcli action text "$(cat /etc/hostname)"` のようにクリップボード経由でテキスト注入 → 完了後に `pbpaste` で元の内容が戻っていることを確認
- [ ] シークレット（パスワード、APIキー）をクリップボードに入れた状態で `fmcli action text "dummy"` を実行 → シークレットが復元されることを視覚確認

---

## 4. 回帰リスクの高い部分（リリース前に毎回確認）

- [ ] IME が ON の状態で `fmcli action text "あいう"` が正しく貼り付けられる（キーシンセサイザ経由ではなくクリップボード経由であるため IME の影響を受けない想定）
- [ ] 複数モニタ環境でパネルが片方のモニタで操作可能
- [ ] スペース（仮想デスクトップ）を跨いでもパネルが追従（`.canJoinAllSpaces`）
- [ ] Full Screen アプリを使用中もパネルが表示される（`.fullScreenAuxiliary`）

---

## 5. よくある問題と切り分け

| 症状 | 原因候補 | 確認手順 |
|---|---|---|
| キーが反応しない | Accessibility 未許可 | `fmcli permissions check` で確認 |
| `action terminal` が開かない | Automation 未許可 / Terminal/iTerm 未インストール | システム設定 → オートメーション / `ls /Applications/` |
| テキストが文字化け | `type` 経由になっていないか（cmdline の quoting ミス） | JSON 定義を直接見直す |
| クリップボードが戻らない | `restoreClipboard: false` 指定 or 直前に `TextActionExecutor` がクラッシュ | ログを確認 |
| パネルが消えた | メニューバー → 「表示/非表示」で復帰 | — |

---

## 6. 完了条件

すべての ✅ 可能項目が緑のときに、「手動テスト合格」とする。
問題があった場合は、**自動テストに落とし込める表現に言い換えて追加**することで、次回から手動項目を減らしていく方針。
