# Claude Code に FloatingMacro を登録する

> 共通の前提・接続方式の説明は [setup.md](./setup.md) を先に読んでください。

## 推奨: 本体の「CLI 登録」ボタン

### 手順

1. FloatingMacro 本体のフローティングパネルの右上にある **歯車アイコン (⚙)** を押す。または、メニューバーのアイコンから「AI に接続...」を選ぶ。
2. 開いた「AI 連携」ウィンドウの「AI クライアントに MCP として登録」ブロックの中、Claude Code の行の **左側にある青い「CLI 登録」ボタン** を押す。
3. 「Claude Code に CLI 版を登録しました (floatingmacro-stdio)。」と緑のメッセージが出れば成功。
4. Claude Code を **完全終了** (⌘+Q) して再起動。
5. ターミナルで `claude mcp list` を実行。`floatingmacro-stdio - ✓ Connected` と表示されれば接続完了。

### このボタンが裏でやっていること

- macOS Keychain から認証用の合言葉を取り出す
- ユーザーの $SHELL を確認 (通常 `/bin/zsh`)
- アプリバンドル内の同梱 npm パッケージのパスを取得
- `~/.claude.json` を読み込む (無ければ新規作成扱い)
- ファイルの `mcpServers` セクションに以下のエントリを追加 (既存の他のサーバーは触らない):
  ```json
  "floatingmacro-stdio": {
    "command": "/bin/zsh",
    "args": [
      "-lc",
      "exec npx -y 'file:/Applications/FloatingMacro.app/Contents/Resources/npm' --token '<合言葉>'"
    ]
  }
  ```
- atomic 書き込みで保存

login shell 経由で起動するため、ユーザーが fnm / nvm / Homebrew どれで Node.js を入れていても、`~/.zshrc` から PATH が組み立てられて npx が見つかります。

## 代替 1: CLI を CLI コマンドで登録

Claude Code には `claude mcp add` という MCP 登録専用のコマンドがあります。本体ボタンを使わず手動でやりたい場合:

```
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
claude mcp add floatingmacro-stdio /bin/zsh \
    -lc "exec npx -y 'file:/Applications/FloatingMacro.app/Contents/Resources/npm' --token '$TOKEN'"
```

確認:

```
claude mcp list
```

`floatingmacro-stdio - ✓ Connected` が出れば成功。

## 代替 2: HTTP 接続で登録する

CLI ではなく HTTP で直接接続したい場合。

### 本体の「HTTP 登録」ボタン

「AI 連携」ウィンドウで Claude Code 行の **右側、白枠の「HTTP 登録」ボタン** を押す。`~/.claude.json` の `mcpServers` に以下が追加されます:

```json
"floatingmacro": {
  "type": "http",
  "url": "http://127.0.0.1:17430/mcp",
  "headers": {
    "Authorization": "Bearer <Keychain から取った合言葉>"
  }
}
```

登録名は `floatingmacro` (CLI 版とは別名)。再起動後 `claude mcp list` で `floatingmacro: HTTP - ✓ Connected` を確認。

### HTTP 手動登録

1. 合言葉取得:
   ```
   security find-generic-password -s FloatingMacro -a ControlAPIToken -w
   ```
2. `~/.claude.json` をエディタで開く:
   ```
   open -a TextEdit ~/.claude.json
   ```
3. `mcpServers` の中に追記:
   ```json
   "floatingmacro": {
     "type": "http",
     "url": "http://127.0.0.1:17430/mcp",
     "headers": {
       "Authorization": "Bearer <ステップ1で取った合言葉>"
     }
   }
   ```
4. 保存 → Claude Code 再起動 → `claude mcp list` で確認。

## 代替 3: ACP 接続 (curl で直接叩く / プロンプト貼付け)

詳細は [acp.md](./acp.md) を参照してください。

## ツール命名規則

Claude Code 内でのツール名:
- CLI 版: `mcp__floatingmacro-stdio__<tool_name>` (例: `mcp__floatingmacro-stdio__preset_current`)
- HTTP 版: `mcp__floatingmacro__<tool_name>` (例: `mcp__floatingmacro__preset_current`)

## CLI 版と HTTP 版の共存

両方を同時に登録できます。同名衝突しないよう本体ボタンは別名 (`floatingmacro-stdio` と `floatingmacro`) で書き込むため、`claude mcp list` には 2 行出ます。Claude Code セッションでは両方のツールが見えますが、機能は同一なのでどちらでも使えます。

## できることの例

- ボタン・グループ・プリセットの追加・編集・削除・並べ替え・移動
- フローティングパネルの位置・透明度・表示/非表示制御
- アクション (テキスト貼付・キーボードショートカット送出・アプリ起動・ターミナル実行) の即時実行
- 実行ログの確認
- 現在の設定の確認

Claude Code セッション中に「floatingmacro のマニフェストを見せて」と頼むと、利用可能な全ツールの一覧が確認できます。

## トラブルシューティング

### 「CLI 登録」したのに `claude mcp list` で出ない
- Claude Code を完全終了 (⌘+Q) してから再起動したか確認
- `~/.claude.json` の JSON が壊れていないか: `python3 -m json.tool ~/.claude.json`

### `npx: command not found` (CLI 版)
Node.js が PATH 上にない。`/bin/zsh -lc 'command -v npx'` で確認。出ない場合は `~/.zshrc` を見直して PATH に Node.js を追加。

### `tool xxx failed: HTTP 401`
合言葉が一致しません。本体ボタンを押し直してください。Keychain のトークンを再生成したい場合は本体の機能で対応 (本体再起動でも同じトークンが維持されます)。

### 本体が動いているか
```
curl http://127.0.0.1:17430/ping
```
200 が返らなければ本体が落ちている。
