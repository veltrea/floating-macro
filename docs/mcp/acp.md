# ACP 接続 — 標準 Agent Communication Protocol で FloatingMacro を呼ぶ

> 共通の前提・接続方式の説明は [setup.md](./setup.md) を先に読んでください。

FloatingMacro は **Agent Communication Protocol (ACP)** に準拠したサーバーとして動きます。ACP は Linux Foundation のもとで策定されている、エージェントを発見し実行するためのオープンな REST 仕様です。

- 仕様: <https://agentcommunicationprotocol.dev/>
- OpenAPI: <https://github.com/i-am-bee/acp/blob/main/docs/spec/openapi.yaml>

## なぜ FloatingMacro が ACP に対応するのか

### 1. AI 時代のアプリは「内蔵」より「手足として呼ばれる」

ここ数年、アプリケーションに AI モデルを内蔵する形の実装が一般的でした。しかしモデルが日々進化していく状況で、特定のモデルや SDK をアプリに焼き付ける設計は急速に陳腐化します。

FloatingMacro は逆のアプローチを取ります。**AI から手足のように呼べる構造**にしておけば、AI 側のモデルが進化しても、アプリ自体は手を入れずに恩恵を受けられます。ACP はその「外から呼ぶ」ための標準プロトコルとしてちょうど良い位置にあります。

### 2. このアプリに合うサブセットを選ぶ

ACP には Run lifecycle、async、streaming、sessions、await/resume、cancel など豊富な機能があります。これらはすべて **オプトイン** として設計されています。

FloatingMacro のツール群は、いずれも短時間・同期・状態を持たない操作です。長時間ジョブやストリーミング応答を持ちません。したがって本サーバーは **stateless + sync-only** のサブセットだけを実装し、その姿勢を `capabilities` で正直に宣言します。フル準拠を目指さないことは、このアプリの性質に対する妥当な設計判断です。

### 3. 開発者と AI が同じ経路でテストを回せる

HTTP 経由で呼べる構造を最初から組み込むことで、開発者自身が curl で end-to-end テストを書くのと、AI エージェントがアプリを自動操作するのは、**まったく同じインターフェース**を使うことになります。テスト用の特殊な経路や、AI 用の別経路を持ちません。

### 4. 権限は Keychain ベースの Bearer トークンで明示

「AI の手足になる」とは、無制限に動かせるという意味ではありません。`POST /runs` は macOS Keychain に保存されたトークンを Bearer 認証で要求します。ユーザーが意図して渡したトークンを持つ AI だけがアプリを操作できる、という境界が常に存在します。

### 5. MCP もサポートする — 普及している経路への入口として

ACP は仕様としては良くできていますが、現時点で実際の AI クライアントに広く実装されているプロトコルは **MCP (Model Context Protocol)** です。Claude Code、Cursor、Gemini CLI などはほぼ MCP で繋がります。

そのため FloatingMacro は ACP の `/runs` だけでなく、MCP（stdio + HTTP）も並行して提供します。**FloatingMacro が便利であることをまず知ってもらうための入口**として、ユーザーが普段使っているツールから素直に繋がる必要があるからです。MCP 経路は本質的には ACP と同じディスパッチに落ちる薄いラッパーで、機能差はありません。

## 準拠している範囲

| 機能 | 対応 |
|---|---|
| `GET /agents` | ✅ 実装 |
| `GET /agents/{name}` | ✅ 実装 |
| `POST /runs` (`mode: "sync"`) | ✅ 実装 |
| `POST /runs` (`mode: "async"` / `"stream"`) | ❌ 501 Not Implemented |
| `GET /runs/{run_id}` / events / resume / cancel | ❌ 501 Not Implemented |
| sessions | ❌ 未対応（`session_id` は受理して echo のみ）|

## 仕組み

```
 ┌──────────────┐  POST /runs  ┌──────────────────┐
 │  ACP Client   │ ───────────► │ FloatingMacro 本体 │
 │  (sync mode)  │              │  (sync executor)  │
 └──────────────┘              └──────────────────┘
```

エージェントは 1 つだけ。名前は `floatingmacro`。あらゆる操作（パネル制御・グループ/ボタン CRUD・マクロ実行など）は **このエージェントへの sync run** として表現されます。

## 認証

ACP のディスカバリー (`GET /agents`, `GET /agents/floatingmacro`) は **認証不要**。これは「エージェントの存在と認証要件を、認証前に発見できる」ためです。

`POST /runs` は **Bearer トークン必須**。

```bash
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
```

以降のリクエストには `Authorization: Bearer $TOKEN` を付けます。

## ステップ 1 — ディスカバリー

エージェント一覧:

```bash
curl -s http://127.0.0.1:17430/agents | jq
```

返り値:

```json
{
  "agents": [
    {
      "name": "floatingmacro",
      "description": "FloatingMacro control agent (sync, stateless)."
    }
  ]
}
```

エージェント manifest:

```bash
curl -s http://127.0.0.1:17430/agents/floatingmacro | jq
```

返り値の主要部分:

```json
{
  "name": "floatingmacro",
  "description": "FloatingMacro — a macOS floating macro launcher. ...",
  "input_content_types":  ["application/json"],
  "output_content_types": ["application/json"],
  "capabilities": {
    "supports_sync":      true,
    "supports_async":     false,
    "supports_streaming": false,
    "supports_sessions":  false,
    "supports_resume":    false,
    "supports_cancel":    false
  },
  "metadata": {
    "documentation": "http://127.0.0.1:17430/manifest",
    "tool_catalog":  "http://127.0.0.1:17430/tools",
    "tool_invocation_format":
      "Encode the tool call as a single Message part with content_type=application/json and content {\"tool\":\"<name>\",\"arguments\":{...}}"
  },
  "skills": [
    { "name": "ping", "description": "Health check.", "input_schema": { ... } },
    { "name": "window_opacity", "description": "Set panel opacity. ...", "input_schema": { ... } },
    ...
  ]
}
```

`skills` は ACP 標準フィールドではなく、FloatingMacro の拡張フィールドです。利用可能な操作 (約 46 種) を 1 リクエストで列挙できるようにしてあります。標準の `/tools` や `/manifest` でも同じカタログが取れます。

## ステップ 2 — `POST /runs` で sync 実行

ACP の Run モデルでは、エージェントへの入力は **Message の配列** で、各 Message は **複数の part** を持てます (text, image, JSON など content_type で区別)。

FloatingMacro は **JSON 1 part** を入力として受け取ります。Part の `content` には次の形の JSON を文字列で詰めます:

```json
{
  "tool":      "<tool_name>",
  "arguments": { ... }
}
```

### 例: ping

```bash
curl -s -X POST http://127.0.0.1:17430/runs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "agent_name": "floatingmacro",
        "input": [
          {
            "role": "user",
            "parts": [
              {
                "content_type": "application/json",
                "content": "{\"tool\":\"ping\"}"
              }
            ]
          }
        ]
      }'
```

返り値:

```json
{
  "run_id": "run_a0a13bb641ec40b5bd0a92a3b122bc38",
  "agent_name": "floatingmacro",
  "session_id": null,
  "status": "completed",
  "output": [
    {
      "role": "agent",
      "parts": [
        {
          "content_type": "application/json",
          "content": "{\"ok\":true,\"product\":\"FloatingMacro\"}"
        }
      ]
    }
  ],
  "error": null,
  "created_at":  "2026-04-27T17:12:21.868Z",
  "finished_at": "2026-04-27T17:12:21.869Z"
}
```

### 例: 引数つき (パネルの透過度を 0.85 に)

```bash
curl -s -X POST http://127.0.0.1:17430/runs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "agent_name": "floatingmacro",
        "input": [{
          "role": "user",
          "parts": [{
            "content_type": "application/json",
            "content": "{\"tool\":\"window_opacity\",\"arguments\":{\"value\":0.85}}"
          }]
        }]
      }'
```

返り値の `output[0].parts[0].content` に `{"opacity":0.85}` が文字列で入って返ります。

### 既定値 / 省略可能フィールド

- `agent_name` を省略した場合は `"floatingmacro"` とみなします
- `mode` を省略した場合は `"sync"` とみなします (ACP 仕様の既定)
- `session_id` を渡しても受理して echo するだけで、状態は保存しません

## エラーの返り方

ACP では「リクエスト自体の不正」と「リクエストは受理したがツールが失敗した」を分けます。FloatingMacro も同様に：

| 状況 | HTTP ステータス | レスポンス |
|---|---|---|
| `agent_name` がこのサーバーにない | 404 | プレーンエラー JSON |
| `mode` が `sync` 以外 | 501 | プレーンエラー JSON |
| 入力の形式不正 | 400 | プレーンエラー JSON |
| 未知のツール名 | 200 | Run 形式 / `status: "failed"` / `error.code: 404` |
| ツールが内部エラーを返した | 200 | Run 形式 / `status: "failed"` / `error.code: 500` |
| ツールが正常終了 | 200 | Run 形式 / `status: "completed"` |

例 (未知のツール):

```json
{
  "run_id": "run_d7407b306e29404395d538168c5f283e",
  "agent_name": "floatingmacro",
  "session_id": null,
  "status": "failed",
  "output": [],
  "error": {
    "code": 404,
    "message": "unknown tool 'nope_does_not_exist'"
  },
  "created_at":  "...",
  "finished_at": "..."
}
```

## 未実装エンドポイントの挙動

仕様にあるが本サーバーが未対応のエンドポイントは、明示的に **501 Not Implemented** を返します:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:17430/runs/run_xxx
```

```json
{
  "error": "not implemented",
  "detail": "this agent is stateless / sync-only; no run lifecycle, sessions, events, resume, or cancel"
}
```

これにより、ACP クライアントは manifest の `capabilities` と合わせて「このサーバーは sync しか喋らない」ことを確実に把握できます。

## ACP / `/tools/call` / MCP の使い分け

FloatingMacro は同じツール群を 3 つの経路で公開しています。中身は同じディスパッチに落ちるので、結果は等価です。

| 経路 | 想定クライアント | 適している場面 |
|---|---|---|
| **`POST /runs`** (ACP) | ACP 準拠のエージェント / オーケストレーター | 標準仕様で連携する。複数の ACP エージェントを並べて運用する |
| **`POST /tools/call`** | curl で叩きたい AI、シェルスクリプト | 1 行で呼べる軽量経路。Message parts のラッパーが不要 |
| **`POST /mcp`** | MCP 対応 AI ツール (Claude Code, Cursor 等) | クライアント側で MCP 設定済みのとき。stdio 推奨だが HTTP 版もある |

## 認証不要のディスカバリーエンドポイント一覧

トークンなしで叩けるエンドポイント:

- `GET /manifest` / `GET /help` — システムプロンプト + 全ツール定義 + クイックスタート
- `GET /openapi.json` — OpenAPI 形式のスキーマ
- `GET /.well-known/agent.json` — Agent Card (A2A 系の Agent Discovery 用)
- `GET /agents` — ACP のエージェント一覧
- `GET /agents/floatingmacro` — ACP のエージェント manifest
- `GET /ping` / `GET /health` — 生存確認

## トラブルシューティング

### `Connection refused`
本体が起動していない、もしくはポート違い。`curl http://127.0.0.1:17430/ping` で確認。

### `HTTP 401 Unauthorized` (POST /runs で)
Bearer トークンが一致しない。`security find-generic-password ...` で取り直す。

### `HTTP 501` が返ってくる
`mode` を `"sync"` 以外にしているか、`/runs/{id}` 系のライフサイクルエンドポイントを叩いている。本サーバーは sync only なので、リクエストを sync に変更するか、`/tools/call` 経由に切り替える。

### Run 結果が `status: "failed"` で返ってくる
これは ACP の正常な経路です。HTTP は 200 でも、`error.code` と `error.message` を確認してください。「ツールは見つかったが内部処理で失敗した」「ツール名が不明だった」などはここに入ります。

### Message の `content` を JSON オブジェクトのまま埋め込みたい
ACP の Message part は `content` を文字列として運ぶのが標準です。本サーバーは互換のため、`content` がオブジェクトでも文字列でもどちらでも受け付けます (オブジェクトのときは内部で JSON 化されます)。
