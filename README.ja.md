# FloatingMacro

> AI エージェントから操作できる HTTP 制御 API を内蔵した、macOS 向けのフローティング式マクロランチャー。

[English](README.md) · [AI プロトコル](docs/AI_PROTOCOL.ja.md) · [仕様書](SPEC.md) · [デザインシステム](DESIGN.md) · [変更履歴](CHANGELOG.md)

---

## これは何?

FloatingMacro は macOS の常駐型の小さなパネルで、**フォーカスを奪わず** にユーザーが定義した **アクション**（キーコンボ / テキスト貼付 / アプリ起動 / ターミナル展開 / 複合マクロ）をワンクリックで実行します。

他のランチャー系アプリとの違いは、**ローカル HTTP 制御 API** を内蔵し、全機能を複数のプロトコル方言（MCP / A2A / OpenAI function calling / Anthropic tool use / REST + OpenAPI）で公開している点です。そのため **AI エージェントが追加のグルーコードなしに** アプリの状態観察・設定変更・アクション実行を行えます。

これは「**AI オリエンテッドな macOS ソフトウェアは今後どんな形になるだろう**」という問いに対する小さな実験です。既存アプリに AI を後付けするのではなく、**AI エージェントを最初から "第一級のユーザー" として想定すると何が起きるか** — 観察・設定・操作を追加レイヤーなしに行えるアプリを、ちっちゃなユーティリティの中で試してみたい、というモチベーションで作りました。

---

## 特徴

- **macOS ネイティブ UI** — SwiftUI + `NSPanel`、システムアクセント / ダークモードに追従
- **6 種類のアクション** — key / text / launch / terminal / delay / macro
- **プリセット機構** — グループとボタン、メニューバーから即切替
- **AI 連携ウィンドウ** — メニューバー「AI に接続...」またはフローティングパネル右上の ⚙ から開ける
  - Claude Code / Cursor / Gemini CLI / VS Code / Windsurf に **ワンクリックで MCP 登録**
  - 接続用プロンプトを Bearer トークン埋め込み済みでコピー（ChatGPT 等の MCP 非対応 AI でも操作可能）
  - 既存の MCP 設定は壊さず追記
- **1700 個以上のアイコン**
  - [Lucide](https://lucide.dev) SVG を同梱（ISC ライセンス、約 1700 個）
  - SF Symbols は実行時対応（6000+、約 120 個を設定画面のピッカーからキュレーション）
  - `com.apple.Safari` 等の bundle id でアプリアイコンを自動取得
  - 任意の PNG / JPEG / ICNS ファイルも使用可能
- **構造化 JSON ログ**（10MB でローテーション、`fmcli log tail` で検索可能）
- **GUI エディタ** — プリセット / グループ / ボタンの CRUD、色ピッカー、サイズ、アクション種別
- **ローカル HTTP 制御 API**（`127.0.0.1` のみ bind、Bearer トークン認証必須）
  - `GET /manifest` — AI エージェント向け自己紹介（無認証）
  - `GET /tools?format=mcp|openai|anthropic` — 3 方言でツール定義を取得
  - `POST /tools/call` — 統一ディスパッチ（**AI からはこれを使う**）
  - `POST /mcp` — JSON-RPC 2.0 / Model Context Protocol
  - `GET /openapi.json` — OpenAPI 3.1 仕様書
  - `GET /.well-known/agent.json` — A2A Agent Card

---

## 動作環境

- macOS 13 (Ventura) 以降
- Swift 5.9 ツールチェイン（Xcode 15 以降に同梱、自前ビルドする場合）
- Accessibility 権限（key / text / terminal アクション用）
- Automation 権限（オプション、Terminal.app / iTerm2 の制御用）

---

## クイックスタート

### インストール

リリース版の DMG を [リリースページ](https://github.com/veltrea/floating-macro/releases/latest) からダウンロードしてマウントし、`FloatingMacro.app` を `/Applications` にドラッグ。

自前でビルドする場合:

```bash
git clone https://github.com/veltrea/floating-macro.git
cd floating-macro
bash scripts/build-app.sh        # build/FloatingMacro.app に .app を生成
open build/FloatingMacro.app
```

初回起動時、macOS が Accessibility 権限を要求します。システム設定 → プライバシーとセキュリティ → アクセシビリティから許可してください。

### CLI で試す

```bash
swift run fmcli help
swift run fmcli config init              # 既定設定を作成
swift run fmcli preset list
swift run fmcli log tail --since 5m --json
swift run fmcli action launch shell:echo hello
```

### 制御 API を叩く

制御 API は本体起動時に自動で `127.0.0.1:17430` に bind されます。全エンドポイントが Bearer トークン認証必須（`/manifest` 等のディスカバリー系を除く）。トークンは初回起動時に `~/Library/Application Support/FloatingMacro/control_api_token` (mode 0600) に自動生成されます（`security` CLI 互換のため Keychain にもミラーされます）。ユーザーが何かを設定する必要はありません。

```bash
TOKEN=$(cat ~/Library/Application\ Support/FloatingMacro/control_api_token)

# 自己紹介（無認証で OK）
curl -s http://127.0.0.1:17430/manifest | jq

# 状態取得
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/state | jq

# ツール呼び出し（AI からはこの形）
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"window_opacity","arguments":{"value":0.7}}'
```

> 個別エンドポイント（`/window/opacity` 等）の直叩きは下層実装です。AI からは **`/tools/call` 経由**で呼んでください。詳細は [CLAUDE.md](CLAUDE.md) と [docs/AI_PROTOCOL.ja.md](docs/AI_PROTOCOL.ja.md)。

---

## AI エージェントと組み合わせる

### 推奨: AI 連携ウィンドウのワンクリック登録

フローティングパネル右上の ⚙ アイコン（またはメニューバー「AI に接続...」）から AI 連携ウィンドウを開き、対応クライアントの行のボタンを押すだけ。

- Claude Code / Cursor / Gemini CLI / VS Code / Windsurf には **CLI 登録**ボタン（推奨、stdio MCP 経由）
- 同じクライアントへ **HTTP 登録**ボタン（HTTP MCP 経由、上級者向け）
- ChatGPT など MCP 非対応の AI 向けには **接続用プロンプトをコピー**（AI が `curl` で `/tools/call` を叩く方式）

ボタンを押すと、Bearer トークンを Keychain から取り出して各クライアントの設定ファイル（`~/.claude.json` / `~/.cursor/mcp.json` / `~/.gemini/settings.json` 等）に追記します。既存の MCP 設定は壊しません。

クライアント別の詳細は [docs/mcp/](docs/mcp/) を参照:
- [Claude Code](docs/mcp/claude-code.md)
- [Claude Desktop](docs/mcp/claude-desktop.md)
- [Cursor](docs/mcp/cursor.md)
- [Gemini CLI](docs/mcp/gemini-cli.md)
- [ACP (curl 経由)](docs/mcp/acp.md)

### 手動で MCP 設定を書く場合

```json
{
  "mcpServers": {
    "floatingmacro": {
      "type": "http",
      "url": "http://127.0.0.1:17430/mcp",
      "headers": {
        "Authorization": "Bearer <Keychain から取得したトークン>"
      }
    }
  }
}
```

トークンは `cat ~/Library/Application\ Support/FloatingMacro/control_api_token` で取得（または互換のため `security find-generic-password -s FloatingMacro -a ControlAPIToken -w`）。

### OpenAI 互換の LLM

```bash
TOKEN=$(cat ~/Library/Application\ Support/FloatingMacro/control_api_token)
curl -s -H "Authorization: Bearer $TOKEN" \
  'http://127.0.0.1:17430/tools?format=openai' | jq '.tools'
```

返ってきた `tools` 配列を Chat Completions / Responses API の `tools` パラメータにそのまま貼り付けます。

### スクリプトから直接 REST

全エンドポイントの仕様は [docs/AI_PROTOCOL.ja.md](docs/AI_PROTOCOL.ja.md) を参照。

---

## 設定

設定ファイルは `~/Library/Application Support/FloatingMacro/` に置かれます（`FLOATINGMACRO_CONFIG_DIR` 環境変数で上書き可能）:

```
config.json              # ウィンドウ座標・アクティブなプリセット・制御API設定
presets/
  default.json           # プリセット: groups -> buttons -> actions
  writing.json
  dev.json
logs/
  floatingmacro.log      # JSON 1 行 1 イベント、10MB でローテーション
  floatingmacro.log.old
```

完全なスキーマは [SPEC.md §6](SPEC.md) を参照。GUI エディタ（メニューバー → "ボタン編集..." または `⌘E`）で通常必要な編集はすべて行えます。

> **`presets/*.json` を直接編集しないこと**。アプリ起動中はメモリ状態でディスクを上書きするため変更が消えます。AI 連携 (`/tools/call`) または GUI エディタを使ってください。

---

## アクション型の例

```json
{ "type": "key",   "combo": "cmd+shift+v" }
{ "type": "text",  "content": "ultrathink" }
{ "type": "launch", "target": "/Applications/Slack.app" }
{ "type": "launch", "target": "com.tinyspeck.slackmacgap" }
{ "type": "launch", "target": "https://claude.ai/code" }
{ "type": "launch", "target": "shell:open ~/Downloads" }
{ "type": "terminal", "app": "iTerm", "command": "cd ~/dev && claude" }
{ "type": "delay", "ms": 300 }
{ "type": "macro", "actions": [ ... ] }
```

---

## ボタンのアイコン指定

```json
{ "icon": "sf:star.fill" }           // SF Symbol (実行時レンダリング)
{ "icon": "lucide:rocket" }          // 同梱 Lucide SVG
{ "icon": "com.apple.Safari" }       // macOS bundle id - 自動取得
{ "icon": "/Applications/Slack.app" }// 任意の .app パス
{ "icon": "/path/to/custom.png" }    // 任意の画像ファイル
```

`icon` が省略され、アクションが launch かつ対象がアプリの場合、そのアプリのアイコンが自動検出されます。

---

## テスト

```bash
# ユニットテスト (高速、権限不要)
swift test

# fmcli スモーク (権限不要の CLI 表面)
bash scripts/fmcli_smoke.sh

# 制御 API スモーク (実 GUI + curl)
bash scripts/control_api_smoke.sh
```

`swift test` が "no such module XCTest" で失敗する場合、Xcode を指すように `DEVELOPER_DIR` を設定してください（Command Line Tools だけでは XCTest が含まれていません）:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

---

## プロジェクト構成

```
Sources/
  FloatingMacroCore/     純粋ロジック、UI非依存。アクション/ログ/制御APIのプロトコル層
  FloatingMacroCLI/      fmcli バイナリ
  FloatingMacroApp/      GUI (SwiftUI + NSPanel)、設定エディタ、アイコンローダ、AI 連携ウィンドウ
Tests/                   ユニットテスト
scripts/                 ビルド・スモークテスト・リリース用シェル
docs/                    AI_PROTOCOL / mcp/ (クライアント別ガイド) / manual_test
npm/                     CLI 接続用の stdio MCP server (DMG に同梱)
SPEC.md                  完全な仕様書
DESIGN.md                デザインシステム
CHANGELOG.md             変更履歴
```

---

## プロジェクトのステータス

最新リリース: **v0.6** (2026-05-01)。変更履歴は [CHANGELOG.md](CHANGELOG.md)、ロードマップは [SPEC.md §17](SPEC.md) を参照してください。公開リリースですが、作者は安定性を保証しません。Pull Request や Issue は歓迎します。

---

## クレジット

- Swift 5.9、SwiftUI、AppKit、Network.framework を使用
- [Lucide](https://lucide.dev) アイコン（ISC）を `Sources/FloatingMacroApp/Resources/lucide/` に同梱
- SF Symbols は Apple 提供、実行時のみ利用
- Windows 向けユーティリティ（Trifolium Studio 社の FloatingButton）からインスピレーションを受けつつ、macOS 向けにゼロから再設計しています。クリーンルーム方針でコードは参照せず、外部から観察可能な挙動のみを参考にしました。

完全なクレジットは [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) を参照。

---

## ライセンス

[MIT License](LICENSE) — Copyright (c) 2026 veltrea

---

## 関連ドキュメント

- [AI プロトコルマニュアル](docs/AI_PROTOCOL.ja.md) — AI エージェントがこのアプリと話す方法
- [MCP クライアント別ガイド](docs/mcp/) — Claude Code / Cursor / Gemini CLI / etc.
- [手動テストチェックリスト](docs/manual_test.ja.md) — 自動テスト対象外の目視確認項目
- [完全仕様書](SPEC.md)
- [デザインシステム](DESIGN.md)
- [変更履歴](CHANGELOG.md)
