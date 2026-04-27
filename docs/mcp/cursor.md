# Cursor に FloatingMacro を登録する

> 共通の前提・接続方式の説明は [setup.md](./setup.md) を先に読んでください。

## 推奨: 本体の「CLI 登録」ボタン

### 手順

1. FloatingMacro 本体のフローティングパネルの右上にある **歯車アイコン (⚙)** を押す。または、メニューバーのアイコンから「AI に接続...」を選ぶ。
2. 開いた「AI 連携」ウィンドウの中、Cursor の行の **左側にある青い「CLI 登録」ボタン** を押す。
3. 「Cursor に CLI 版を登録しました (floatingmacro-stdio)。」と緑のメッセージが出れば成功。
4. Cursor を **完全終了** (⌘+Q) して再起動。Reload Window だけでは反映されないことがあるので必ず終了。
5. Cursor の `Settings → MCP Servers` を開く。`floatingmacro-stdio` の行に **緑のドット** が点いて、ツール数が表示されれば接続完了。

### このボタンが裏でやっていること

- 認証用の合言葉を Keychain から取り出す
- `~/.cursor/` フォルダを必要なら作成
- `~/.cursor/mcp.json` の `mcpServers` に追加 (既存設定は壊さない):
  ```json
  "floatingmacro-stdio": {
    "command": "/bin/zsh",
    "args": [
      "-lc",
      "exec npx -y 'file:/Applications/FloatingMacro.app/Contents/Resources/npm' --token '<合言葉>'"
    ]
  }
  ```

## 代替 1: CLI 手動登録

Cursor には MCP 専用 CLI コマンドが無いので、設定ファイル直接編集です。

1. フォルダ作成:
   ```
   mkdir -p ~/.cursor
   ```
2. 合言葉取得:
   ```
   security find-generic-password -s FloatingMacro -a ControlAPIToken -w
   ```
3. ファイル作成 (無ければ):
   ```
   touch ~/.cursor/mcp.json
   ```
4. エディタで開く:
   ```
   open -a TextEdit ~/.cursor/mcp.json
   ```
5. 中身 (新規なら丸ごと、既存があれば追記):
   ```json
   {
     "mcpServers": {
       "floatingmacro-stdio": {
         "command": "/bin/zsh",
         "args": [
           "-lc",
           "exec npx -y 'file:/Applications/FloatingMacro.app/Contents/Resources/npm' --token '<ステップ2で取った合言葉>'"
         ]
       }
     }
   }
   ```
6. 保存 → Cursor 完全終了 → 再起動 → `Settings → MCP Servers` で確認。

## 代替 2: HTTP 接続で登録する

### 本体の「HTTP 登録」ボタン

Cursor 行の右側「HTTP 登録」ボタンを押す。`~/.cursor/mcp.json` の `mcpServers` に以下が追加されます:

```json
"floatingmacro": {
  "url": "http://127.0.0.1:17430/mcp",
  "headers": {
    "Authorization": "Bearer <合言葉>"
  }
}
```

Cursor は Claude Code と違って `"type": "http"` を書く必要はありません (`url` の存在で HTTP transport と判別)。

### HTTP 手動登録

1. 合言葉取得:
   ```
   security find-generic-password -s FloatingMacro -a ControlAPIToken -w
   ```
2. `~/.cursor/mcp.json` の `mcpServers` に追記:
   ```json
   "floatingmacro": {
     "url": "http://127.0.0.1:17430/mcp",
     "headers": {
       "Authorization": "Bearer <合言葉>"
     }
   }
   ```
3. 保存 → Cursor 再起動 → `Settings → MCP Servers` で確認。

## 代替 3: ACP 接続

詳細は [acp.md](./acp.md) 参照。

## ツール命名規則

Cursor 内でのツール名は `<server>:<tool_name>` 形式 (例: `floatingmacro-stdio:preset_current`)。

## できることの例

(Claude Code と同じ機能セット)

Cursor の AI チャットで「floatingmacro のプリセットを見せて」「floatingmacro に新しいボタンを追加して」のように依頼。

## トラブルシューティング

### `Settings → MCP Servers` で赤くなっている
- 本体起動確認: `curl http://127.0.0.1:17430/ping`
- Node.js 確認 (CLI 版): `/bin/zsh -lc 'command -v npx'` で npx パスが出るか
- JSON 構文: `python3 -m json.tool ~/.cursor/mcp.json`

### 設定変更が反映されない
Reload Window では足りない。完全終了 (⌘+Q) → 再起動。

### Cursor のバージョンが古い (HTTP 接続が動かない)
HTTP transport は v0.48.0 以降。古いバージョンでは CLI 版を使ってください。

### ログ確認
Help → Toggle Developer Tools → Console。`Failed to start MCP server` 等を探す。
