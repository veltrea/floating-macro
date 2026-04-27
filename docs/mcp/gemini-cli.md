# Gemini CLI に FloatingMacro を登録する

> 共通の前提・接続方式の説明は [setup.md](./setup.md) を先に読んでください。

## 推奨: 本体の「CLI 登録」ボタン

### 手順

1. FloatingMacro 本体のフローティングパネルの右上の **歯車アイコン (⚙)** を押す。または、メニューバーから「AI に接続...」を選ぶ。
2. 開いた「AI 連携」ウィンドウで、Gemini CLI の行の **左側「CLI 登録」ボタン** を押す。
3. 「Gemini CLI に CLI 版を登録しました (floatingmacro-stdio)。」と出れば成功。
4. すでに `gemini` セッションが起動中なら、そのセッション内で `/mcp reload` を実行するか、`gemini` を再起動。
5. `gemini` 起動後 `/mcp list` で `floatingmacro-stdio - Ready (46 tools)` を確認。

### このボタンが裏でやっていること

- 認証用の合言葉を Keychain から取り出す
- `~/.gemini/` フォルダを必要なら作成
- `~/.gemini/settings.json` の `mcpServers` に追加 (既存設定は壊さない):
  ```json
  "floatingmacro-stdio": {
    "command": "/bin/zsh",
    "args": [
      "-lc",
      "exec npx -y 'file:/Applications/FloatingMacro.app/Contents/Resources/npm' --token '<合言葉>'"
    ]
  }
  ```

## 代替 1: CLI コマンドで登録

Gemini CLI には MCP 登録専用のサブコマンドがあります。

```
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
gemini mcp add floatingmacro-stdio /bin/zsh \
    -lc "exec npx -y 'file:/Applications/FloatingMacro.app/Contents/Resources/npm' --token '$TOKEN'"
```

> **重要**: 名前にアンダースコアを使わないでください (`floatingmacro_stdio` は不可)。Gemini CLI のツール名は `mcp_<serverName>_<toolName>` 形式で、最初の `_` で分割されるため、アンダースコア入りの名前は誤解析されます。ハイフン (`-`) を使ってください。

サブコマンド:
- `gemini mcp list` — 登録済み一覧
- `gemini mcp remove floatingmacro-stdio` — 削除
- `gemini mcp disable floatingmacro-stdio` / `gemini mcp enable floatingmacro-stdio` — 一時的有効/無効
- `gemini mcp disable floatingmacro-stdio --session` — 現セッションだけ無効化

## 代替 2: HTTP 接続で登録する

### 本体の「HTTP 登録」ボタン

Gemini CLI 行の右側「HTTP 登録」を押す。`~/.gemini/settings.json` に以下が追加されます:

```json
"floatingmacro": {
  "httpUrl": "http://127.0.0.1:17430/mcp",
  "headers": {
    "Authorization": "Bearer <合言葉>"
  }
}
```

> **Gemini CLI 独自ルール**: URL のキー名は `url` ではなく **`httpUrl`** です。Gemini CLI は `httpUrl` を `StreamableHTTPClientTransport` にマップし、`url` (古い SSE 用) と区別します。

### HTTP 手動登録

1. 合言葉取得:
   ```
   security find-generic-password -s FloatingMacro -a ControlAPIToken -w
   ```
2. `~/.gemini/settings.json` の `mcpServers` に追記:
   ```json
   "floatingmacro": {
     "httpUrl": "http://127.0.0.1:17430/mcp",
     "headers": {
       "Authorization": "Bearer <合言葉>"
     }
   }
   ```
3. 保存 → `gemini` 起動 → `/mcp list` で確認。

## 代替 3: ACP 接続

詳細は [acp.md](./acp.md) 参照。

## ツール命名規則

Gemini CLI 内でのツール名は `mcp_<serverName>_<toolName>` 形式:
- CLI 版: `mcp_floatingmacro-stdio_<tool_name>`
- HTTP 版: `mcp_floatingmacro_<tool_name>`

## できることの例

(他クライアントと同じ機能セット)

`gemini` セッションで「floatingmacro のプリセット見せて」「パネルの透明度を 80% にして」と依頼。

## トラブルシューティング

### 接続するがツール呼び出し失敗
本体起動確認: `curl http://127.0.0.1:17430/ping`

### `command not found: npx` (CLI 版)
Node.js が PATH 上にない。`/bin/zsh -lc 'command -v npx'` で確認。出なければ `~/.zshrc` 見直し。

### `httpUrl` と `url` の違い (HTTP 版)
`httpUrl` → Streamable HTTP transport (推奨)
`url` → SSE transport (古い)
FloatingMacro は Streamable HTTP なので必ず `httpUrl` を使う。

### `/mcp reload` が効かない
セッションを再起動してください。

### `Connection closed` エラー
本体ボタンを押し直して登録内容をリセット。それでも改善しない場合は本体を再起動して再度 `/mcp reload`。
