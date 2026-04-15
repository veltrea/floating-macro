#!/usr/bin/env bash
# control_api_smoke.sh — drive the FloatingMacroApp HTTP control API via curl.
#
# Spins up the real GUI binary with a controlled config directory, enables the
# control API, and verifies every endpoint from outside.
#
# Pre-flight:
#   - The app will attempt to show a floating panel on the user's screen.
#     This is fine; we focus on API behavior and kill the process when done.
#   - Accessibility / Automation permissions are NOT required for any of these
#     calls (we don't invoke /action with key/text/terminal during smoke).
#
# Usage:
#   bash scripts/control_api_smoke.sh
#   VERBOSE=1 bash scripts/control_api_smoke.sh

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TMP_BASE="$(mktemp -d -t fmctl-smoke)"
export FLOATINGMACRO_CONFIG_DIR="$TMP_BASE/fm-config"
mkdir -p "$FLOATINGMACRO_CONFIG_DIR/presets" "$FLOATINGMACRO_CONFIG_DIR/logs"

PORT=$(( 45000 + RANDOM % 1000 ))

pass=0
fail=0
failures=()

say()   { printf '%s\n' "$*" >&2; }
debug() { [ "${VERBOSE:-0}" = "1" ] && say "    | $*"; return 0; }

cleanup() {
    if [ -n "${APP_PID:-}" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        sleep 0.3
        kill -9 "$APP_PID" 2>/dev/null || true
    fi
    if [ "$fail" -eq 0 ]; then
        rm -rf "$TMP_BASE"
    else
        say "Temp dir kept for inspection: $TMP_BASE"
    fi
}
trap cleanup EXIT

# Assertion helpers
expect_http() {
    local label="$1"; local expected="$2"; local method="$3"; local path="$4"; local body="${5:-}"
    local out code
    if [ -n "$body" ]; then
        out=$(curl -sS -X "$method" -H 'Content-Type: application/json' \
              -d "$body" --max-time 3 -w "\n%{http_code}" \
              "http://127.0.0.1:$PORT$path")
    else
        out=$(curl -sS -X "$method" --max-time 3 -w "\n%{http_code}" \
              "http://127.0.0.1:$PORT$path")
    fi
    code="${out##*$'\n'}"
    body="${out%$'\n'*}"
    if [ "$code" = "$expected" ]; then
        pass=$((pass+1)); say "✓  $label  (http=$code)"
        debug "$body"
    else
        fail=$((fail+1)); failures+=("$label — expected $expected, got $code")
        say "✗  $label  (http=$code, expected $expected)"
        printf '%s\n' "$body" | sed 's/^/    /'
    fi
}

expect_json_field() {
    local label="$1"; local path="$2"; local field="$3"; local expected="$4"
    local out actual
    out=$(curl -sS --max-time 3 "http://127.0.0.1:$PORT$path")
    actual=$(printf '%s' "$out" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    v = d
    for key in '$field'.split('.'):
        v = v[key] if isinstance(v, dict) else None
    print(v)
except Exception as e:
    print('ERR: ' + str(e))
")
    if [ "$actual" = "$expected" ]; then
        pass=$((pass+1)); say "✓  $label  ($field=$actual)"
    else
        fail=$((fail+1)); failures+=("$label — $field expected $expected, got $actual")
        say "✗  $label  ($field expected $expected, got $actual)"
    fi
}

# ------------------------------------------------------------------------- #
# 1. Build & initialize config
# ------------------------------------------------------------------------- #

say "Building FloatingMacro..."
if ! ( cd "$ROOT" && swift build --product FloatingMacro ) >/dev/null 2>&1; then
    say "✗  build failed"
    exit 1
fi
APP_BIN="$(cd "$ROOT" && swift build --product FloatingMacro --show-bin-path)/FloatingMacro"
if [ ! -x "$APP_BIN" ]; then
    say "✗  FloatingMacro binary not found at $APP_BIN"
    exit 1
fi
say "✓  built: $APP_BIN"

# Write a config.json that enables the control API on our random port.
cat > "$FLOATINGMACRO_CONFIG_DIR/config.json" <<EOF
{
  "version": 1,
  "activePreset": "default",
  "window": {
    "x": 100, "y": 100, "width": 200, "height": 300,
    "orientation": "vertical",
    "alwaysOnTop": true,
    "hideAfterAction": false,
    "opacity": 1.0
  },
  "controlAPI": {
    "enabled": true,
    "port": $PORT
  }
}
EOF

# Default preset
cat > "$FLOATINGMACRO_CONFIG_DIR/presets/default.json" <<'EOF'
{
  "version": 1,
  "name": "default",
  "displayName": "smoke",
  "groups": [
    {
      "id": "g1", "label": "G1", "collapsed": false,
      "buttons": [
        { "id": "b1", "label": "hello",
          "action": { "type": "text", "content": "hi" } }
      ]
    }
  ]
}
EOF

# Extra preset so we can switch to it
cat > "$FLOATINGMACRO_CONFIG_DIR/presets/alt.json" <<'EOF'
{
  "version": 1,
  "name": "alt",
  "displayName": "Alternate",
  "groups": []
}
EOF

# ------------------------------------------------------------------------- #
# 2. Launch app in background
# ------------------------------------------------------------------------- #

say "Launching FloatingMacro..."
"$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!

# Wait up to 4 seconds for /ping to succeed.
READY=0
for _ in $(seq 1 40); do
    if curl -sS --max-time 0.3 "http://127.0.0.1:$PORT/ping" >/dev/null 2>&1; then
        READY=1; break
    fi
    sleep 0.1
done
if [ "$READY" = 0 ]; then
    say "✗  control server never responded on port $PORT"
    exit 1
fi
pass=$((pass+1)); say "✓  control server live on port $PORT"

# ------------------------------------------------------------------------- #
# 3. Endpoints
# ------------------------------------------------------------------------- #

expect_http       "ping"                     200  GET  /ping
expect_json_field "ping.product is FMacro"   /ping   product   "FloatingMacro"

expect_http       "state"                    200  GET  /state
expect_json_field "state.activePreset"       /state  activePreset  "default"
expect_json_field "state.visible=True"       /state  visible       "True"

# Window hide / toggle / show
expect_http "window hide"                    200  POST /window/hide
expect_json_field "visible=False after hide" /state  visible  "False"

expect_http "window toggle (→ visible)"      200  POST /window/toggle
expect_json_field "visible=True after toggle" /state visible  "True"

expect_http "window show"                    200  POST /window/show

# Opacity
expect_http "opacity 0.5 accepted"           200  POST /window/opacity '{"value":0.5}'
expect_json_field "window.opacity"           /state  window.opacity  "0.5"
expect_http "opacity malformed body"         400  POST /window/opacity '{"nope":1}'

# Preset list / switch
expect_http       "preset list"              200  GET  /preset/list
expect_http       "preset switch alt"        200  POST /preset/switch '{"name":"alt"}'
expect_json_field "activePreset now alt"     /state  activePreset  "alt"
expect_http       "preset switch back"       200  POST /preset/switch '{"name":"default"}'
expect_http       "preset reload"            200  POST /preset/reload
expect_http       "preset switch bad body"   400  POST /preset/switch '{}'

# /action with safe shell launch (no Accessibility required)
MARKER="$TMP_BASE/ctl-marker-$RANDOM"
expect_http "action launch shell:"           202  POST /action \
    "{\"type\":\"launch\",\"target\":\"shell:touch '$MARKER'\"}"
# Give the detached Task a moment.
sleep 0.5
if [ -f "$MARKER" ]; then
    pass=$((pass+1)); say "✓  action launch actually created the marker"
else
    fail=$((fail+1)); failures+=("action launch did not create marker")
    say "✗  marker file not created"
fi

expect_http "action malformed body"          400  POST /action '{"type":"bogus"}'

# log tail
expect_http       "log tail no params"       200  GET /log/tail
expect_http       "log tail with filters"    200  "GET" "/log/tail?level=info&since=5m&limit=10"

# Window move / resize
expect_http       "window move"              200  POST /window/move   '{"x":222,"y":333}'
expect_json_field "window.x"                 /state  window.x  "222"
expect_json_field "window.y"                 /state  window.y  "333"
expect_http       "window resize"            200  POST /window/resize '{"width":260,"height":410}'
expect_json_field "window.width"             /state  window.width  "260"
expect_json_field "window.height"            /state  window.height "410"
expect_http       "move malformed body"      400  POST /window/move  '{"x":1}'
expect_http       "resize malformed body"    400  POST /window/resize '{"w":1}'

# Preset CRUD via API
expect_http "preset create"                  200  POST /preset/create '{"name":"api-created","displayName":"API作"}'
expect_http "preset rename"                  200  POST /preset/rename '{"name":"api-created","displayName":"API改名"}'

# Group add to active preset (default has g1)
expect_http "group add"                      200  POST /group/add '{"id":"g-added","label":"Added"}'
expect_http "group update label"             200  POST /group/update '{"id":"g-added","label":"AddedRenamed"}'

# Button add
expect_http "button add with styling"        200  POST /button/add \
  '{"groupId":"g-added","button":{"id":"b-styled","label":"Fancy","backgroundColor":"#ff00ff","width":160,"height":32,"action":{"type":"key","combo":"cmd+s"}}}'

# Button update — partial patch
expect_http "button update label + color"    200  POST /button/update \
  '{"id":"b-styled","label":"FancierNow","backgroundColor":"#00ffff"}'

# Verify via /preset/current that the edit landed
run_fmcli_curl() {
    curl -sS --max-time 3 "http://127.0.0.1:$PORT/preset/current"
}
if run_fmcli_curl | grep -q FancierNow; then
    pass=$((pass+1)); say "✓  button update persisted into preset"
else
    fail=$((fail+1)); failures+=("button update did not persist")
    say "✗  button update did not persist"
fi

# Button reorder (only 1 button — trivial but proves endpoint responds)
expect_http "button reorder"                 200  POST /button/reorder \
  '{"groupId":"g-added","ids":["b-styled"]}'

# Button move between groups
expect_http "button move to g1"              200  POST /button/move \
  '{"id":"b-styled","toGroupId":"g1"}'

# Button delete
expect_http "button delete"                  200  POST /button/delete '{"id":"b-styled"}'

# Group delete
expect_http "group delete"                   200  POST /group/delete '{"id":"g-added"}'

# Preset delete
expect_http "preset delete"                  200  POST /preset/delete '{"name":"api-created"}'

# Malformed CRUD
expect_http "button add bad body"            400  POST /button/add '{}'
expect_http "group add bad body"             400  POST /group/add  '{}'

# Icon endpoint — Safari ships on every Mac
expect_http "icon for bundle id"             200  GET  "/icon/for-app?bundleId=com.apple.Safari"
expect_http "icon for path"                  200  GET  "/icon/for-app?path=/Applications/Safari.app"
expect_http "icon missing params"            400  GET  "/icon/for-app"
expect_http "icon unknown bundle"            404  GET  "/icon/for-app?bundleId=com.fake.nope"

# ------------------------------------------------------------------------- #
# AI self-introduction + tool catalog
# ------------------------------------------------------------------------- #

expect_http       "manifest"                 200  GET  /manifest
expect_http       "help (alias of manifest)" 200  GET  /help
expect_json_field "manifest.product"         /manifest  product  "FloatingMacro"

# tools list in all three dialects
expect_http "tools (mcp default)"            200  GET  /tools
expect_http "tools (openai)"                 200  "GET" "/tools?format=openai"
expect_http "tools (anthropic)"              200  "GET" "/tools?format=anthropic"

# Inspect the MCP payload: first tool must include name/description/inputSchema
if curl -sS --max-time 3 "http://127.0.0.1:$PORT/tools" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert 'tools' in d
assert len(d['tools']) > 10
first = d['tools'][0]
assert 'name' in first and 'description' in first and 'inputSchema' in first
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  /tools MCP payload has name+description+inputSchema"
else
    fail=$((fail+1)); failures+=("/tools MCP payload malformed")
    say "✗  /tools MCP payload malformed"
fi

# tools/call dispatch to a simple tool
expect_http "tools/call -> ping"             200  POST /tools/call '{"name":"ping","arguments":{}}'
expect_http "tools/call -> get_state"        200  POST /tools/call '{"name":"get_state","arguments":{}}'

# tools/call with arguments (window_opacity)
expect_http "tools/call -> window_opacity"   200  POST /tools/call '{"name":"window_opacity","arguments":{"value":0.65}}'

# tools/call -> help should return the manifest
if curl -sS --max-time 3 -X POST "http://127.0.0.1:$PORT/tools/call" \
    -H 'Content-Type: application/json' \
    -d '{"name":"help","arguments":{}}' | grep -q systemPrompt; then
    pass=$((pass+1)); say "✓  tools/call help returns manifest"
else
    fail=$((fail+1)); failures+=("tools/call help did not return manifest")
    say "✗  tools/call help did not return manifest"
fi

expect_http "tools/call unknown tool 404"    404  POST /tools/call '{"name":"no_such_tool"}'
expect_http "tools/call bad body 400"        400  POST /tools/call '{}'

# ------------------------------------------------------------------------- #
# OpenAPI (ACP / REST discovery)
# ------------------------------------------------------------------------- #

expect_http       "openapi.json"             200  GET  /openapi.json
expect_json_field "openapi version"          /openapi.json  openapi  "3.1.0"

# Validate the OpenAPI document is syntactically well-formed enough for
# basic tooling by attempting to pull all path keys.
if curl -sS --max-time 3 "http://127.0.0.1:$PORT/openapi.json" | python3 -c "
import sys, json
doc = json.loads(sys.stdin.read())
assert 'paths' in doc
assert len(doc['paths']) > 10
# /window/move must be a POST with a requestBody
assert 'post' in doc['paths']['/window/move']
assert 'requestBody' in doc['paths']['/window/move']['post']
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  openapi.json has expected paths + POST requestBody"
else
    fail=$((fail+1)); failures+=("openapi.json malformed")
    say "✗  openapi.json malformed"
fi

# ------------------------------------------------------------------------- #
# A2A Agent Card
# ------------------------------------------------------------------------- #

expect_http       "agent card"               200  GET  /.well-known/agent.json
expect_json_field "agent card name"          /.well-known/agent.json  name  "FloatingMacro"

if curl -sS --max-time 3 "http://127.0.0.1:$PORT/.well-known/agent.json" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert 'skills' in d
assert 'capabilities' in d
assert d['capabilities']['streaming'] is False
assert len(d['skills']) > 10
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  agent card has skills + capabilities block"
else
    fail=$((fail+1)); failures+=("agent card malformed")
    say "✗  agent card malformed"
fi

# ------------------------------------------------------------------------- #
# MCP JSON-RPC 2.0 over /mcp
# ------------------------------------------------------------------------- #

# initialize
if curl -sS --max-time 3 -X POST "http://127.0.0.1:$PORT/mcp" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['jsonrpc'] == '2.0'
assert d['id'] == 1
assert 'serverInfo' in d['result']
assert d['result']['serverInfo']['name'] == 'FloatingMacro'
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  MCP initialize returns serverInfo"
else
    fail=$((fail+1)); failures+=("MCP initialize failed")
    say "✗  MCP initialize failed"
fi

# tools/list
if curl -sS --max-time 3 -X POST "http://127.0.0.1:$PORT/mcp" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert 'tools' in d['result']
assert len(d['result']['tools']) > 10
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  MCP tools/list returns catalog"
else
    fail=$((fail+1)); failures+=("MCP tools/list failed")
    say "✗  MCP tools/list failed"
fi

# tools/call
if curl -sS --max-time 3 -X POST "http://127.0.0.1:$PORT/mcp" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ping","arguments":{}}}' \
    | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['result']['isError'] is False
assert len(d['result']['content']) >= 1
assert d['result']['content'][0]['type'] == 'text'
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  MCP tools/call ping wraps content"
else
    fail=$((fail+1)); failures+=("MCP tools/call ping failed")
    say "✗  MCP tools/call ping failed"
fi

# tools/call with arguments
if curl -sS --max-time 3 -X POST "http://127.0.0.1:$PORT/mcp" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"window_opacity","arguments":{"value":0.75}}}' \
    | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['result']['isError'] is False
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  MCP tools/call window_opacity with args"
else
    fail=$((fail+1)); failures+=("MCP tools/call window_opacity failed")
    say "✗  MCP tools/call window_opacity failed"
fi

# Unknown method must return -32601
if curl -sS --max-time 3 -X POST "http://127.0.0.1:$PORT/mcp" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":5,"method":"unknown/method"}' \
    | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['error']['code'] == -32601
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  MCP unknown method → -32601"
else
    fail=$((fail+1)); failures+=("MCP unknown method code incorrect")
    say "✗  MCP unknown method code incorrect"
fi

# Malformed JSON must return -32700
if curl -sS --max-time 3 -X POST "http://127.0.0.1:$PORT/mcp" \
    -H 'Content-Type: application/json' \
    -d 'not valid json' \
    | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['error']['code'] == -32700
print('OK')
" 2>/dev/null | grep -q OK; then
    pass=$((pass+1)); say "✓  MCP malformed JSON → -32700"
else
    fail=$((fail+1)); failures+=("MCP parse error code incorrect")
    say "✗  MCP parse error code incorrect"
fi

# ------------------------------------------------------------------------- #
# 404 / 405
# ------------------------------------------------------------------------- #

expect_http "unknown path 404"               404  GET  /nothing
expect_http "method not allowed"             404  POST /ping

# ------------------------------------------------------------------------- #
# Summary
# ------------------------------------------------------------------------- #

say ""
say "================================"
say " control API smoke: $pass passed, $fail failed"
say "================================"
for f in "${failures[@]:-}"; do
    [ -n "$f" ] && say "  ✗ $f"
done

[ "$fail" -eq 0 ] || exit 1
exit 0
