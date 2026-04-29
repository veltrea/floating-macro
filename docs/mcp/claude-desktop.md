# Claude Desktop に FloatingMacro を登録する

> 共通の前提・接続方式の説明は [setup.md](./setup.md) を先に読んでください。

Claude Desktop は他のクライアントと事情が違うので、最初に説明します。

## Claude Desktop の特殊事情

- **無料版 (Free)**: HTTP 接続 (Custom Connector) は使えません。**CLI 接続のみが利用可能**。
- **Pro / Max / Team / Enterprise プラン**: `Settings → Connectors` の Custom Connector で URL 直接登録ができます。

そのため Claude Desktop は本体の AI 連携ウィンドウに登録ボタンを用意していません (プラン依存・OAuth 想定など複雑性が高いため)。手動登録です。CLI 接続なら無料版・Pro 版両方で使えるので、CLI を主推奨します。

## 推奨: CLI 接続 (手動登録)

### 設定ファイル

```
~/Library/Application Support/Claude/claude_desktop_config.json
```

### 手順

1. フォルダ作成 (無ければ):
   ```
   mkdir -p ~/Library/Application\ Support/Claude
   ```
2. 合言葉取得:
   ```
   security find-generic-password -s FloatingMacro -a ControlAPIToken -w
   ```
3. 設定ファイルを開く (無ければ作る):
   ```
   touch ~/Library/Application\ Support/Claude/claude_desktop_config.json
   open ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```
4. 中身 (新規なら丸ごと、既存があれば `mcpServers` の中に追記):
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

5. 保存 → Claude Desktop を **完全終了** (⌘+Q、Dock からただ消すのは不可) → 再起動。

6. 入力欄の左下にある「ツール」アイコンを開く → `floatingmacro-stdio` の項目があり、ツール一覧が見えれば接続完了。

## 代替: HTTP 接続 (Pro 以上のプラン限定)

### 手順

1. Claude Desktop を起動。
2. `Settings → Connectors` を開く。
3. 「Add custom connector」を選択。
4. URL 欄に `http://127.0.0.1:17430/mcp` を入力。
5. 合言葉を取得:
   ```
   security find-generic-password -s FloatingMacro -a ControlAPIToken -w
   ```
6. ヘッダー設定で `Authorization: Bearer <合言葉>` を追加。
7. 保存して接続テスト。

> **注意**: Claude Desktop の Custom Connector は OAuth ベースの認証を想定している部分があるため、ローカルの Bearer トークンでうまく動かない場合があります。動かない時は CLI 接続を使ってください。

## ACP 接続

詳細は [acp.md](./acp.md) 参照。Claude Desktop の Free プランで MCP 登録なしに使いたい時、または素のチャットで使いたい時に有効。

## ツール命名規則

Claude Desktop 内ではサーバー名がプレフィックスになります (例: `floatingmacro-stdio:preset_current`)。表記はクライアント実装やバージョンで揺れることがあります。

## できることの例

(他クライアントと同じ機能セット)

Claude Desktop のチャットで「floatingmacro のボタンを並べ替えて」のように依頼。

## トラブルシューティング

### ツール一覧に floatingmacro-stdio が出ない
- 設定ファイルの絶対パスを再確認 (`~` は展開されないことがある、`/Users/<NAME>/...` で書く)
- Node.js が PATH 上にあるか: `/bin/zsh -lc 'command -v npx'`
- ログを確認:
  ```
  tail -f ~/Library/Logs/Claude/mcp*.log
  ```
  `Failed to start MCP server` や `command not found` のメッセージがあれば、shell から npx が見えていません。`~/.zshrc` の PATH を見直し。

### ツールが赤く失敗する
- 本体 (FloatingMacro) が起動していない: `curl http://127.0.0.1:17430/ping` で確認
- 認証エラー (`HTTP 401`): 設定ファイル内の合言葉が古い。`security find-generic-password ...` で取り直して設定ファイルを更新

### 設定ファイルの JSON が壊れている
```
python3 -m json.tool ~/Library/Application\ Support/Claude/claude_desktop_config.json
```
で構文を確認。

### Claude Desktop が起動しなくなった
設定ファイルの JSON が壊れている可能性。バックアップから復元するか、`mcpServers` の中身を `{}` に戻して起動できるか確認。

## 将来の改善

Claude Desktop 用にも本体ボタンでの登録を提供することは技術的に可能ですが、無料版・Pro 版でフローが分岐する複雑性のため現在は未対応です。
