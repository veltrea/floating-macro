# FloatingMacro Control API — 自動テスト実行手順

## この書類について

**このドキュメントはテスト自動実行エージェント向けです。**
テストに必要な情報はこのドキュメントに全て記載されています。
**ソースコードを読む必要はありません。curl と jq だけでテストできます。**

手動テストのチェックリストは `docs/manual_test.ja.md` を参照してください。
このドキュメントは「AI が自律的にアプリを起動し、API を叩いて合否を判定する」ユースケース向けに書かれています。

---

## 重要: 環境情報

| 項目 | 値 |
|---|---|
| API サーバーアドレス | `127.0.0.1` |
| デフォルトポート | `17430`（衝突時は +1 ずつ最大 17439 まで fallback） |
| config.json パス | `~/Library/Application Support/FloatingMacro/config.json` |
| ビルドコマンド | `swift build -c debug` |
| 作業ディレクトリ | `/Volumes/2TB_USB/dev/floatingmacro` |

---

## ステップ 0: アプリと API サーバーを確認・起動する

### 0-1. API が応答するかまず確認

```bash
curl -s --max-time 2 http://127.0.0.1:17430/ping
```

**応答があれば**: ステップ 1 へ進む

**応答がなければ**: 下記 0-2 → 0-3 を実行

---

### 0-2. Control API を有効化する

`controlAPI.enabled` はデフォルト `false` なので、未設定の場合は以下で有効化する:

```bash
CONFIG="$HOME/Library/Application Support/FloatingMacro/config.json"
python3 -c "
import sys, json, os
path = os.path.expanduser('~/Library/Application Support/FloatingMacro/config.json')
c = json.load(open(path)) if os.path.exists(path) else {}
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

# ビルド
swift build -c debug 2>&1 | grep -E "error:|Build complete"

# バックグラウンド起動
.build/debug/FloatingMacro &

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

ポートが 17430 で応答しない場合は fallback を探す:

```bash
for p in $(seq 17430 17439); do
  result=$(curl -s --max-time 0.5 http://127.0.0.1:$p/ping)
  [ -n "$result" ] && echo "Port: $p  $result" && break
done
```

---

## テスト内容の概要

このスクリプトが検証する内容:

1. **疎通確認** — ping / state / manifest でサーバーが正常起動していることを確認
2. **全ツール登録** — ToolCatalog に定義された全ツールが `/tools` に出ていることを確認
3. **プリセット管理** — create / switch / group_add / button_add / update / reorder / move / delete の一連のサイクル
4. **Settings UI 操作** — select_button → set_action_value / set_background_color / set_text_color / commit → clear_selection の順序依存フロー
5. **グループ編集** — select_group → set_background_color → commit の流れ
6. **ピッカー開閉** — open_app_icon_picker / open_sf_picker → dismiss_picker
7. **キーコンボ設定** — set_key_combo / set_action_type の自動タブ切替
8. **ウィンドウ操作** — opacity / move / resize / hide / toggle / show
9. **アクション直実行** — run_action (text / key) + log_tail でエラーがないことを確認
10. **Settings ウィンドウ管理** — open / move / close
11. **エラーハンドリング** — 不正な入力に対して 400 が返ることを確認
12. **クリーンアップ** — テスト用プリセット (`test-api-script`) を削除して環境を復元

---

## フルシーケンス 一発実行スクリプト

スクリプトはテスト用プリセットを作成し、全操作を順番に実行した後に削除する。
実行前に **アプリが起動済みで API が応答していること** を確認すること（ステップ 0 参照）。

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

# テスト用プリセットを確実に削除する（スクリプトが途中で失敗しても）
cleanup() {
  curl -s -X POST "$BASE/preset/switch" \
    -H 'Content-Type: application/json' -d '{"name":"default"}' > /dev/null 2>&1 || true
  curl -s -X POST "$BASE/preset/delete" \
    -H 'Content-Type: application/json' -d '{"name":"test-api-script"}' > /dev/null 2>&1 || true
}
trap cleanup EXIT

# -------------------------
echo "=== 疎通確認 ==="
check "ping"      "curl -s --max-time 2 $BASE/ping"  '"ok":true'
check "get_state" "curl -s $BASE/state"               '"activePreset"'
check "manifest"  "curl -s $BASE/manifest"            '"tools"'

# -------------------------
echo ""
echo "=== 全ツール登録確認 ==="
ALL_TOOLS=(
  help manifest ping get_state
  window_show window_hide window_toggle window_opacity window_move window_resize
  preset_list preset_current preset_switch preset_reload
  preset_create preset_rename preset_delete
  group_add group_update group_delete
  button_add button_update button_delete button_reorder button_move
  run_action log_tail icon_for_app
  settings_open settings_close settings_open_sf_picker settings_move
  settings_select_button settings_select_group
  settings_open_app_icon_picker settings_dismiss_picker
  settings_clear_selection settings_commit
  settings_set_background_color settings_set_text_color
  settings_set_action_type settings_set_key_combo settings_set_action_value
  arrange
)
for TOOL in "${ALL_TOOLS[@]}"; do
  check "$TOOL 登録済み" \
    "curl -s $BASE/tools | python3 -c \"import sys,json; names=[t['name'] for t in json.load(sys.stdin)['tools']]; print('found' if '$TOOL' in names else 'missing')\"" \
    "found"
done

# -------------------------
echo ""
echo "=== ウィンドウ配置 ==="
check "arrange (open_settings)" \
  "curl -s -X POST $BASE/arrange -H 'Content-Type: application/json' -d '{\"open_settings\":true}'" \
  '"settings"'

# -------------------------
echo ""
echo "=== プリセット管理サイクル ==="
check "preset_list"   "curl -s $BASE/preset/list"    '"presets"'
check "preset_current" "curl -s $BASE/preset/current" '"preset"'

check "preset_create" \
  "curl -s -X POST $BASE/preset/create -H 'Content-Type: application/json' -d '{\"name\":\"test-api-script\",\"displayName\":\"Script Test\"}'" \
  '"ok":true'

check "preset_switch (to test)" \
  "curl -s -X POST $BASE/preset/switch -H 'Content-Type: application/json' -d '{\"name\":\"test-api-script\"}'" \
  '"loaded":true'

check "group_add (main)" \
  "curl -s -X POST $BASE/group/add -H 'Content-Type: application/json' -d '{\"id\":\"g-main\",\"label\":\"Main\"}'" \
  '"ok":true'

check "group_add (sub)" \
  "curl -s -X POST $BASE/group/add -H 'Content-Type: application/json' -d '{\"id\":\"g-sub\",\"label\":\"Sub\",\"collapsed\":true}'" \
  '"ok":true'

check "button_add" \
  "curl -s -X POST $BASE/button/add -H 'Content-Type: application/json' \
    -d '{\"groupId\":\"g-main\",\"button\":{\"id\":\"btn-a\",\"label\":\"A\",\"action\":{\"type\":\"text\",\"content\":\"test\"}}}'" \
  '"ok":true'

# 並び替えテスト用にもう1つ追加
curl -s -X POST "$BASE/button/add" -H 'Content-Type: application/json' \
  -d '{"groupId":"g-main","button":{"id":"btn-b","label":"B","action":{"type":"text","content":"b"}}}' > /dev/null

check "button_reorder" \
  "curl -s -X POST $BASE/button/reorder -H 'Content-Type: application/json' -d '{\"groupId\":\"g-main\",\"ids\":[\"btn-b\",\"btn-a\"]}'" \
  '"ok":true'

check "button_update" \
  "curl -s -X POST $BASE/button/update -H 'Content-Type: application/json' -d '{\"id\":\"btn-a\",\"label\":\"A2\"}'" \
  '"ok":true'

check "button_move" \
  "curl -s -X POST $BASE/button/move -H 'Content-Type: application/json' -d '{\"id\":\"btn-b\",\"toGroupId\":\"g-sub\"}'" \
  '"ok":true'

check "group_update" \
  "curl -s -X POST $BASE/group/update -H 'Content-Type: application/json' -d '{\"id\":\"g-sub\",\"label\":\"Sub v2\",\"collapsed\":false}'" \
  '"ok":true'

check "group_delete (sub)" \
  "curl -s -X POST $BASE/group/delete -H 'Content-Type: application/json' -d '{\"id\":\"g-sub\"}'" \
  '"ok":true'

check "preset_reload" \
  "curl -s -X POST $BASE/preset/reload" \
  '"activePreset"'

check "preset_rename" \
  "curl -s -X POST $BASE/preset/rename -H 'Content-Type: application/json' -d '{\"name\":\"test-api-script\",\"displayName\":\"Script Test v2\"}'" \
  '"ok":true'

check "preset_current (after edits)" \
  "curl -s $BASE/preset/current" '"groups"'

# -------------------------
echo ""
echo "=== Settings UI — ボタン編集フロー ==="
# select → 編集 → commit → clear の順序依存フロー

check "settings/open" \
  "curl -s -X POST $BASE/settings/open" '"visible":true'

check "settings/select-button" \
  "curl -s -X POST $BASE/settings/select-button -H 'Content-Type: application/json' -d '{\"id\":\"btn-a\"}'" \
  '"id":"btn-a"'

check "settings/set-action-type (text)" \
  "curl -s -X POST $BASE/settings/set-action-type -H 'Content-Type: application/json' -d '{\"type\":\"text\"}'" \
  '"type":"text"'

check "settings/set-action-value" \
  "curl -s -X POST $BASE/settings/set-action-value -H 'Content-Type: application/json' -d '{\"type\":\"text\",\"value\":\"hello from script\"}'" \
  '"type":"text"'

check "settings/set-background-color" \
  "curl -s -X POST $BASE/settings/set-background-color -H 'Content-Type: application/json' -d '{\"color\":\"#1A73E8\"}'" \
  '"color":"#1A73E8"'

check "settings/set-text-color" \
  "curl -s -X POST $BASE/settings/set-text-color -H 'Content-Type: application/json' -d '{\"color\":\"#FFFFFF\"}'" \
  '"color":"#FFFFFF"'

check "settings/commit (button)" \
  "curl -s -X POST $BASE/settings/commit" '"committed":true'

check "settings/clear-selection" \
  "curl -s -X POST $BASE/settings/clear-selection" '"cleared":true'

# -------------------------
echo ""
echo "=== Settings UI — グループ編集フロー ==="

check "settings/select-group" \
  "curl -s -X POST $BASE/settings/select-group -H 'Content-Type: application/json' -d '{\"id\":\"g-main\"}'" \
  '"id":"g-main"'

check "settings/set-background-color (group)" \
  "curl -s -X POST $BASE/settings/set-background-color -H 'Content-Type: application/json' -d '{\"color\":\"#34A853\"}'" \
  '"color":"#34A853"'

check "settings/commit (group)" \
  "curl -s -X POST $BASE/settings/commit" '"committed":true'

check "settings/clear-selection (after group)" \
  "curl -s -X POST $BASE/settings/clear-selection" '"cleared":true'

# -------------------------
echo ""
echo "=== Settings UI — ピッカー開閉フロー ==="

check "settings/select-button (for picker)" \
  "curl -s -X POST $BASE/settings/select-button -H 'Content-Type: application/json' -d '{\"id\":\"btn-a\"}'" \
  '"id":"btn-a"'

check "settings/open-app-icon-picker" \
  "curl -s -X POST $BASE/settings/open-app-icon-picker" '"opened":true'

check "settings/dismiss-picker (app icon)" \
  "curl -s -X POST $BASE/settings/dismiss-picker" '"dismissed":true'

check "settings/open-sf-picker" \
  "curl -s -X POST $BASE/settings/open-sf-picker" '"opened":true'

check "settings/dismiss-picker (SF)" \
  "curl -s -X POST $BASE/settings/dismiss-picker" '"dismissed":true'

# -------------------------
echo ""
echo "=== Settings UI — キーコンボ設定フロー ==="

check "settings/set-action-type (key)" \
  "curl -s -X POST $BASE/settings/set-action-type -H 'Content-Type: application/json' -d '{\"type\":\"key\"}'" \
  '"type":"key"'

check "settings/set-key-combo" \
  "curl -s -X POST $BASE/settings/set-key-combo -H 'Content-Type: application/json' -d '{\"combo\":\"cmd+shift+v\"}'" \
  '"combo":"cmd+shift+v"'

check "settings/commit (key)" \
  "curl -s -X POST $BASE/settings/commit" '"committed":true'

check "settings/clear-selection (final)" \
  "curl -s -X POST $BASE/settings/clear-selection" '"cleared":true'

check "settings/move" \
  "curl -s -X POST $BASE/settings/move -H 'Content-Type: application/json' -d '{\"x\":100,\"y\":200}'" \
  '"x"'

check "settings/close" \
  "curl -s -X POST $BASE/settings/close" '"visible":false'

# -------------------------
echo ""
echo "=== ウィンドウ操作 ==="

check "window_opacity" \
  "curl -s -X POST $BASE/window/opacity -H 'Content-Type: application/json' -d '{\"value\":0.6}'" \
  '"opacity"'

check "window_move" \
  "curl -s -X POST $BASE/window/move -H 'Content-Type: application/json' -d '{\"x\":300,\"y\":300}'" \
  '"x"'

check "window_resize" \
  "curl -s -X POST $BASE/window/resize -H 'Content-Type: application/json' -d '{\"width\":200,\"height\":280}'" \
  '"width"'

check "window_hide" \
  "curl -s -X POST $BASE/window/hide" '"visible":false'

check "window_toggle (show)" \
  "curl -s -X POST $BASE/window/toggle" '"visible":true'

check "window_opacity (restore)" \
  "curl -s -X POST $BASE/window/opacity -H 'Content-Type: application/json' -d '{\"value\":1.0}'" \
  '"opacity"'

# -------------------------
echo ""
echo "=== アクション実行 ==="

check "run_action (text)" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE/action \
    -H 'Content-Type: application/json' \
    -d '{\"type\":\"text\",\"content\":\"script test\",\"restoreClipboard\":true}'" \
  "202"

check "log_tail" \
  "curl -s '$BASE/log/tail?limit=5'" '"events"'

check "log_tail (no errors)" \
  "curl -s '$BASE/log/tail?since=30s&level=error'" \
  '"events"'

check "icon_for_app (Safari)" \
  "curl -s '$BASE/icon/for-app?bundleId=com.apple.Safari'" \
  '"png_base64"'

# -------------------------
echo ""
echo "=== エラーハンドリング ==="

check "set-action-type: 不正な type → 400" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE/settings/set-action-type \
    -H 'Content-Type: application/json' -d '{\"type\":\"invalid\"}'" \
  "400"

check "select-button: id 省略 → 400" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE/settings/select-button \
    -H 'Content-Type: application/json' -d '{}'" \
  "400"

check "window_resize: 最小値未満 → 400" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE/window/resize \
    -H 'Content-Type: application/json' -d '{\"width\":10,\"height\":10}'" \
  "400"

check "preset_switch: 存在しない名前 → 400 or 404" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE/preset/switch \
    -H 'Content-Type: application/json' -d '{\"name\":\"no-such-preset\"}'" \
  "40"

# -------------------------
echo ""
echo "=== クリーンアップ ==="
curl -s -X POST "$BASE/preset/switch" \
  -H 'Content-Type: application/json' -d '{"name":"default"}' > /dev/null
curl -s -X POST "$BASE/preset/delete" \
  -H 'Content-Type: application/json' -d '{"name":"test-api-script"}' > /dev/null

check "test-api-script が削除されている" \
  "curl -s $BASE/preset/list | python3 -c \"import sys,json; names=[p['name'] for p in json.load(sys.stdin)['presets']]; print('gone' if 'test-api-script' not in names else 'still-exists')\"" \
  "gone"

# -------------------------
echo ""
echo "===== 結果: $PASS 成功 / $FAIL 失敗 ====="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

実行:
```bash
bash docs/test-settings-api.md
```

---

## 注意事項

- `settings_set_action_type` / `settings_set_action_value` / `settings_set_key_combo` / `settings_set_background_color` / `settings_set_text_color` / `settings_commit` は **ButtonEditor または GroupEditor が画面に表示されている状態でのみ有効**。`settings_select_button` か `settings_select_group` を必ず先に呼ぶこと。
- ピッカーを開いた後は `settings_dismiss_picker` で閉じること。ピッカーが開いたまま他の操作を呼ぶと無視される場合がある。
- `run_action` は 202 Accepted を返した時点でアクションをキューに積む。実際の実行結果は `log_tail` で確認する。
- テスト用プリセット (`test-api-script`) は `trap cleanup EXIT` で確実に削除されるが、強制終了（`kill -9`）した場合は手動で削除が必要。
