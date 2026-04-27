# FloatingMacro を AI クライアントに接続する — 共通ガイド

FloatingMacro を Claude / Cursor / Gemini CLI / VS Code / Windsurf などの AI ツールから操作できるようにするための共通ガイドです。各クライアント別の手順は別ファイルにあります。

- [Claude Code 向け](./claude-code.md)
- [Claude Desktop 向け](./claude-desktop.md)
- [Cursor 向け](./cursor.md)
- [Gemini CLI 向け](./gemini-cli.md)
- [ACP (curl・AI へのプロンプト貼付け) 向け](./acp.md)

---

## 接続方式は 3 種類あります

FloatingMacro は AI クライアントとの接続方式を 3 つ用意しています。どれを選んでも最終的に同じ機能セットが使えます。

### 方式 1: CLI 接続 (推奨)

FloatingMacro 本体に同梱されている小さな Node.js 製 MCP server (`floatingmacro-mcp` という npm パッケージ) を、AI クライアントが必要に応じて起動して標準入出力で会話する方式。中身は HTTP API への薄いプロキシで、状態を持ちません。

- 本体に「CLI 登録」ボタンが用意されているので、ワンクリックで設定完了
- 認証用の合言葉は本体ボタンが裏で取り扱うため、ユーザーが触る必要は無い
- npm パッケージなので macOS の codesign / Gatekeeper / Keychain ACL のトラブルから完全に逃れられる

ほぼ全ての主要 AI クライアント (Claude Code / Cursor / Gemini CLI / VS Code Copilot / Windsurf / Claude Desktop) でこの方式が使えます。

### 方式 2: HTTP 接続 (中級者向け)

FloatingMacro 本体が起動中ずっと開いている `http://127.0.0.1:17430/mcp` という HTTP の窓口に、AI クライアントが直接接続する方式。

- 中間プロセスを挟まないので起動が少し早い
- AI クライアント側の設定ファイルに URL と Bearer ヘッダーが書かれる
- 本体に「HTTP 登録」ボタンが用意されているので、設定ファイルを手で書きたくなければボタンで完了

Claude Code / Cursor / Gemini CLI / VS Code / Windsurf は HTTP transport をサポートしているので、こちらの方式でもつながります。

### 方式 3: ACP 接続 (上級者・MCP 非対応 AI 向け)

MCP に対応していない AI ツール (素の ChatGPT Web 等) でも FloatingMacro を操作できるようにする方式。AI に「接続用プロンプト」を貼り付けると、AI 自身が `curl` などで FloatingMacro の HTTP API (`/tools/call`) を直接叩きます。

詳細は [acp.md](./acp.md) を参照してください。

---

## 各方式の使い分け

| 状況 | 推奨方式 |
|---|---|
| 何も考えず最短で繋げたい | **CLI (方式 1)**。本体「CLI 登録」ボタンを押すだけ |
| HTTP で直接繋ぎたい (中間プロセスなし) | **HTTP (方式 2)**。本体「HTTP 登録」ボタンか手動登録 |
| MCP 非対応の AI (素の ChatGPT 等) を使いたい | **ACP (方式 3)**。接続用プロンプトを AI に貼付け |

迷ったら方式 1 です。本体の AI 連携ウィンドウを開いて該当クライアントの「CLI 登録」ボタンを押すだけ。

---

## 前提条件

1. **macOS 13 Ventura 以降**
2. **FloatingMacro 本体が起動していること**。どの方式でも本体が動いていなければ何もできません。
3. **Node.js 18 以上が PATH 上にあること** (CLI 接続を使う場合のみ)。Claude Code / Cursor / Gemini CLI などの AI コーディングツールが既に動いている環境ならほぼ確実に入っています。確認:
    ```
    node --version
    ```
4. **本体起動の確認**:
    ```
    curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:17430/ping
    ```
   200 が返れば本体は生きています。

---

## CLI 版 (Node.js 製 MCP server) について

CLI 接続で使う Node.js 製 MCP server は、**FloatingMacro 本体のアプリバンドル内に同梱されています**。場所:

```
/Applications/FloatingMacro.app/Contents/Resources/npm
```

(開発ビルドの場合は `<repo>/build/FloatingMacro.app/Contents/Resources/npm` にあります。)

ユーザーが別途 `npm install` する必要はありません。本体ボタン経由の登録なら、このパスを `npx -y file:<上記>` という形で参照する設定が自動で書き込まれます。

### 動作テスト (任意)

本体起動中に、ターミナルで:

```
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ping","arguments":{}}}' \
  | npx -y file:/Applications/FloatingMacro.app/Contents/Resources/npm \
        --token "$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)"
```

3 行の JSON レスポンスが返れば、CLI 版が正常に動作しています。

---

## 認証用の合言葉について

FloatingMacro は外部からの命令を受ける時に、毎回パスワードのような文字列 (Bearer トークン、64 文字の英数字) を要求します。これは初回起動時に本体が自動生成して macOS Keychain に保存します。あなたが何かを設定する必要はありません。

- **方式 1 (CLI)**: 本体「CLI 登録」ボタンを使えば、ボタンが Keychain から取り出して設定ファイルに書き込みます。CLI 版自身は Keychain にアクセスしません (Keychain ダイアログは出ません)。
- **方式 2 (HTTP)**: 本体「HTTP 登録」ボタンを使えば、ボタンが Keychain から取り出して設定ファイルに書き込みます。
- **方式 3 (ACP)**: 本体「接続用プロンプトをコピー」ボタンが合言葉込みのプロンプトを作ります。

手動登録の場合のみ、以下のコマンドで合言葉を取り出して、設定ファイルに自分で貼り付ける必要があります:

```
security find-generic-password -s FloatingMacro -a ControlAPIToken -w
```

---

## CLI 版と HTTP 版の共存

両方を同じクライアントに同時に登録できます。本体ボタンは別名で書き込みます:

- HTTP 版の登録名: `floatingmacro`
- CLI 版の登録名: `floatingmacro-stdio`

別名なので衝突しません。

> **登録名にアンダースコアを使わない**: Gemini CLI は `mcp_<serverName>_<toolName>` 形式でツール名を分解するため、`floatingmacro_stdio` のような名前は誤解析されます。`floatingmacro-stdio` のようにハイフン (`-`) を使ってください。

---

## トラブルシューティング (共通)

### 本体に到達できない (`FloatingMacro app not reachable`)
本体が起動していない、もしくはポート違い。`curl http://127.0.0.1:17430/ping` で確認。

### 認証エラー (`HTTP 401`)
合言葉が一致しない。本体「CLI 登録」または「HTTP 登録」ボタンを押し直してください。

### `npx: command not found` (CLI 版を使うとき)
Node.js が PATH 上にない。`node --version` でインストール状態を確認。インストール方法は https://nodejs.org/ 。

### `command not found` などが AI クライアント側で出る
本体ボタンは `/bin/zsh -lc "exec npx ..."` の形でログインシェル経由起動するため、`~/.zshrc` で PATH が組み立てられる前提。シェルの設定で npx が PATH に出ないと失敗します。確認:
```
/bin/zsh -lc 'command -v npx'
```
出てこなければ `~/.zshrc` の PATH 設定を見直してください。

### tools/list は通るが呼び出すと無反応
本体側のログ:
```
curl -s "http://127.0.0.1:17430/log/tail?limit=30" \
  -H "Authorization: Bearer $(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)"
```
