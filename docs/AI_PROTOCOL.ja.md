# FloatingMacro — AI エージェント接続マニュアル

**対象読者**: Claude / Gemini / GPT 等の AI エージェント、またはそれらをホストする開発者。

このドキュメントは **AI がこのアプリを操作するためのプロトコル仕様** である。人間向け仕様書は `SPEC.md`、手動テスト手順は `docs/manual_test.md` を参照。

---

## 0. TL;DR — AI はまず何をすればいい?

```bash
# 1. アプリを起動 (まだなら)
#    controlAPI.enabled=true の config を用意してから FloatingMacro を起動する。

# 2. サーバーが生きているか確認
curl http://127.0.0.1:17430/ping

# 3. 最初に必ず /manifest を読む (自己紹介 + 全ツール一覧が一度に返る)
curl -s http://127.0.0.1:17430/manifest | jq

# 4. 現状を把握
curl -s http://127.0.0.1:17430/state | jq

# 5. ツールを呼ぶ (統一エンドポイント経由)
curl -X POST http://127.0.0.1:17430/tools/call \
    -H 'Content-Type: application/json' \
    -d '{"name":"window_opacity","arguments":{"value":0.7}}'

# 6. 結果を確認
curl -s 'http://127.0.0.1:17430/log/tail?since=1m&level=info' | jq
```

---

## 1. このアプリについて知っておくべきこと

**FloatingMacro** は macOS 用のフローティングマクロランチャー。**AI エージェントを第一級のユーザーとして想定した設計** になっており、GUI を人が操作する代わりにこの API からエンドツーエンドで動かされることを期待しています。

**AI の期待される行動**:
- コマンド実行や GUI クリックをユーザーに依頼するより、まず HTTP API を優先する
- 操作 → ログ確認 → 判断、のループを自律的に回す
- 不明な点は `help` ツールで manifest を再読み込みする

---

## 2. 接続方法

### 2.1 HTTP (推奨、ACP スタイル)

```
Base URL: http://127.0.0.1:17430
```

- TCP ソケット、loopback のみにバインド (外部からは不可)
- 認証なし
- HTTP/1.1、`Content-Type: application/json` 前提
- Keep-Alive なし (1 接続 1 リクエスト)
- ポートは衝突時 +1 ずつ最大 10 回 fallback → 実ポートは `GET /state` の `.port` では返さず、起動ログ (`ControlServer Started on 127.0.0.1:NNNNN`) に記録される

### 2.2 MCP (Anthropic 標準)

```
POST http://127.0.0.1:17430/mcp
Content-Type: application/json

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
```

Claude Desktop / Claude Code の MCP 設定に `http://127.0.0.1:17430/mcp` を指定するだけで、全ツールが tool use として使えるようになる。

### 2.3 OpenAI function calling / Anthropic tool use

ツール定義を LLM に渡したい場合、次の URL を GET して LLM の `tools` パラメータにそのまま貼り付ける:

```
GET /tools?format=openai     # OpenAI Chat Completions "tools"
GET /tools?format=anthropic  # Anthropic Messages "tools"
GET /tools?format=mcp        # MCP (デフォルト)
```

---

## 3. 最初に絶対にやること — `GET /manifest`

```bash
curl -s http://127.0.0.1:17430/manifest
```

返り値には以下がすべて含まれる (1 回のリクエストで bootstrap 完了):

```json
{
  "product": "FloatingMacro",
  "version": "0.8",
  "systemPrompt": "...AI 向けの行動指針...",
  "quickStart": ["GET /manifest", "GET /state", ...],
  "endpoints": [{ "method": "GET", "path": "/manifest", "desc": "..." }, ...],
  "dialects": {
    "mcp":       "/tools?format=mcp",
    "openai":    "/tools?format=openai",
    "anthropic": "/tools?format=anthropic"
  },
  "helpTool": {
    "call": { "name": "help", "arguments": {} },
    "description": "Call any time to re-read the manifest."
  },
  "tools": [
    { "name": "window_move", "description": "...", "inputSchema": {...} },
    ...
  ]
}
```

**迷ったら `help` ツールを呼ぶ** (= `GET /manifest` と同じ):
```json
POST /tools/call
{"name": "help", "arguments": {}}
```

---

## 4. ツール呼び出しの 3 つの方法

同じ機能に 3 つの入り口がある。用途に応じて選ぶ。

### 4.1 REST 直叩き (最も軽い)

```bash
# 個別エンドポイントに POST/GET する
curl -X POST http://127.0.0.1:17430/window/move \
    -H 'Content-Type: application/json' \
    -d '{"x": 100, "y": 200}'
```

### 4.2 統一ディスパッチ `/tools/call` (推奨、宣言的)

```bash
curl -X POST http://127.0.0.1:17430/tools/call \
    -H 'Content-Type: application/json' \
    -d '{"name":"window_move","arguments":{"x":100,"y":200}}'
```

レスポンスは封筒形式:
```json
{
  "name":   "window_move",
  "status": 200,
  "result": { "x": 100, "y": 200 }
}
```

### 4.3 MCP JSON-RPC 2.0 `/mcp` (Claude ネイティブ)

```bash
curl -X POST http://127.0.0.1:17430/mcp \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"window_move","arguments":{"x":100,"y":200}}}'
```

レスポンス (MCP `tools/call` 仕様):
```json
{
  "jsonrpc": "2.0",
  "id":      1,
  "result": {
    "content": [{ "type": "text", "text": "{\"x\":100,\"y\":200}" }],
    "isError": false
  }
}
```

---

## 5. ツール・カタログ (要約)

**全定義は `GET /tools` で取得する**。ここは代表的なもののみ一覧。

### ディスカバリ
- `help` / `manifest` — マニフェスト再取得

### ヘルスとステート
- `ping` — 生存確認
- `get_state` — パネル可視性 / アクティブプリセット / ウィンドウ座標

### パネル (Phase 3 / v0.12 — 推奨)
- `panel_list` — 全パネルを `{id, presetName, displayName, visible, window, dockedEdge}` の配列で返す
- `panel_create` `{presetName: String, x?, y?, width?, height?, opacity?}` — 新規パネルを生成。返り値の `id` を後続呼び出しで使う
- `panel_close` `{id}` — パネル削除。最後の 1 件は拒否
- `panel_show` `{id}` — orderFront (ドック / ミニアイコンからの展開にも対応)
- `panel_hide` `{id}` — orderOut
- `panel_dock` `{id, edge?}` — パネルを画面端にドック (left/right/top/bottom)。`edge` 省略時はパネル位置から最寄り辺を自動判定
- `panel_undock` `{id}` — ドック中のパネルを通常のフローティング状態に展開

### パネル — id 指定で個別制御 (Phase 3.6)
ドラッグ操作が困難なユーザーが、自然言語の指示（「右上のパネルを左下に移動」「Claude Code のパネルを右半分に広げて」など）でレイアウトを完結できるようにするための per-id ツール群。設定 UI と同じ純粋関数を呼ぶので変更は `config.json` に永続化され、再起動しても保持される。
- `panel_move` `{id, x, y}` — 絶対座標で移動（AppKit: 原点は画面左下）
- `panel_resize` `{id, width, height}` — width ≥ 120, height ≥ 80 にクランプ
- `panel_opacity` `{id, opacity}` — `[0.25, 1.0]` にクランプ
- `panel_set_preset` `{id, presetName}` — そのパネルが表示するプリセットを切替。`presetName` は `preset_list` の内部 id

### ウィンドウ (deprecated — プライマリパネルにのみ作用)
v0.12 以降、複数パネル対応に移行したため `window_*` はプライマリパネル (panels[0]) への後方互換 API。新規開発は `panel_*` を使うこと。
- `window_show` / `window_hide` / `window_toggle`
- `window_opacity` `{value: 0.25..1.0}`
- `window_move` `{x, y}`
- `window_resize` `{width, height}` (width ≥ 120, height ≥ 80)

### プリセット
- `preset_list` / `preset_current`
- `preset_get` `{name}` — アクティブでない任意のプリセットを read-only で取得（`preset_current` の任意指定版）
- `preset_switch` `{name}`
- `preset_reload`
- `preset_create` `{name?, displayName?, memo?}` — `memo` でプリセット作成時に使う前提条件（前面アプリ・OS 設定・副作用等）を残せる
- `preset_rename` `{name, displayName?, memo?}` — `displayName` と `memo` の片方または両方を更新する preset_update 相当（互換のため tool 名は維持）。`memo: ""` でメモのクリア
- `preset_delete` `{name}`
- `preset_reorder` `{ids: [String]}` — ピッカーに表示する順序を上書きする。ディスクに無い名前は無視、欠けている名前はアルファベット順で末尾に追加される。

### グループ
- `group_add` `{id, label, collapsed?, displayType?}`
- `group_update` `{id, label?, collapsed?, displayType?}`
- `group_delete` `{id}`

`displayType` (v0.11 追加) はグループ内ボタンのレンダリングスタイル: `icon` (既定、コンパクト) / `wide` (全幅セル) / `card` (サムネイル + タイトルのギャラリー)。card のときは各ボタンの `thumbnail` フィールドが大きく表示される。

### ボタン
- `button_add` `{groupId, button: ButtonDefinition}`
- `button_update` `{id, label?, icon?, iconText?, thumbnail?, backgroundColor?, width?, height?, action?}`
- `button_delete` `{id}`
- `button_reorder` `{groupId, ids: [String]}`
- `button_move` `{id, toGroupId, position?}`

`button_update` は `thumbnail: null` で消去・`thumbnail: "..."` で設定。card タイプのグループに置いたときだけ意味を持つ (v0.11)。

### アクション実行
- `run_action` — Action JSON を送って即実行 (返却は 202 Accepted、結果はログで確認)

### 観察
- `log_tail` `{level?, since?, limit?}` — JSON 1 行 1 イベント
- `icon_for_app` `{bundleId? | path?}` — base64 PNG

### セッティングウィンドウ（基本操作）
- `settings_open` — Settings ウィンドウを開く
- `settings_close` — Settings ウィンドウを閉じる
- `settings_open_sf_picker` — Settings を開き SF Symbol ピッカーシートを表示
- `settings_move` `{x, y}` — Settings ウィンドウを指定スクリーン座標へ移動 (AppKit 座標系: 左下原点)
- `arrange` `{open_settings?}` — フローティングパネルと Settings ウィンドウを重ならないようにタイル配置。`open_settings:true` で Settings も同時に開ける

### セッティングウィンドウ（テスト自動化・AI 操作）

これらのツールは AI がスクリーンショットを撮らずに Settings UI を直接操作するためのものです。

- `settings_select_button` `{id}` — id でボタンを選択し ButtonEditor を開く (Settings が閉じていれば開く)
- `settings_select_group` `{id}` — id でグループを選択し GroupEditor を開く
- `settings_clear_selection` — 選択を解除して ButtonEditor / GroupEditor を閉じる
- `settings_commit` — 開いている ButtonEditor / GroupEditor の Save ボタンを押して変更を確定
- `settings_open_app_icon_picker` — アプリアイコンピッカーシートを開く (Settings が閉じていれば開く)
- `settings_dismiss_picker` — 開いているピッカーシート（アイコンピッカー / SF Symbol ピッカー）を閉じる
- `settings_set_background_color` `{color?, enabled?}` — 背景色を設定。`{enabled:false}` で無効化
- `settings_set_text_color` `{color?, enabled?}` — 文字色を設定。`{enabled:false}` で無効化
- `settings_set_action_type` `{type}` — アクションタイプタブを切り替え (`text` | `key` | `launch` | `terminal`)
- `settings_set_key_combo` `{combo?, cmd?, shift?, option?, ctrl?, key?}` — キーコンボを設定。`combo:"cmd+shift+v"` 形式か修飾キー個別フラグで指定。アクションタイプタブを自動で `key` に切り替える。特殊キー (`delete`, `forwarddelete`, `left/right/up/down`, `home/end`, `pageup/pagedown`, `return`, `tab`, `space`, `escape`, `f1`〜`f20`) も使用可能 (v0.9.2)
- `settings_set_action_value` `{type, value}` — アクション値フィールドを設定 (テキスト内容 / launch ターゲット / terminal コマンド)。アクションタイプタブも合わせて切り替える
- `list_key_codes` `{}` (v0.9.2) — combo 文字列で使えるキー名の正規カタログを返す。`modifiers` / `modifierAliases` / `specialKeys` (name + label) / `functionKeys` / `keyAliases` / `examples` を含む。「特殊キー名を覚えていない」「ユーザーにピッカーを提示したい」場面で参照する想定

---

## 6. Action JSON の形状

`run_action` ツール (および `button_add` / `button_update` の `action` フィールド) で使う:

```json
// キーコンボ
{ "type": "key", "combo": "cmd+shift+v" }

// テキスト貼り付け (クリップボード経由)
{
  "type": "text",
  "content": "ultrathink で考えて",
  "pasteDelayMs": 120,
  "restoreClipboard": true
}

// テキスト追記モード (v0.10 追加 — プロンプトビルダー)
// appendMode: true のとき、現在のクリップボード末尾に content を連結し、
// ペーストはしない (復元もしない)。Midjourney のような「画風 + ポーズ +
// 服装」を複数ボタンで積み上げて最後に自分で Cmd+V する用途。
// セパレータは入れないので、必要なら content に ", " 等を含めて制御する。
{
  "type": "text",
  "content": "anime style, ",
  "appendMode": true
}

// アプリ / URL / shell 起動
{ "type": "launch", "target": "/Applications/Slack.app" }
{ "type": "launch", "target": "com.tinyspeck.slackmacgap" }
{ "type": "launch", "target": "https://claude.ai/code" }
{ "type": "launch", "target": "shell:open ~/Downloads" }

// ターミナル + コマンド
{
  "type": "terminal",
  "app": "iTerm",
  "command": "cd ~/dev && claude",
  "newWindow": true,
  "execute": true
}

// 待機 (マクロ内でのみ意味を持つ)
{ "type": "delay", "ms": 500 }

// マクロ (ネスト禁止)
{
  "type": "macro",
  "actions": [
    { "type": "terminal", "command": "cd /proj && claude", "newWindow": true },
    { "type": "delay", "ms": 300 },
    { "type": "terminal", "command": "cd /other && claude", "newWindow": true }
  ],
  "stopOnError": true
}
```

---

## 7. ログの読み方 — AI 最重要

アプリの内部状態とすべての失敗は構造化ログに出る。**AI はアクション実行後に必ずログを確認すべき**。

```bash
# 最近 5 分のエラーだけ
curl -s 'http://127.0.0.1:17430/log/tail?level=warn&since=5m' | jq

# 最新 20 件を全レベル
curl -s 'http://127.0.0.1:17430/log/tail?limit=20' | jq
```

イベントの形:
```json
{
  "timestamp": "2026-04-16T00:30:00.123Z",
  "level":     "warn",
  "category":  "KeyAction",
  "message":   "Key dispatch failed",
  "metadata": {
    "keyCode": "9",
    "error":   "accessibilityDenied"
  }
}
```

### カテゴリ一覧
- `MacroRunner` — マクロ全体の進行
- `KeyAction` / `TextAction` / `LaunchAction` / `TerminalAction` — 各 Executor
- `ConfigLoader` — 設定読み書き
- `ControlServer` — HTTP サーバー
- `ControlAPI` — 個別エンドポイントからの投入

---

## 8. エラーハンドリング

### 8.1 REST / /tools/call のエラー

HTTP ステータスコード + JSON ボディ:

```json
{ "error": "unknown tool", "name": "no_such_tool" }  // 404
{ "error": "body must contain {id: String}" }         // 400
```

### 8.2 MCP のエラー

JSON-RPC 2.0 エラーコード:

| コード | 意味 | このサーバーでの発生条件 |
|---|---|---|
| -32700 | Parse error | JSON が壊れている |
| -32600 | Invalid Request | `jsonrpc:2.0` or `method` がない |
| -32601 | Method not found | 未知の method / 未知の tool |
| -32602 | Invalid params | `name` がない等 |
| -32603 | Internal error | サーバー内部エラー |
| -32000 | Tool failed | 配下の REST ハンドラが非 2xx を返した (data に詳細) |

### 8.3 典型的な失敗と対処

| 症状 | 原因 | 対処 |
|---|---|---|
| `GET /ping` がタイムアウト | controlAPI が有効でない or ポート衝突 | `config.json` の `controlAPI.enabled` 確認、`/log` で起動時のバインド結果を確認 |
| `run_action { key }` が無反応 | Accessibility 権限未許可 | `/log/tail?level=error` で `accessibilityDenied` 確認。**AI では権限を付与できない** ため、ユーザーに依頼 |
| `button_update` が失敗 | `id` が存在しない | `preset_current` で現在のプリセット全体を取得して正しい id を確認 |
| `preset_switch` 後に画面が変わらない | パネル再描画のタイミング | `preset_reload` を呼ぶと確実 |

---

## 9. 典型的なワークフロー

### 9.1 Slack 起動ボタンを追加する

```bash
# 1. 現在のプリセットの構造を把握
curl -s http://127.0.0.1:17430/preset/current | jq

# 2. グループ id を確認して、ボタンを追加
curl -X POST http://127.0.0.1:17430/tools/call \
    -H 'Content-Type: application/json' \
    -d '{
      "name": "button_add",
      "arguments": {
        "groupId": "group-1",
        "button": {
          "id": "btn-slack",
          "label": "Slack",
          "icon": "com.tinyspeck.slackmacgap",
          "backgroundColor": "#4A154B",
          "width": 140,
          "height": 36,
          "action": {
            "type": "launch",
            "target": "com.tinyspeck.slackmacgap"
          }
        }
      }
    }'

# 3. 追加できたか確認
curl -s http://127.0.0.1:17430/preset/current | jq '.preset.groups[0].buttons[] | select(.id=="btn-slack")'

# 4. エラーがなかったかログで確認
curl -s 'http://127.0.0.1:17430/log/tail?since=1m&level=warn' | jq
```

### 9.2 ウィンドウを画面右上に固定

```bash
curl -X POST http://127.0.0.1:17430/window/resize -d '{"width":180,"height":400}'
curl -X POST http://127.0.0.1:17430/window/move   -d '{"x":1700,"y":900}'
```

次回起動時も同じ位置/サイズで復元される (`applicationWillTerminate` で config.json に書き戻し)。

### 9.3 テスト実行ループ (AI が自律判定)

```bash
# アクション実行
curl -X POST http://127.0.0.1:17430/tools/call \
    -d '{"name":"run_action","arguments":{"type":"text","content":"test"}}'

# 直後にログから結果判定
RESULT=$(curl -s 'http://127.0.0.1:17430/log/tail?since=10s&level=warn' | jq '.events | length')
if [ "$RESULT" -gt 0 ]; then
    # warn 以上が出ている → 失敗。詳細を取得して次の手を考える
    curl -s 'http://127.0.0.1:17430/log/tail?since=10s&level=warn' | jq
fi
```

---

## 10. セキュリティと制限

- **loopback のみ** (`127.0.0.1`) にバインドされる。他ホストから到達不可
- **認証なし**。同一マシンの任意プロセスが到達可能
- 危険なシェルコマンド (`rm -rf` 等) を `run_action { launch: "shell:..." }` で送る場合は、**送る前にユーザーに確認** するのが望ましい
- `run_action { terminal }` で `execute: false` を使うと Enter を押さずにコマンドを入力だけしておける (ユーザー確認を挟める)
- パスワードや API キーをテキスト貼付する場合、**クリップボードは必ず復元される** (`restoreClipboard: true` が既定、失敗時も `defer` で復元される)

---

## 11. プロトコル互換性早見表

| AI クライアント / エコシステム | 推奨エンドポイント | 方言 |
|---|---|---|
| Claude Code / Claude Desktop | `POST /mcp` | MCP JSON-RPC 2.0 |
| Google ADK / A2A Client | `GET /.well-known/agent.json` + `POST /tools/call` | A2A Agent Card + REST |
| OpenAI Assistants / Responses API | `GET /tools?format=openai` をプロンプトに注入 | OpenAI function calling |
| Anthropic Messages API | `GET /tools?format=anthropic` をプロンプトに注入 | Anthropic tool use |
| curl / LangChain / 独自実装 | `GET /openapi.json` から生成 | ACP / REST |

---

## 12. バージョニング

現在 `version: "0.8"`。破壊的変更が入る場合は `/manifest` の `version` が更新される。AI クライアントは接続時に version を読み、互換性のない変更があったら挙動を調整するのが望ましい。

この仕様書 (`AI_PROTOCOL.md`) は常に最新実装に追従する。`/manifest` のレスポンスも同様に **実装から自動生成** されているため、ここが真実:

```bash
curl -s http://127.0.0.1:17430/manifest
```

---

## 13. Web Panel — スマホ/タブレットからの操作 (v0.13)

### 概要

LAN 公開モードを有効にすると、同じ Wi-Fi のモバイルデバイスから `/webpanel` にアクセスしてパネル UI を操作できる。認証は Bearer token ではなく **ephemeral LAN token**（再起動で失効）を使用する。

### ルート

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/webpanel` | メイン UI（HTML SSR） |
| GET | `/webpanel/assets/*` | CSS/JS/画像 |
| GET | `/webpanel/api/preset` | 現在のプリセット JSON |
| POST | `/webpanel/api/press` | ボタン実行 |

### 認証

Web Panel のリクエストには URL パラメータ `?token=<ephemeral>` を付ける。`<img>` タグ等から Authorization ヘッダーを送れないため、クエリパラメータ方式を採用。

```bash
# LAN token の取得
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/lan-token

# LAN token のローテーション
curl -X POST -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/lan-token/rotate
```

### ツール制限 (`WebPanelToolWhitelist`)

Web Panel 経由で呼べるツールは安全系に限定される（`button_press`、`preset_list`、`preset_current`、`preset_get` 等）。設定変更や削除系ツールは 403 で拒否。

### mDNS サービスタイプ

`_floatingmacro._tcp.` — Bonjour 対応クライアントからのゼロコンフィグ検出に使用。

---

## 14. 参考 — 関連プロトコル

- **MCP (Model Context Protocol)** — Anthropic: https://modelcontextprotocol.io/
- **A2A (Agent-to-Agent)** — Google: https://a2aproject.github.io/A2A/
- **OpenAI Function Calling**: https://platform.openai.com/docs/guides/function-calling
- **Anthropic Tool Use**: https://docs.anthropic.com/en/docs/tool-use
- **JSON-RPC 2.0**: https://www.jsonrpc.org/specification
- **OpenAPI 3.1**: https://spec.openapis.org/oas/v3.1.0
