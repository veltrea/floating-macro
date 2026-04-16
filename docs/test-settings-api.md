# Settings Test API — 自動テスト実行手順

## この書類について

**このドキュメントはテスト自動実行エージェント向けです。**
テストに必要な情報はこのドキュメントに全て記載されています。
**ソースコードを読む必要はありません。curl と jq だけでテストできます。**

---

## 重要: 環境情報

| 項目 | 値 |
|---|---|
| API サーバーアドレス | `127.0.0.1` |
| デフォルトポート | `17430`（config.json の `controlAPI.port` で変更可能） |
| 実際のポート取得 | 下記「ポート確認コマンド」を使うこと |
| config.json パス | `~/Library/Application Support/FloatingMacro/config.json` |
| ビルドコマンド | `swift build -c debug` |
| 起動コマンド（バイナリ直接） | `.build/debug/FloatingMacro &` |
| 起動コマンド（GUI付き） | `open build/FloatingMacro.app` |
| 作業ディレクトリ | `/Volumes/2TB_USB/dev/floatingmacro` |

### ポート確認コマンド（テスト開始前に必ず実行）

```bash
# config.json から設定ポートを読む
PORT=$(python3 -c "
import json, os
path = os.path.expanduser('~/Library/Application Support/FloatingMacro/config.json')
c = json.load(open(path))
print(c.get('controlAPI', {}).get('port', 17430))
")
echo "Configured port: $PORT"

# 実際にリッスン中のポートを確認（起動済みの場合）
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep FloatingMacro
```

以降のコマンドで `17430` と書かれている箇所は、上記で確認した実際のポートに読み替えること。

---

## ステップ 0: アプリと API サーバーを確認・起動する

### 0-1. API が応答するかまず確認

```bash
curl -s --max-time 2 http://127.0.0.1:17430/ping
```

**応答があれば**: ステップ 1 へ進む

**応答がなければ (Connection refused / タイムアウト)**: 下記の 0-2 を実行

---

### 0-2. API が無効になっている場合: config.json を更新する

`enabled: false` がデフォルトのため、API サーバーは初期状態では起動しない。
以下のコマンドで有効化する:

```bash
# config.json の controlAPI.enabled を true にする
CONFIG="$HOME/Library/Application Support/FloatingMacro/config.json"
cat "$CONFIG" | python3 -c "
import sys, json
c = json.load(sys.stdin)
c.setdefault('controlAPI', {})['enabled'] = True
print(json.dumps(c, ensure_ascii=False, indent=2))
" > /tmp/fm-config-new.json && mv /tmp/fm-config-new.json "$CONFIG"

echo "Updated config:"
cat "$CONFIG" | python3 -m json.tool
```

---

### 0-3. アプリを (再) 起動する

```bash
cd /Volumes/2TB_USB/dev/floatingmacro

# 既存プロセスを止める
pkill -x FloatingMacro 2>/dev/null; sleep 1

# ビルド（変更があれば再コンパイルされる）
swift build -c debug 2>&1 | grep -E "error:|Build complete"

# バイナリを直接バックグラウンド起動（API テストにはこれで十分）
.build/debug/FloatingMacro &
# Note: GUI 付きで起動したい場合は代わりに `open build/FloatingMacro.app` を使う

# 起動完了をポーリングで待つ（最大 15 秒）
for i in $(seq 1 15); do
  sleep 1
  result=$(curl -s --max-time 1 http://127.0.0.1:17430/ping 2>/dev/null)
  if echo "$result" | grep -q '"ok":true'; then
    echo "✓ API ready (${i}秒)"
    break
  fi
  echo "  waiting... ($i/15)"
done
```

---

### 0-4. 起動確認

```bash
curl -s --max-time 3 http://127.0.0.1:17430/ping
```

**期待値**:
```json
{"ok": true, "product": "FloatingMacro"}
```

もし 17430 で応答しない場合はポートが +1 ずれている可能性がある:

```bash
# 実際のポートを調べる
lsof -nP -iTCP -sTCP:LISTEN | grep FloatingMacro
# または 17430〜17439 を順に試す
for p in $(seq 17430 17439); do
  result=$(curl -s --max-time 0.5 http://127.0.0.1:$p/ping)
  [ -n "$result" ] && echo "Port: $p  $result" && break
done
```

以降のコマンドではポート `17430` を使用。実際のポートに読み替えること。

---

### 0-5. ウィンドウを重ならないよう配置する

テストを目視確認する場合は、最初にウィンドウを自動タイリングしておくこと。

```bash
# Settings ウィンドウを開きつつ、フローティングパネルと重ならないよう配置
curl -s -X POST http://127.0.0.1:17430/arrange \
  -H "Content-Type: application/json" \
  -d '{"open_settings": true}' | python3 -m json.tool
```

**期待値**:
```json
{
    "panel":    {"x": ..., "y": ...},
    "screen":   {"width": ..., "height": ...},
    "settings": {"x": ..., "y": ...}
}
```

**レイアウト**: 画面幅に応じて自動選択される
- 十分な横幅がある場合: Settings 左側・パネル右上
- 狭い場合: Settings 左下・パネル右上（重ならない位置）

Settings ウィンドウだけ移動したい場合:
```bash
curl -s -X POST http://127.0.0.1:17430/settings/move \
  -H "Content-Type: application/json" \
  -d '{"x": 12, "y": 12}'
```

---

## ステップ 1: ビルド検証

```bash
cd /Volumes/2TB_USB/dev/floatingmacro
swift build -c debug 2>&1 | grep -E "^(error:|warning:|Build complete)"
```

**期待値**: `Build complete!` が出力される

---

## ステップ 2: 新規ツールが登録されているか確認

```bash
curl -s http://127.0.0.1:17430/tools \
  | python3 -c "
import sys, json
tools = json.load(sys.stdin).get('tools', [])
names = [t['name'] for t in tools if t['name'].startswith('settings_')]
for n in sorted(names): print(n)
"
```

**期待値** (この 5 つが全て表示される):
```
settings_open_app_icon_picker
settings_open_sf_picker
settings_select_button
settings_select_group
settings_set_action_type
```

---

## ステップ 3: 各エンドポイント動作確認

### 3-1. Settings ウィンドウを開く

```bash
curl -s -X POST http://127.0.0.1:17430/settings/open
```

**期待値**: `{"visible":true}`

---

### 3-2. ボタンを選択する (`settings_select_button`)

```bash
# アクティブプリセットから最初のボタン ID を取得
BUTTON_ID=$(curl -s http://127.0.0.1:17430/preset/current \
  | python3 -c "import sys,json; p=json.load(sys.stdin)['preset']; print(p['groups'][0]['buttons'][0]['id'])" \
  2>/dev/null)

if [ -z "$BUTTON_ID" ]; then
  echo "ERROR: ボタンが存在しない。先に button_add でボタンを作成すること"
  echo "例: curl -X POST http://127.0.0.1:17430/button/add -H 'Content-Type: application/json' \\"
  echo "  -d '{\"groupId\":\"g1\", \"button\":{\"id\":\"b1\",\"label\":\"Test\",\"action\":{\"type\":\"key\",\"combo\":\"cmd+c\"}}}'"
else
  echo "ボタン ID: $BUTTON_ID"
  curl -s -X POST http://127.0.0.1:17430/settings/select-button \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"$BUTTON_ID\"}"
fi
```

**期待値**: `{"id":"<button-id>"}`  
**UI 確認**: Settings の左ペインでボタンが選択状態、右ペインに ButtonEditor が表示される

---

### 3-3. グループを選択する (`settings_select_group`)

```bash
GROUP_ID=$(curl -s http://127.0.0.1:17430/preset/current \
  | python3 -c "import sys,json; p=json.load(sys.stdin)['preset']; print(p['groups'][0]['id'])" \
  2>/dev/null)

echo "グループ ID: $GROUP_ID"
curl -s -X POST http://127.0.0.1:17430/settings/select-group \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"$GROUP_ID\"}"
```

**期待値**: `{"id":"<group-id>"}`  
**UI 確認**: Settings の右ペインに GroupEditor（グループ名・背景色・ツールチップ等）が表示される

---

### 3-4. アプリアイコンピッカーを開く (`settings_open_app_icon_picker`)

```bash
# 事前にボタンを選択した状態で実行すること（ButtonEditor が表示されている必要がある）
curl -s -X POST http://127.0.0.1:17430/settings/open-app-icon-picker
```

**期待値**: `{"opened":true}`  
**UI 確認**: 「アプリ...」ボタンを押したのと同じアプリアイコン一覧シートが表示される

---

### 3-5. エディタ選択を解除する (`settings_clear_selection`)

```bash
# select-button / select-group の後に呼ぶと右ペインが空になる
curl -s -X POST http://127.0.0.1:17430/settings/clear-selection
```

**期待値**: `{"cleared":true}`  
**UI 確認**: Settings 右ペインの ButtonEditor / GroupEditor が閉じて空になる

---

### 3-6. ピッカーを閉じる (`settings_dismiss_picker`)

```bash
# open-app-icon-picker または open-sf-picker の後に呼ぶ
curl -s -X POST http://127.0.0.1:17430/settings/dismiss-picker
```

**期待値**: `{"dismissed":true}`  
**UI 確認**: 開いているピッカーシートが閉じる（アプリアイコン・SF Symbol どちらも対応）

---

### 3-6. アクションタイプを切り替える (`settings_set_action_type`)

```bash
# 事前にボタンを選択した状態で実行すること（ButtonEditor が表示されている必要がある）
for TYPE in text key launch terminal; do
  echo -n "Setting action type '$TYPE': "
  curl -s -X POST http://127.0.0.1:17430/settings/set-action-type \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"$TYPE\"}"
  sleep 0.3
done
```

**期待値** (各行):
```
Setting action type 'text': {"type":"text"}
Setting action type 'key': {"type":"key"}
Setting action type 'launch': {"type":"launch"}
Setting action type 'terminal': {"type":"terminal"}
```

**UI 確認**: `text|key|launch|terminal` セグメントが切り替わる

---

## ステップ 4: エラーケース確認

```bash
echo "=== 4-1: 不正な type 値 ==="
curl -s -X POST http://127.0.0.1:17430/settings/set-action-type \
  -H "Content-Type: application/json" \
  -d '{"type":"invalid"}'
# 期待値: {"error": "...must be one of..."} と HTTP 400

echo ""
echo "=== 4-2: 必須フィールド省略 ==="
curl -s -w " HTTP_%{http_code}" \
  -X POST http://127.0.0.1:17430/settings/select-button \
  -H "Content-Type: application/json" \
  -d '{}'
# 期待値: {"error": "..."} HTTP_400

echo ""
echo "=== 4-3: 存在しない ID（エラーにはならないが UI 変化なし）==="
curl -s -X POST http://127.0.0.1:17430/settings/select-button \
  -H "Content-Type: application/json" \
  -d '{"id":"nonexistent-9999"}'
# 期待値: {"id":"nonexistent-9999"} （200 OK, ただし Settings 右ペインは空）
```

---

## ステップ 5: フルシーケンス一発実行スクリプト

```bash
#!/bin/bash
set -euo pipefail

# ポートを config.json から動的に取得
PORT=$(python3 -c "
import json, os
path = os.path.expanduser('~/Library/Application Support/FloatingMacro/config.json')
c = json.load(open(path))
print(c.get('controlAPI', {}).get('port', 17430))
" 2>/dev/null || echo "17430")
BASE="http://127.0.0.1:${PORT}"
echo "Using port: $PORT"
PASS=0; FAIL=0

check() {
  local desc="$1"; local cmd="$2"; local expected="$3"
  result=$(eval "$cmd" 2>/dev/null)
  if echo "$result" | grep -q "$expected"; then
    echo "  ✓ $desc"
    ((PASS++)) || true
  else
    echo "  ✗ $desc"
    echo "    期待: $expected"
    echo "    実際: $result"
    ((FAIL++)) || true
  fi
}

echo "=== ウィンドウ配置 ==="
check "arrange (open_settings)" \
  "curl -s -X POST $BASE/arrange -H 'Content-Type: application/json' -d '{\"open_settings\":true}'" \
  '"settings"'

echo ""
echo "=== 疎通確認 ==="
check "ping" "curl -s --max-time 2 $BASE/ping" '"ok":true'

echo ""
echo "=== ツール登録確認 ==="
for TOOL in settings_select_button settings_select_group settings_open_app_icon_picker settings_dismiss_picker settings_clear_selection settings_set_action_type; do
  check "$TOOL が登録済み" \
    "curl -s $BASE/tools | python3 -c \"import sys,json; names=[t['name'] for t in json.load(sys.stdin)['tools']]; print('found' if '$TOOL' in names else 'missing')\"" \
    "found"
done

echo ""
echo "=== エンドポイント確認 ==="
check "settings/open" \
  "curl -s -X POST $BASE/settings/open" '"visible":true'

# ボタン ID を取得
BTN=$(curl -s "$BASE/preset/current" | python3 -c "import sys,json; p=json.load(sys.stdin)['preset']; print(p['groups'][0]['buttons'][0]['id'])" 2>/dev/null || echo "")
GRP=$(curl -s "$BASE/preset/current" | python3 -c "import sys,json; p=json.load(sys.stdin)['preset']; print(p['groups'][0]['id'])" 2>/dev/null || echo "")

if [ -z "$BTN" ]; then
  echo "  ⚠ ボタンが見つからない — select-button / set-action-type テストをスキップ"
else
  check "settings/select-button" \
    "curl -s -X POST $BASE/settings/select-button -H 'Content-Type: application/json' -d '{\"id\":\"$BTN\"}'" \
    "\"id\""
  check "settings/set-action-type text" \
    "curl -s -X POST $BASE/settings/set-action-type -H 'Content-Type: application/json' -d '{\"type\":\"text\"}'" \
    '"type":"text"'
  check "settings/set-action-type key" \
    "curl -s -X POST $BASE/settings/set-action-type -H 'Content-Type: application/json' -d '{\"type\":\"key\"}'" \
    '"type":"key"'
fi

if [ -z "$GRP" ]; then
  echo "  ⚠ グループが見つからない — select-group テストをスキップ"
else
  check "settings/select-group" \
    "curl -s -X POST $BASE/settings/select-group -H 'Content-Type: application/json' -d '{\"id\":\"$GRP\"}'" \
    "\"id\""
fi

check "settings/open-app-icon-picker" \
  "curl -s -X POST $BASE/settings/open-app-icon-picker" '"opened":true'
check "settings/dismiss-picker" \
  "curl -s -X POST $BASE/settings/dismiss-picker" '"dismissed":true'
check "settings/clear-selection" \
  "curl -s -X POST $BASE/settings/clear-selection" '"cleared":true'

echo ""
echo "=== エラーハンドリング ==="
check "invalid type は 400" \
  "curl -s -w ' HTTP_%{http_code}' -X POST $BASE/settings/set-action-type -H 'Content-Type: application/json' -d '{\"type\":\"bad\"}'" \
  "HTTP_400"
check "missing id は 400" \
  "curl -s -w ' HTTP_%{http_code}' -X POST $BASE/settings/select-button -H 'Content-Type: application/json' -d '{}'" \
  "HTTP_400"

echo ""
echo "===== 結果: $PASS 成功 / $FAIL 失敗 ====="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

保存して実行:
```bash
chmod +x docs/test-settings-api.sh
bash docs/test-settings-api.sh
```

---

## 注意事項

- `set-action-type` と `open-app-icon-picker` は ButtonEditor が画面に表示されている状態でのみ有効。`select-button` の後に呼ぶこと。
- ピッカーを開いた後は `dismiss-picker` で閉じること（アプリアイコン・SF Symbol ピッカー両方に対応）。
- `externalActionTypeRequest` は `onChange` で消費されて `nil` に戻る。ButtonEditor が表示されていない場合、次回表示時に反映されない（消費されてしまう）。
