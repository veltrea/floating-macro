# MCP 統合 — 実装ハンドオーバー

このドキュメントは FloatingMacro の MCP (Model Context Protocol) 統合の現状と、次セッションで作業を継続する場合の手順をまとめたものです。

---

## 1. 現状サマリー

FloatingMacro は AI クライアント (Claude / Cursor / Gemini CLI / VS Code / Windsurf 等) から操作可能で、3 系統の接続方式をサポートしています。

| 系統 | 実装場所 | クライアント側設定 |
|---|---|---|
| **CLI 接続** | `npm/` (Node.js 製、本体バンドル `Contents/Resources/npm/` に同梱) | `command: /bin/zsh, args: ["-lc", "exec npx -y file:<bundle>/Contents/Resources/npm --token <T>"]` |
| **HTTP 接続** | 本体内蔵 (`/mcp` エンドポイント) | `command/url: http://127.0.0.1:17430/mcp + Authorization: Bearer <T>` |
| **ACP 接続** | 本体内蔵 (`/tools/call` エンドポイント) | AI への接続用プロンプト貼付け |

すべての登録は本体の **AI 連携ウィンドウ** にあるボタンから自動化できます。

## 2. 主要ファイル

| ファイル | 役割 |
|---|---|
| `Sources/FloatingMacroApp/AIIntegrationView.swift` | AI 連携ウィンドウの SwiftUI ビュー。各クライアント行に「CLI 登録」「HTTP 登録」ボタン |
| `Sources/FloatingMacroApp/AIIntegrationWindowController.swift` | AI 連携ウィンドウのライフタイム管理 |
| `Sources/FloatingMacroApp/ControlAPI/ControlHandlers.swift` | HTTP API ハンドラ。`/ai-integration/open`, `/ai-integration/close` を提供 |
| `Sources/FloatingMacroCore/ControlAPI/ToolCatalog.swift` | 全 46 ツールの定義。`run_action` の `inputSchema` には `type: "object"` が必須 (Gemini CLI のバリデータが厳格) |
| `npm/package.json`, `npm/bin/floatingmacro-mcp.mjs` | Node.js 製 MCP stdio server。HTTP API への薄いプロキシ |
| `scripts/build-app.sh` | アプリバンドル組み立て。`npm/` を `Contents/Resources/npm/` にコピー |
| `docs/mcp/*.md` | ユーザー向けマニュアル (各クライアント別 + setup + acp) |

## 3. 削除済みの旧実装

- `Sources/FloatingMacroCLI/MCPStdioServer.swift` (旧 Swift 製 stdio サーバー、~134 行) — 削除済み
- `Sources/FloatingMacroCLI/main.swift` 内の `case "mcp"` (旧 fmcli mcp サブコマンド) — 削除済み

旧実装の問題点:
- Swift ネイティブバイナリのため、macOS 15 Sequoia の codesign 検証で SIGKILL 対象
- ad-hoc 署名はビルド毎にハッシュが変わり、Keychain ACL がリセットされる
- ZIP 解凍時の quarantine xattr で再度ブロックされる
- 配布物として真っ当に通すには Apple Developer ID 署名 + Notarization が必要

これらの問題を Node.js 製 npm パッケージに置き換えることで完全回避しました。

## 4. アプリバンドル内 npm 同梱の仕組み

`scripts/build-app.sh` のセクション 3.5 で以下を実行:

```bash
cp -R "$ROOT/npm" "$RES_DIR/npm"
rm -rf "$RES_DIR/npm/node_modules" "$RES_DIR/npm/.git"
```

結果として `FloatingMacro.app/Contents/Resources/npm/` に配置されます。

本体ボタンが書き込む設定値:
```json
"floatingmacro-stdio": {
  "command": "/bin/zsh",
  "args": [
    "-lc",
    "exec npx -y 'file:/Applications/FloatingMacro.app/Contents/Resources/npm' --token '<TOKEN>'"
  ]
}
```

`/bin/zsh -lc` でログインシェルを起動 → ユーザーの `~/.zshrc` から PATH を構築 → `npx` が見つかる、という形で fnm / nvm / Homebrew のどの Node.js インストール方式でも動作します。

## 5. 動作確認のクイックチェック

### 本体起動確認
```
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:17430/ping
# 期待: 200
```

### npm 版 (CLI 接続) の素のテスト
```
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
BUNDLE_NPM=/Applications/FloatingMacro.app/Contents/Resources/npm
# 開発ビルドの場合は ./build/FloatingMacro.app/Contents/Resources/npm
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ping","arguments":{}}}' \
  | /bin/zsh -lc "exec npx -y 'file:$BUNDLE_NPM' --token '$TOKEN'"
# 期待: 3 行の JSON、id=2 で 46 ツール、id=3 で ping ok:true
```

### HTTP 接続の確認
```
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"ping","arguments":{}}'
# 期待: {"name":"ping","result":{"ok":true,"product":"FloatingMacro"},"status":200}
```

## 6. 既知の制約・将来課題

- **Claude Desktop 用の本体ボタンは未提供**: 無料版は HTTP 不可で stdio のみ、Pro 以上は OAuth ベースの Custom Connector のため、フローが分岐して複雑。手動登録ガイドのみ提供 (`docs/mcp/claude-desktop.md`)。
- **Trae / Antigravity の HTTP MCP 対応状況は未確認**: 公式ドキュメント取得が出来なかったため詳細不明。CLI (stdio) なら設定ファイル形式は他クライアントとほぼ共通のはず。
- **npm パッケージは未 publish**: 現状はアプリバンドル内同梱の `file:` プロトコル参照のみ。npm registry に publish すれば `npx -y @veltrea/floatingmacro-mcp` という標準的な指定が使えるようになる。
- **配布版 (Notarization) 未対応**: 本体は ad-hoc 署名のため、Apple の正式配布チャネル (Developer ID + Notarization) は未整備。

## 7. 次セッション着手時の推奨手順

1. このファイル + `docs/mcp/setup.md` で全体像を把握
2. アプリ起動 → `curl http://127.0.0.1:17430/ping` で 200 確認
3. 上記「5. 動作確認のクイックチェック」を実行して回帰がないか確認
4. ToDo を確認 (例: 5 クライアント実機検証、npm publish、Notarization)

## 8. 絶対に守るルール

1. **MCP stdio に Content-Length ヘッダーを付けない** (LSP の発想を持ち込まない)
2. **stdout に絵文字や print デバッグを出さない** (JSONL 通信が壊れる)
3. **`floatingmacro-mcp` から FloatingMacro 本体を起動しない** (プロセス多重起動を絶対回避)
4. **コミットメッセージに AI 著作権表記を入れない** (`Co-Authored-By: Claude` 等は禁止)
5. **設定ファイル (`~/Library/Application Support/FloatingMacro/presets/*.json`) を直接編集しない** — アプリが上書きする。必ず `/tools/call` 経由で
