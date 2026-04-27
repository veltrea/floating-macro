# FloatingMacro MCP 統合 — テスト手順書

このドキュメントは、新セッションで FloatingMacro の MCP 統合 (CLI / HTTP / ACP) を実機検証するための手順書です。**前提知識ゼロから自己完結**で進められるよう書かれています。

> **HANDOVER.md ではない**: 引き継ぎは [HANDOVER.md](./HANDOVER.md) を参照。本ファイルはテスト実行の手順だけに絞っています。

---

## 0. テストの目的

`/Applications/FloatingMacro.app` (本体) の AI 連携ウィンドウから各 AI クライアントへ MCP を登録するボタンが、想定通りに動くか、ユーザー目線で確認する。

具体的に検証する 3 系統:

| 系統 | 対象 |
|---|---|
| CLI 接続 | npm パッケージ (`Contents/Resources/npm/`) を `/bin/zsh -lc 'exec npx -y file:... --token ...'` で起動 |
| HTTP 接続 | 本体 `/mcp` エンドポイントに直接 HTTP でつなぐ |
| ACP 接続 | 接続用プロンプトを AI に貼り付けて curl 経由で操作 |

確認対象クライアント (5 つ):

- Claude Code (CLI で確認可能)
- Claude Desktop (UI 確認、ボタン未提供のため手動登録のみ)
- Cursor (UI 確認)
- Gemini CLI (CLI で確認可能)
- VS Code Copilot (UI 確認)
- Windsurf (UI 確認)

---

## 1. 環境準備

新セッションでは、まず以下を順番にチェックします。

### 1.1 リポジトリの場所を確認

```bash
cd /Volumes/2TB_USB/dev/floatingmacro
ls -la docs/mcp/
```

`TEST_PLAN.md` (このファイル) と `HANDOVER.md` が見えれば OK。

### 1.2 アプリのインストール状況確認

```bash
ls -la /Applications/FloatingMacro.app/Contents/Resources/npm/bin/floatingmacro-mcp.mjs
```

存在すれば配布形態でインストール済み。存在しなければ:

```bash
INSTALL=1 bash scripts/build-app.sh
```

### 1.3 本体起動状態確認

```bash
curl -s -o /dev/null -w "ping=%{http_code}\n" http://127.0.0.1:17430/ping
```

`ping=200` が出れば OK。出なければ:

```bash
open /Applications/FloatingMacro.app
sleep 3
curl -s -o /dev/null -w "ping=%{http_code}\n" http://127.0.0.1:17430/ping
```

### 1.4 認証用合言葉が取れるか確認

```bash
security find-generic-password -s FloatingMacro -a ControlAPIToken -w
```

64 文字の英数字が表示されれば OK。出なければ本体を再起動。

### 1.5 Node.js が PATH 上にあるか確認

```bash
/bin/zsh -lc 'command -v npx && node --version'
```

`/Users/.../bin/npx` 系のパスと `v18.x` 以上のバージョンが出れば OK。

---

## 2. ベースライン (素の動作テスト)

各クライアントを触る前に、npm パッケージそのものが動くか単独で確認します。

### 2.1 CLI 版の素のテスト

```bash
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
BUNDLE=/Applications/FloatingMacro.app/Contents/Resources/npm
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ping","arguments":{}}}' \
  | /bin/zsh -lc "exec npx -y 'file:$BUNDLE' --token '$TOKEN'"
```

**期待結果**: 3 行の JSON。
- 1 行目: `protocolVersion: "2024-11-05"` を含む initialize 応答
- 2 行目: `tools` 配列に 46 個 (`run_action` の inputSchema が `type: "object"` を持つ)
- 3 行目: `{"ok":true,"product":"FloatingMacro"}` を含む ping 結果

### 2.2 HTTP 版の素のテスト

```bash
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"ping","arguments":{}}'
```

**期待結果**: `{"name":"ping","result":{"ok":true,"product":"FloatingMacro"},"status":200}`

### 2.3 ACP 版の素のテスト (manifest discovery)

```bash
curl -s http://127.0.0.1:17430/manifest | python3 -c "
import json, sys
m = json.load(sys.stdin)
print(f'tools: {len(m[\"tools\"])}, server: {m[\"serverInfo\"]}')
"
```

**期待結果**: `tools: 46, server: {'name': 'FloatingMacro', 'version': '0.1'}`

ベースラインが通らなければ、以降のクライアント別テストは無意味なので先にこの 3 つを揃えてください。

---

## 3. 本体「CLI 登録」「HTTP 登録」ボタンの動作確認

本体の AI 連携ウィンドウからボタンを押した時に、設定ファイルが正しく書き換わるかを検証します。

### 3.1 AI 連携ウィンドウを開く

HTTP API 経由で開くのが確実 (computer-use を介さない):

```bash
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"ai_integration_open","arguments":{}}'
```

**期待結果**: `{"name":"ai_integration_open","result":{"visible":true},"status":200}`

加えて、画面に「FloatingMacro AI 連携」ウィンドウが現れる。

### 3.2 ボタン押下前の状態スナップショット

```bash
for f in \
  "$HOME/.claude.json" \
  "$HOME/.cursor/mcp.json" \
  "$HOME/.gemini/settings.json" \
  "$HOME/Library/Application Support/Code/User/mcp.json" \
  "$HOME/.codeium/windsurf/mcp_config.json"
do
  echo "--- $f ---"
  if [ -f "$f" ]; then
    python3 -c "
import json
with open('$f') as fp:
    d = json.load(fp)
keys = list(d.get('mcpServers', {}).keys()) + list(d.get('servers', {}).keys())
print('  servers:', keys)
"
  else
    echo "  (file not found)"
  fi
done
```

書き込み前後の差分が見えるよう、ボタンを押す前にこのスナップショットを取っておく。

### 3.3 各クライアントの「CLI 登録」「HTTP 登録」ボタンを押す

ユーザー操作: 開いた AI 連携ウィンドウで、各行 (Claude Code / Cursor / Gemini CLI / VS Code / Windsurf) の **「CLI 登録」(青)** と **「HTTP 登録」(白枠)** をそれぞれ押す。各ボタンを押すたびに緑の確認メッセージが表示される。

### 3.4 ボタン押下後の状態確認

書き込まれた内容が想定通りか確認:

```bash
python3 <<'PY'
import json, os
TARGETS = [
    ("Claude Code",  "~/.claude.json",                                      "mcpServers"),
    ("Cursor",       "~/.cursor/mcp.json",                                  "mcpServers"),
    ("Gemini CLI",   "~/.gemini/settings.json",                             "mcpServers"),
    ("VS Code",      "~/Library/Application Support/Code/User/mcp.json",   "servers"),
    ("Windsurf",     "~/.codeium/windsurf/mcp_config.json",                "mcpServers"),
]
for name, p, key in TARGETS:
    path = os.path.expanduser(p)
    if not os.path.exists(path):
        print(f"[NG] {name}: file missing")
        continue
    try:
        d = json.load(open(path))
    except Exception as e:
        print(f"[NG] {name}: JSON parse error {e}")
        continue
    section = d.get(key, {})
    cli = section.get("floatingmacro-stdio")
    http = section.get("floatingmacro")
    print(f"{name}:")
    if cli:
        cmd = cli.get("command")
        args0 = (cli.get("args") or [None])[0]
        print(f"  CLI:  command={cmd}, args[0]={args0}, type={cli.get('type','-')}")
    else:
        print(f"  CLI:  (not registered)")
    if http:
        url = http.get("url") or http.get("httpUrl") or http.get("serverUrl")
        print(f"  HTTP: url={url}, type={http.get('type','-')}")
    else:
        print(f"  HTTP: (not registered)")
PY
```

**期待結果**:
- 全 5 クライアントの CLI 行: `command=/bin/zsh, args[0]=-lc, type=stdio (VS Code のみ)`
- 全 5 クライアント の HTTP 行: `url=http://127.0.0.1:17430/mcp, type=http (Claude Code/VS Code のみ)`

### 3.5 既存の他の MCP サーバーが壊れていないか

スナップショット (3.2) と比べて、`floatingmacro` / `floatingmacro-stdio` 以外のキーが消えたり中身が変わったりしていないか確認。

---

## 4. 各クライアント別の実機検証

### 4.1 Claude Code (CLI 確認可能)

```bash
claude mcp list 2>&1 | grep floatingmacro
```

**期待結果**:
```
floatingmacro: http://127.0.0.1:17430/mcp (HTTP) - ✓ Connected
floatingmacro-stdio: /bin/zsh -lc exec npx -y ... - ✓ Connected
```

両方が `Connected` であること。`Failed to connect` が出る場合はトラブルシューティングへ。

実セッションでテスト:
```bash
# Claude Code を起動して以下を依頼
# 「floatingmacro のマニフェストを見せて」
# 期待: mcp__floatingmacro__manifest または mcp__floatingmacro-stdio__manifest が呼ばれて 46 ツールが返る
```

### 4.2 Gemini CLI (CLI 確認可能)

```bash
gemini --help 2>&1 | head -3   # Gemini CLI が PATH 上にあるか確認
```

ターミナルから `gemini` を起動 → セッション内で:

```
/mcp list
```

**期待結果**: `floatingmacro-stdio: connected` (CLI 版)、 `floatingmacro: connected` (HTTP 版) が表示。

実セッションでテスト:
```
floatingmacro のプリセットを見せて
```

`mcp_floatingmacro-stdio_preset_current` または `mcp_floatingmacro_preset_current` が呼ばれて結果が返る。

### 4.3 Cursor (UI 確認)

ユーザー操作:

1. Cursor を **完全終了** (`⌘+Q`) して再起動
2. `Settings → MCP Servers` を開く
3. `floatingmacro-stdio` と `floatingmacro` が表示されているか確認
4. 両方の左に **緑のドット** が点いているか確認 (赤や黄色の場合は失敗)
5. AI チャット欄で「floatingmacro のプリセットを見せて」と依頼
6. ツールが呼ばれて結果が返れば成功

ログ確認 (失敗時): `Help → Toggle Developer Tools → Console`

### 4.4 VS Code Copilot (UI 確認)

ユーザー操作:

1. VS Code を完全終了 → 再起動
2. Copilot Chat を開く
3. 入力欄左上の工具アイコン (ツールピッカー) を開く
4. `floatingmacro` / `floatingmacro-stdio` が一覧に出ているか確認
5. チャットで「floatingmacro のパネルの透明度を 80% にして」と依頼

ログ確認 (失敗時): `Help → Show Logs → Window`

### 4.5 Windsurf (UI 確認)

ユーザー操作:

1. Windsurf を完全終了 → 再起動
2. Cascade のサイドバー内 MCP セクションを開く
3. `floatingmacro-stdio` と `floatingmacro` が出ているか確認
4. Cascade のチャットで「floatingmacro のボタンを並べ替えて」と依頼

### 4.6 Claude Desktop (UI 確認、本体ボタン未提供)

Claude Desktop は本体ボタンによる登録ボタンが未提供のため、手動登録のテストになります。

設定ファイル: `~/Library/Application Support/Claude/claude_desktop_config.json`

[`docs/mcp/claude-desktop.md`](./claude-desktop.md) の手順で `floatingmacro-stdio` を手動登録 → 完全終了 → 再起動 → 入力欄左下の「ツール」アイコンから `floatingmacro-stdio` のツール一覧が見えるか確認。

---

## 5. 実機での操作テスト (回帰確認)

接続が確認できたクライアントのうち 1 つで、実際に副作用を伴うツールを呼んでみる。これでツールがちゃんと本体に届いて画面が変わることを確認。

### 5.1 パネルの透明度を変える

任意の AI クライアントで:

```
floatingmacro のパネルの透明度を 0.5 にして
```

**期待結果**: 画面に出ている FloatingMacro のフローティングパネルが半透明になる。

戻す:

```
floatingmacro のパネルの透明度を 1.0 にして
```

### 5.2 テスト用ボタンを 1 個追加 → 削除

```
floatingmacro に "test-tmp" という id でラベル "🧪" のボタンを追加して、追加したらすぐ削除して
```

**期待結果**: パネルにボタンが一瞬出て消える (ログから確認可能)。

### 5.3 ログ確認

```bash
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
curl -s "http://127.0.0.1:17430/log/tail?limit=20" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -m json.tool | tail -40
```

直前の操作 (透明度変更、ボタン追加/削除) のログが見えれば成功。

---

## 6. ACP (curl・プロンプト貼付け) 検証

### 6.1 接続用プロンプトをコピー

AI 連携ウィンドウの「プロンプトをコピー」ボタンを押す。または HTTP API:

```bash
# ボタン経由が簡単。手動なら以下を構成:
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
echo "接続先: http://127.0.0.1:17430"
echo "認証トークン: $TOKEN"
```

### 6.2 任意の AI (素の Claude / ChatGPT 等) に貼り付ける

期待結果: AI が `curl http://127.0.0.1:17430/manifest | jq` を実行 → 自己紹介を読み込む → `/tools/call` 経由で操作可能になる。

### 6.3 直接 curl でツールを呼ぶ

```bash
TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w)
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"window_opacity","arguments":{"value":0.7}}'
sleep 1
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"window_opacity","arguments":{"value":1.0}}'
```

**期待結果**: パネルが一瞬 70% 透明になって元に戻る。

---

## 7. 完了チェックリスト

すべて ✓ になればテスト合格。

- [ ] 1.x 環境準備すべて OK (本体起動、Keychain トークン、Node.js)
- [ ] 2.1 CLI 版 素のテスト OK (46 ツール、ping ok:true)
- [ ] 2.2 HTTP 版 素のテスト OK (curl /tools/call で ping ok:true)
- [ ] 2.3 ACP /manifest 取得 OK (46 ツール表示)
- [ ] 3.1 AI 連携ウィンドウ開く OK
- [ ] 3.4 ボタン押下後、5 クライアント全部に CLI/HTTP エントリが書き込まれる
- [ ] 3.5 既存の他 MCP サーバー設定が壊れていない
- [ ] 4.1 Claude Code: `claude mcp list` で両 ✓ Connected
- [ ] 4.2 Gemini CLI: `/mcp list` で両 connected
- [ ] 4.3 Cursor: Settings → MCP Servers で両 緑ドット
- [ ] 4.4 VS Code: Copilot Chat ツールピッカーで両表示
- [ ] 4.5 Windsurf: Cascade MCP で両表示
- [ ] 4.6 Claude Desktop: 手動登録で stdio 版表示 (CLI 版のみ)
- [ ] 5.1 透明度変更 OK (画面で確認)
- [ ] 5.2 テストボタン追加/削除 OK
- [ ] 5.3 ログに操作の記録あり
- [ ] 6.1-6.3 ACP curl 直叩き OK

---

## 8. トラブルシューティング

### `ping=000` (本体応答なし)
本体が起動していない、もしくは別ポート使用中。
```bash
lsof -i :17430
open /Applications/FloatingMacro.app
sleep 3
curl http://127.0.0.1:17430/ping
```

### `npx: command not found`
Node.js が PATH 上にない。
```bash
/bin/zsh -lc 'command -v npx'
# 出ない場合: ~/.zshrc を見直し、Node.js を入れ直し
```

### `tool xxx failed: HTTP 401`
合言葉が一致していない。設定ファイルのトークンを取り直し。本体ボタンを押し直すのが最も簡単。

### Claude Code で `Connection closed`
- fmcli (Swift 版) が残っている可能性。ToDo: `~/.local/bin/fmcli` を削除
- npm パッケージのバージョンが古い可能性。`bash scripts/build-app.sh` で再ビルド

### Cursor / VS Code / Windsurf で接続失敗
1. アプリを完全終了 (`⌘+Q`) してから再起動 (Reload Window だけでは不十分)
2. JSON 構文を確認:
   ```bash
   python3 -m json.tool ~/.cursor/mcp.json
   python3 -m json.tool "$HOME/Library/Application Support/Code/User/mcp.json"
   python3 -m json.tool ~/.codeium/windsurf/mcp_config.json
   ```
3. 各アプリの開発者ログで `Failed to start MCP server` を検索

### tools/list で 46 個出るが Gemini CLI が拒否
`run_action` ツールの inputSchema が `type: "object"` を持っているか確認:
```bash
curl -s http://127.0.0.1:17430/manifest | python3 -c "
import json, sys
m = json.load(sys.stdin)
ra = next(t for t in m['tools'] if t['name'] == 'run_action')
print('run_action inputSchema keys:', list(ra['inputSchema'].keys()))
print('  type:', ra['inputSchema'].get('type'))
"
```
`type: object` が無ければ `Sources/FloatingMacroCore/ControlAPI/ToolCatalog.swift` の `actionSchema()` を確認。

---

## 9. テスト後のクリーンアップ (任意)

テスト中に追加した登録を削除したい場合:

```bash
# Claude Code から削除
claude mcp remove floatingmacro-stdio
claude mcp remove floatingmacro

# Gemini CLI から削除
gemini mcp remove floatingmacro-stdio
gemini mcp remove floatingmacro

# Cursor / VS Code / Windsurf は設定ファイルから手動削除
```

または python で全クライアントから一気に消す:

```bash
python3 <<'PY'
import json, os
TARGETS = [
    ("~/.claude.json",                                       "mcpServers"),
    ("~/.cursor/mcp.json",                                   "mcpServers"),
    ("~/.gemini/settings.json",                              "mcpServers"),
    ("~/Library/Application Support/Code/User/mcp.json",    "servers"),
    ("~/.codeium/windsurf/mcp_config.json",                 "mcpServers"),
]
for p, key in TARGETS:
    path = os.path.expanduser(p)
    if not os.path.exists(path): continue
    d = json.load(open(path))
    section = d.get(key, {})
    section.pop("floatingmacro-stdio", None)
    section.pop("floatingmacro", None)
    json.dump(d, open(path, "w"), indent=2, ensure_ascii=False)
    print(f"cleaned: {path}")
PY
```

---

## 10. 関連ファイル

| ファイル | 役割 |
|---|---|
| [setup.md](./setup.md) | 共通ガイド (3 系統の接続方式) |
| [claude-code.md](./claude-code.md) | Claude Code 別マニュアル |
| [claude-desktop.md](./claude-desktop.md) | Claude Desktop 別マニュアル |
| [cursor.md](./cursor.md) | Cursor 別マニュアル |
| [gemini-cli.md](./gemini-cli.md) | Gemini CLI 別マニュアル |
| [acp.md](./acp.md) | ACP 接続マニュアル (curl・プロンプト貼付け) |
| [HANDOVER.md](./HANDOVER.md) | 引き継ぎ概要 |
| [REPORT_GEMINI_MCP.ja.md](./REPORT_GEMINI_MCP.ja.md) | Gemini CLI 検証時の技術レポート |
