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
4. **Control API（HTTP）** の全エンドポイント — 実際の操作シナリオ通りの順番で確認

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
5. **Control API を有効にする**（セクション 3 を実施する場合のみ）:
   ```json
   // ~/Library/Application Support/FloatingMacro/config.json に追記
   { "controlAPI": { "enabled": true } }
   ```
   有効にしてからアプリを起動すると `ControlServer Started on 127.0.0.1:17430` がログに出る。

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
- [ ] 「表示/非表示」でパネルの可視状態が切り替わる
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

## 3. Control API — シナリオ型テスト

> **このセクションは一本の流れとして順番に実行する。**
> 各手順は直前の手順の結果を前提としており、スキップや順番の入れ替えをすると検証が成立しない。

Control API が有効なアプリを起動してから実施すること（事前準備 5 を参照）。

### 3-0. 環境変数

```bash
BASE="http://127.0.0.1:17430"
```

このセッション中、以下のすべての `curl` コマンドは `$BASE` を使う。
`-H 'Content-Type: application/json'` を省略した POST も一部あるが、`-d` を渡す場合は必ず付ける。

---

### 3-1. セッション開始シーケンス

Control API のテストを始める前に、必ずこの順で実施する。

```bash
# ① サーバー疎通確認
curl -s $BASE/ping
# → {"ok":true,"product":"FloatingMacro"}
```
- [ ] `ok: true` が返る（タイムアウトや接続拒否の場合は config と起動ログを確認）

```bash
# ② アプリ状態のスナップショットを取得
curl -s $BASE/state | jq
# → パネルの表示状態・アクティブプリセット名・ウィンドウ座標などが含まれる
```
- [ ] JSON が返る（パースエラーなし）

```bash
# ③ マニフェストで全ツールを確認
curl -s $BASE/manifest | jq '[.tools[].name]'
# → すべてのツール名の配列が表示される
```
- [ ] `arrange`・`settings_commit`・`settings_set_key_combo` 等、最新ツールが含まれる

```bash
# ④ テスト用に重ならない位置へ整列（Settings ウィンドウも同時に開く）
curl -s -X POST $BASE/arrange \
    -H 'Content-Type: application/json' \
    -d '{"open_settings": true}' | jq
# → {"panel":{"x":...,"y":...},"settings":{"x":...,"y":...}} 実際に配置された座標
```
- [ ] フローティングパネルと Settings ウィンドウが画面上で重なっていない
- [ ] Settings ウィンドウが開いている

---

### 3-2. テスト用プリセットの作成と構造構築

> **⚠️ このセクションの手順は 3-7 まで続く。`test-api` プリセットをここで作り、3-7 でまとめて削除する。**

```bash
# ⑤ 現在のプリセット一覧を確認（ベースライン）
curl -s $BASE/preset/list | jq
```

```bash
# ⑥ テスト用プリセットを作成
curl -s -X POST $BASE/preset/create \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api","displayName":"APIテスト"}' | jq
```
- [ ] エラーなく作成される

```bash
# ⑦ テスト用プリセットに切替（以降の操作の対象になる）
curl -s -X POST $BASE/preset/switch \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api"}' | jq
```
- [ ] パネルが空（ボタンゼロ）になる

```bash
# ⑧ グループを追加（メイン）
curl -s -X POST $BASE/group/add \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main","label":"メイングループ"}' | jq

# ⑨ グループを追加（サブ：button_move のターゲット用）
curl -s -X POST $BASE/group/add \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-sub","label":"サブグループ","collapsed":true}' | jq
```
- [ ] パネルに「メイングループ」と折りたたまれた「サブグループ」が表示される

```bash
# ⑩ ボタンをメイングループに追加
curl -s -X POST $BASE/button/add \
    -H 'Content-Type: application/json' \
    -d '{
      "groupId": "g-main",
      "button": {
        "id": "btn-test",
        "label": "テスト",
        "iconText": "🧪",
        "action": {"type":"text","content":"APIテスト成功"}
      }
    }' | jq
```
- [ ] パネルに「テスト」ボタンが現れる

```bash
# ⑪ プリセット全体の構造を確認
curl -s $BASE/preset/current | jq '.preset.groups[] | {id,label,buttons:[.buttons[].id]}'
# → g-main に btn-test、g-sub が空 の構造が返る
```

```bash
# ⑫ ボタンの動作確認（TextEdit にフォーカスしてから実施）
# パネルの「テスト」ボタンをクリック
```
- [ ] TextEdit に「APIテスト成功」が貼り付けられる

---

### 3-3. ボタン・グループの API 操作

> 前の手順（3-2）から続けて実施する。`test-api` プリセットがアクティブな状態。

```bash
# ⑬ ボタンのラベルを更新
curl -s -X POST $BASE/button/update \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test","label":"テスト済","iconText":"✅"}' | jq
```
- [ ] パネルのボタンが「✅ テスト済」に変わる

```bash
# ⑭ 追加ボタンをひとつ作って並び替えを検証できるようにする
curl -s -X POST $BASE/button/add \
    -H 'Content-Type: application/json' \
    -d '{
      "groupId": "g-main",
      "button": {
        "id": "btn-dummy",
        "label": "ダミー",
        "action": {"type":"text","content":"dummy"}
      }
    }' | jq

# ⑮ ボタンの順番を逆にする
curl -s -X POST $BASE/button/reorder \
    -H 'Content-Type: application/json' \
    -d '{"groupId":"g-main","ids":["btn-dummy","btn-test"]}' | jq
```
- [ ] パネルで「ダミー」が上、「テスト済」が下になる

```bash
# ⑯ ボタンをサブグループへ移動
curl -s -X POST $BASE/button/move \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-dummy","toGroupId":"g-sub","position":0}' | jq
```
- [ ] サブグループを展開すると「ダミー」が入っている

```bash
# ⑰ グループの表示名と折りたたみ状態を更新
curl -s -X POST $BASE/group/update \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-sub","label":"サブ（展開済）","collapsed":false}' | jq
```
- [ ] グループヘッダーが「サブ（展開済）」になり展開される

```bash
# ⑱ 空のグループは group_delete で削除できることを確認（g-main からボタンをすべて移動した後）
# まず g-main からも btn-test を g-sub へ移動して g-main を空にする
curl -s -X POST $BASE/button/move \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test","toGroupId":"g-sub"}' | jq

curl -s -X POST $BASE/group/delete \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main"}' | jq
```
- [ ] パネルから「メイングループ」が消える

```bash
# ⑲ g-main を作り直して btn-test を戻す（以降の Settings テスト用）
curl -s -X POST $BASE/group/add \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main","label":"メイングループ"}' | jq

curl -s -X POST $BASE/button/move \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test","toGroupId":"g-main","position":0}' | jq
```

```bash
# ⑳ preset_reload のスモークテスト（ディスクから再読み込みしても壊れないことを確認）
curl -s -X POST $BASE/preset/reload | jq
```
- [ ] エラーなく応答し、パネルの表示が維持される

```bash
# ㉑ preset_rename でディスプレイ名を変更
curl -s -X POST $BASE/preset/rename \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api","displayName":"APIテスト v2"}' | jq
```
- [ ] メニューバーのプリセット一覧に「APIテスト v2」が表示される

---

### 3-4. Settings UI 経由のボタン編集フロー

> Settings ウィンドウが開いている状態（3-1 の④ arrange で開いた）から続ける。
> このセクションは `select → 編集 → commit → clear` の一連の流れを検証する。

```bash
# ㉒ btn-test を Settings で選択（ButtonEditor が開く）
curl -s -X POST $BASE/settings/select-button \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test"}' | jq
```
- [ ] Settings ウィンドウの右ペインに ButtonEditor が展開される

```bash
# ㉓ アクションタイプを text に明示的に切替
curl -s -X POST $BASE/settings/set-action-type \
    -H 'Content-Type: application/json' \
    -d '{"type":"text"}' | jq

# ㉔ テキスト内容を書き換え
curl -s -X POST $BASE/settings/set-action-value \
    -H 'Content-Type: application/json' \
    -d '{"type":"text","value":"Settings API から書き込んだテキスト"}' | jq
```
- [ ] ButtonEditor のテキストフィールドに新しい内容が表示される

```bash
# ㉕ 背景色を設定（Save 前でもライブプレビューされることを確認）
curl -s -X POST $BASE/settings/set-background-color \
    -H 'Content-Type: application/json' \
    -d '{"color":"#1A73E8"}' | jq
```
- [ ] パネルの「テスト済」ボタン背景がリアルタイムで青 `#1A73E8` に変わる（Save 前）

```bash
# ㉖ 文字色を白に設定
curl -s -X POST $BASE/settings/set-text-color \
    -H 'Content-Type: application/json' \
    -d '{"color":"#FFFFFF"}' | jq
```
- [ ] パネルのボタン文字色が白になる（Save 前でもプレビュー反映）

```bash
# ㉗ 変更を保存（Save ボタンを押す相当）
curl -s -X POST $BASE/settings/commit | jq

# ㉘ 選択を解除（ButtonEditor が閉じる）
curl -s -X POST $BASE/settings/clear-selection | jq
```
- [ ] ButtonEditor が閉じて空の状態に戻る
- [ ] パネルのボタン色が保存後も維持されている

```bash
# ㉙ 保存内容を API で確認
curl -s $BASE/preset/current | jq '.preset.groups[0].buttons[0] | {label,backgroundColor,textColor,action}'
# → backgroundColor: "#1A73E8", textColor: "#FFFFFF", action.content: "Settings API から書き込んだテキスト"
```

---

### 3-5. Settings UI 経由のグループ編集フロー

> 3-4 から続けて実施。Settings ウィンドウが開いていること。

```bash
# ㉚ g-main を Settings で選択（GroupEditor が開く）
curl -s -X POST $BASE/settings/select-group \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main"}' | jq
```
- [ ] GroupEditor ペインが右側に展開される

```bash
# ㉛ グループ背景色を設定
curl -s -X POST $BASE/settings/set-background-color \
    -H 'Content-Type: application/json' \
    -d '{"color":"#34A853"}' | jq
```
- [ ] グループヘッダーの背景がリアルタイムで緑になる

```bash
# ㉜ 保存 → 解除
curl -s -X POST $BASE/settings/commit | jq
curl -s -X POST $BASE/settings/clear-selection | jq
```
- [ ] グループヘッダーの緑が保存後も維持されている

---

### 3-6. ピッカーシートの開閉フロー

> 3-5 から続けて実施。Settings が開いていること。

```bash
# ㉝ btn-test を選択してからアプリアイコンピッカーを開く
curl -s -X POST $BASE/settings/select-button \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test"}' | jq

curl -s -X POST $BASE/settings/open-app-icon-picker | jq
```
- [ ] アプリアイコンピッカーシートが Settings ウィンドウにオーバーレイで表示される

```bash
# ㉞ 選択せずに閉じる
curl -s -X POST $BASE/settings/dismiss-picker | jq
```
- [ ] シートが閉じ、ButtonEditor に戻る

```bash
# ㉟ SF Symbol ピッカーを開く（settings_open_sf_picker は Settings も開いていない場合は開く）
curl -s -X POST $BASE/settings/open-sf-picker | jq
```
- [ ] SF Symbol ピッカーシートが表示される

```bash
# ㊱ 閉じる
curl -s -X POST $BASE/settings/dismiss-picker | jq
curl -s -X POST $BASE/settings/clear-selection | jq
```

---

### 3-7. キーコンボ設定フロー

> 3-6 から続けて実施。

```bash
# ㊲ btn-test を再選択
curl -s -X POST $BASE/settings/select-button \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test"}' | jq

# ㊳ キーコンボを設定（アクションタイプが自動で key に切り替わる）
curl -s -X POST $BASE/settings/set-key-combo \
    -H 'Content-Type: application/json' \
    -d '{"combo":"cmd+shift+4"}' | jq
```
- [ ] ButtonEditor のアクションタイプタブが「キー」に切り替わる
- [ ] キーコンボフィールドに `⌘⇧4` 相当の表示が出る

```bash
# ㊴ 保存 → 解除
curl -s -X POST $BASE/settings/commit | jq
curl -s -X POST $BASE/settings/clear-selection | jq
```

```bash
# ㊵ API でも確認
curl -s $BASE/preset/current | jq '.preset.groups[0].buttons[0].action'
# → {"type":"key","combo":"cmd+shift+4"}
```

---

### 3-8. テスト用プリセットのクリーンアップ

> 3-7 まで完了したら、テスト用データを削除して環境を戻す。

```bash
# ㊶ default に戻す
curl -s -X POST $BASE/preset/switch \
    -H 'Content-Type: application/json' \
    -d '{"name":"default"}' | jq
```
- [ ] パネルが default プリセットの表示に戻る

```bash
# ㊷ test-api を削除
curl -s -X POST $BASE/preset/delete \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api"}' | jq

# ㊸ 削除されたことを確認
curl -s $BASE/preset/list | jq '[.[].name]'
# → test-api が含まれていないこと
```
- [ ] `test-api` がリストに存在しない

---

### 3-9. ウィンドウ操作シーケンス

> プリセット削除後、フローティングパネルへの操作を検証する。

```bash
# ㊹ 不透明度を下げる
curl -s -X POST $BASE/window/opacity \
    -H 'Content-Type: application/json' \
    -d '{"value":0.4}' | jq
```
- [ ] パネルが半透明（約 40%）になる

```bash
# ㊺ パネルを移動
curl -s -X POST $BASE/window/move \
    -H 'Content-Type: application/json' \
    -d '{"x":300,"y":300}' | jq

# ㊻ パネルをリサイズ
curl -s -X POST $BASE/window/resize \
    -H 'Content-Type: application/json' \
    -d '{"width":220,"height":320}' | jq
```
- [ ] パネルが指定位置・サイズに変わる

```bash
# ㊼ 非表示にする
curl -s -X POST $BASE/window/hide | jq
```
- [ ] パネルが画面から消える

```bash
# ㊽ toggle で表示に戻す
curl -s -X POST $BASE/window/toggle | jq
```
- [ ] パネルが再表示される

```bash
# ㊾ 不透明度を元に戻す
curl -s -X POST $BASE/window/opacity \
    -H 'Content-Type: application/json' \
    -d '{"value":1.0}' | jq
```

---

### 3-10. アクション直実行 + ログ確認シーケンス

> TextEdit を開き、カーソルを置いてから実施する。

```bash
# ㊿ テキスト貼付（クリップボード復元付き）
# 事前に何かをクリップボードにコピーしておく（例: "PREV"）
curl -s -X POST $BASE/action \
    -H 'Content-Type: application/json' \
    -d '{"type":"text","content":"APIから直接貼付","restoreClipboard":true}' | jq
```
- [ ] TextEdit に「APIから直接貼付」が挿入される
- [ ] Cmd+V を押すと元のクリップボード（"PREV"）が戻る

```bash
# 51. ログでエラーがないか確認
curl -s "$BASE/log/tail?since=30s&level=warn" | jq '.events | length'
# → 0（warn 以上のイベントがゼロ）
```

```bash
# 52. キーショートカットを送信（TextEdit で Undo）
curl -s -X POST $BASE/action \
    -H 'Content-Type: application/json' \
    -d '{"type":"key","combo":"cmd+z"}' | jq
```
- [ ] TextEdit で直前のテキスト挿入が Undo される

```bash
# 53. アプリアイコンを取得（Safari）
curl -s "$BASE/icon/for-app?bundleId=com.apple.Safari" | jq '{mimeType,iconSize:(.icon|length)}'
# → {mimeType:"image/png", iconSize: 大きな数値} が返る
```
- [ ] PNG の base64 データが返る（`iconSize` が 1000 以上であること）

---

### 3-11. Settings ウィンドウ操作

```bash
# 54. Settings が開いていれば一度閉じてから再テスト
curl -s -X POST $BASE/settings/close | jq

# 55. 改めて開く
curl -s -X POST $BASE/settings/open | jq
```
- [ ] Settings ウィンドウが開く

```bash
# 56. Settings ウィンドウを移動
curl -s -X POST $BASE/settings/move \
    -H 'Content-Type: application/json' \
    -d '{"x":150,"y":350}' | jq
```
- [ ] Settings ウィンドウが指定座標に移動する

```bash
# 57. 閉じる
curl -s -X POST $BASE/settings/close | jq
```
- [ ] Settings ウィンドウが閉じる

```bash
# 58. セクション全体のエラーがないか最終ログ確認
curl -s "$BASE/log/tail?since=10m&level=error" | jq '.events'
# → [] （エラーイベントがゼロ）
```

---

## 4. セキュリティ確認（重要）

- [ ] `fmcli action text "$(cat /etc/hostname)"` のようにクリップボード経由でテキスト注入 → 完了後に `pbpaste` で元の内容が戻っていることを確認
- [ ] シークレット（パスワード、APIキー）をクリップボードに入れた状態で `fmcli action text "dummy"` を実行 → シークレットが復元されることを視覚確認

---

## 5. 回帰リスクの高い部分（リリース前に毎回確認）

- [ ] IME が ON の状態で `fmcli action text "あいう"` が正しく貼り付けられる（キーシンセサイザ経由ではなくクリップボード経由であるため IME の影響を受けない想定）
- [ ] 複数モニタ環境でパネルが片方のモニタで操作可能
- [ ] スペース（仮想デスクトップ）を跨いでもパネルが追従（`.canJoinAllSpaces`）
- [ ] Full Screen アプリを使用中もパネルが表示される（`.fullScreenAuxiliary`）
- [ ] Control API 有効状態でアプリを再起動しても `controlAPI.enabled` が保持され `GET /ping` に応答する
- [ ] 色変更（`set_background_color` / `set_text_color`）を `commit` してアプリを再起動後、パネルの色が維持されている

---

## 6. よくある問題と切り分け

| 症状 | 原因候補 | 確認手順 |
|---|---|---|
| キーが反応しない | Accessibility 未許可 | `fmcli permissions check` で確認 |
| `action terminal` が開かない | Automation 未許可 / Terminal/iTerm 未インストール | システム設定 → オートメーション / `ls /Applications/` |
| テキストが文字化け | `type` 経由になっていないか（cmdline の quoting ミス） | JSON 定義を直接見直す |
| クリップボードが戻らない | `restoreClipboard: false` 指定 or 直前に `TextActionExecutor` がクラッシュ | ログを確認 |
| パネルが消えた | メニューバー → 「表示/非表示」で復帰 | — |
| `GET /ping` がタイムアウト | `controlAPI.enabled` が false またはポート衝突 | `config.json` 確認 / 起動ログで `ControlServer Started` を探す |
| `settings_commit` がエラー | ButtonEditor / GroupEditor が開いていない | `settings_select_button` か `settings_select_group` を先に呼ぶ |
| `group_add` が失敗 | Settings 側に未保存の編集がある | `settings_commit` または `settings_clear_selection` してからリトライ |
| `button_update` が失敗 | `id` が存在しない | `preset_current` で正しい id を確認 |
| `preset_switch` 後に画面が変わらない | パネル再描画のタイミング | `preset_reload` を呼ぶと確実 |

---

## 7. 完了条件

すべての ✅ 可能項目が緑のときに、「手動テスト合格」とする。
問題があった場合は、**自動テストに落とし込める表現に言い換えて追加**することで、次回から手動項目を減らしていく方針。
