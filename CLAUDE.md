# FloatingMacro を AI から操作する

このファイルは **AI（Claude Code / Cursor / Gemini CLI 等）に読ませる前提**で書かれています。
あなたが AI なら、これから先を**自分への指示として**受け取ってください。

---

## あなたが今接続しようとしているもの

ユーザーの Mac で **FloatingMacro** という macOS アプリが常駐しています。
画面上にフローティングパネルを表示し、ボタンをクリックすると：

- AI へのプロンプト投入（テキストをペースト）
- キーボードショートカット送出
- アプリ・URL・ファイルの起動
- ターミナルでのコマンド実行
- 上記を組み合わせたマクロ実行

を行えます。あなたは **このアプリの設定（ボタン・グループ・プリセット）を
HTTP API 経由で読み書きできます**。

接続先：

```
http://127.0.0.1:17430
```

このポートは loopback (127.0.0.1) にしかバインドされていないため、
ネットワーク越しからは到達できません。

---

## 最初にやること（この順番で）

### 1. 認証トークンを取得する

操作系エンドポイントは Bearer 認証必須です。トークンは macOS Keychain に保存されているので、シェルで取得してください：

```bash
security find-generic-password -s FloatingMacro -a ControlAPIToken -w
```

以降、すべてのリクエストに `Authorization: Bearer <取得したトークン>` ヘッダを付けます。

### 2. `/manifest` でアプリの自己紹介を読む

`/manifest`（または別名 `/help`）は**認証不要**です。アプリの正式な systemPrompt、quickStart、全ツール定義（`tools` 配列）が一発で取れます。

```bash
curl -s http://127.0.0.1:17430/manifest | jq
```

ここに書かれている systemPrompt とツールリストが**この API の真の説明書**です。
このファイルとマニフェストの記述が食い違ったら、マニフェスト側を優先してください。

### 3. 現状を把握する

ユーザーから依頼を受けたら、いきなり書き換えに行かず必ず最初に状態を確認します。

```bash
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)

# パネル可視性・アクティブプリセット
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/state | jq

# 現在のプリセットの全グループ・全ボタン
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/preset/current | jq
```

---

## やってはいけないこと

### ❌ 個別 HTTP エンドポイントを直叩きしない

`/group/add`、`/button/add`、`/preset/switch` などは**実装の下層**です。AI からは必ず ACP のディスパッチ層 `/tools/call` 経由で呼んでください。

```bash
# ❌ 間違い（直叩き）
curl -X POST http://127.0.0.1:17430/group/add -d '{"id":"g1","label":"Test"}'

# ✅ 正しい（/tools/call 経由）
curl -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"group_add","arguments":{"id":"g1","label":"Test"}}'
```

直叩きでも今は動きますが、将来エンドポイント仕様が変わる可能性があり、
ACP 経由なら manifest の tool 定義に追従できます。

### ❌ 設定ファイルを直接編集しない

`~/Library/Application Support/FloatingMacro/presets/*.json` を直接書き換えても、アプリが起動中なら**メモリ上の状態でディスクを上書き**して変更が消えます。
必ず API 経由で操作してください。

### ❌ 推測でツール名を呼ばない

ツール一覧は manifest の `tools` 配列、または `GET /tools` で取得できます。
存在しないツール名を投機的に呼ばず、まずカタログを確認してください。

---

## 典型的な依頼への対応

### 「○○というボタンを追加して」

1. `preset_current` で現状を読む（既存のグループ id を把握）
2. 適切なグループを選ぶ。なければ `group_add` で作る
3. `button_add` でボタンを追加
4. 必要に応じて `log_tail` で実行ログを確認

### 「ボタンを並べ替えて／別グループに移して」

`button_reorder`（同一グループ内）、`button_move`（グループ間）。

### 「キーボードショートカットを送るボタンを作って」

action は `{"type":"key", "combo":"cmd+shift+v"}` の形。
combo は `cmd+shift+v`、`f5`、`cmd+space` など。

### 「テキストを貼り付けるボタンを作って」

action は `{"type":"text", "content":"...", "pasteDelayMs":120, "restoreClipboard":true}`。
クリップボード経由で貼り付けるため、対象アプリがアクティブな状態で押されることを前提に動作します。

### 「ターミナルでコマンドを実行するボタンを作って」

action は `{"type":"terminal", "app":"Terminal", "command":"...", "execute":true, "newWindow":false}`。

### 「Slack を起動するボタンを作って」

action は `{"type":"launch", "target":"com.tinyspeck.slackmacgap"}`（bundle id）または絶対パス。

---

## 開発者向け補足（このリポジトリで作業する Claude 用）

このリポジトリ自体を Claude Code でいじる場合：

- ソースは Swift（macOS 専用）。`swift build` でビルド
- 実機の動作確認は `scripts/build-app.sh` → `scripts/rebuild-and-relaunch.sh`
- Control API の手動疎通は `bash scripts/control_api_smoke.sh`
- ツール定義の真実の源は `Sources/FloatingMacroCore/ControlAPI/ToolCatalog.swift`
- システムプロンプトの真実の源は `Sources/FloatingMacroCore/Resources/agent_prompts.json`
  （`SystemPrompt.swift` のフォールバックは JSON が読めない時の保険）
- 認証ミドルウェアは `Sources/FloatingMacroApp/ControlAPI/ControlHandlers.swift` 末尾の `wrapWithAuth`

ユーザー（リポジトリ所有者）の方針：

- AI が自律的にテストを完結できる設計を最優先（人間に「ボタンを押してください」と頼まない）
- MCP は stdio + 厳選ツールのみ。HTTP `/mcp` はデモ扱い。本命は ACP（`/tools/call`）
- OSS としての配布が目的（収益目的ゼロ）。配布物のサイズ・依存数は気にしない
