#!/usr/bin/env bash
# seed_install_smoke.sh — verify bundled seed presets get installed on
# first launch and that the `/preset/install-seeds` endpoint can restore
# them after deletion.
#
# Boots the GUI binary with a fresh config dir, asserts via the control
# API that midjourney + note-hashtags presets appear, then exercises the
# delete / force-reinstall path.

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

TMP_BASE="$(mktemp -d -t fm-seed-smoke)"
export FLOATINGMACRO_CONFIG_DIR="$TMP_BASE/fm-config"
mkdir -p "$FLOATINGMACRO_CONFIG_DIR/presets" "$FLOATINGMACRO_CONFIG_DIR/logs"

PORT=$(( 46000 + RANDOM % 1000 ))

pass=0; fail=0; failures=()
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

api() {
    local method="$1" path="$2" body="${3:-}"
    if [ -n "$body" ]; then
        curl -sS -X "$method" -H 'Content-Type: application/json' \
             -d "$body" --max-time 3 \
             "http://127.0.0.1:$PORT$path"
    else
        curl -sS -X "$method" --max-time 3 \
             "http://127.0.0.1:$PORT$path"
    fi
}

assert_jq() {
    local label="$1" jq_expr="$2" expected="$3" json="$4"
    local actual
    actual=$(printf '%s' "$json" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    expr = '$jq_expr'
    cur = d
    for tok in expr.split('.'):
        if tok.startswith('[') and tok.endswith(']'):
            cur = cur[int(tok[1:-1])]
        elif tok:
            cur = cur[tok]
    print(cur)
except Exception as e:
    print('ERR: ' + str(e))
")
    if [ "$actual" = "$expected" ]; then
        pass=$((pass+1)); say "✓  $label  ($actual)"
    else
        fail=$((fail+1)); failures+=("$label — expected $expected, got $actual")
        say "✗  $label  expected=$expected got=$actual"
        debug "$json"
    fi
}

# ----- Build & boot -----
say "Building FloatingMacro..."
if ! ( cd "$ROOT" && swift build --product FloatingMacro ) >/dev/null 2>&1; then
    say "✗  build failed"; exit 1
fi
APP_BIN="$(cd "$ROOT" && swift build --product FloatingMacro --show-bin-path)/FloatingMacro"

# Empty config: no seeds, no AppConfig.json — installer should run on first launch.
cat > "$FLOATINGMACRO_CONFIG_DIR/config.json" <<EOF
{
  "version": 1,
  "activePreset": "default",
  "controlAPI": { "enabled": true, "port": $PORT, "requireAuth": true, "testMode": true }
}
EOF

"$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!

# Wait until /ping responds
for _ in $(seq 1 50); do
    if curl -sS --max-time 0.2 "http://127.0.0.1:$PORT/ping" >/dev/null 2>&1; then break; fi
    sleep 0.1
done

# ----- 1. Seeds present after first launch -----
list_json=$(api GET /preset/list)
# Substring search is the simplest way to validate presence; the exact
# JSON shape of /preset/list isn't critical for this test.
if printf '%s' "$list_json" | grep -q '"midjourney"'; then
    pass=$((pass+1)); say "✓  midjourney appears in /preset/list"
else
    fail=$((fail+1)); failures+=("midjourney missing from /preset/list")
    say "✗  midjourney missing from /preset/list"
    debug "$list_json"
fi
if printf '%s' "$list_json" | grep -q '"note-hashtags"'; then
    pass=$((pass+1)); say "✓  note-hashtags appears in /preset/list"
else
    fail=$((fail+1)); failures+=("note-hashtags missing from /preset/list")
    say "✗  note-hashtags missing from /preset/list"
    debug "$list_json"
fi

# ----- 2. Export and validate structure -----
mj_json=$(api POST /preset/export '{"name":"midjourney"}')
assert_jq "midjourney displayName"    "preset.displayName"             "MidJourney 用"        "$mj_json"
assert_jq "midjourney first group"    "preset.groups.[0].label"        "Aspect Ratio"        "$mj_json"
assert_jq "midjourney first button"   "preset.groups.[0].buttons.[0].label" "1:1"            "$mj_json"

note_json=$(api POST /preset/export '{"name":"note-hashtags"}')
assert_jq "note displayName"          "preset.displayName"             "note.com Hash Tag"  "$note_json"
assert_jq "note first group"          "preset.groups.[0].label"        "Basic"                  "$note_json"

# ----- 3. seedInstalled flag persisted -----
if grep -q '"seedInstalled" *: *true' "$FLOATINGMACRO_CONFIG_DIR/config.json"; then
    pass=$((pass+1)); say "✓  seedInstalled flag persisted in config.json"
else
    fail=$((fail+1)); failures+=("seedInstalled flag not set in config.json")
    say "✗  seedInstalled flag not set"
fi

# ----- 4. Delete then force re-install -----
api POST /preset/delete '{"name":"midjourney"}' >/dev/null
list2=$(api GET /preset/list)
if printf '%s' "$list2" | grep -q '"midjourney"'; then
    fail=$((fail+1)); failures+=("delete failed — midjourney still in list")
    say "✗  delete failed — midjourney still in list"
else
    pass=$((pass+1)); say "✓  delete removed midjourney"
fi

reinstall=$(api POST /preset/install-seeds '{"force":false}')
if printf '%s' "$reinstall" | grep -q '"installed":\[.*"midjourney".*\]'; then
    pass=$((pass+1)); say "✓  install-seeds restored midjourney (force=false)"
else
    fail=$((fail+1)); failures+=("install-seeds did not restore midjourney")
    say "✗  install-seeds did not restore midjourney"
    debug "$reinstall"
fi

# After force=false reinstall, note-hashtags should be skipped (file still exists)
if printf '%s' "$reinstall" | grep -q '"skipped":\[.*"note-hashtags".*\]'; then
    pass=$((pass+1)); say "✓  install-seeds skipped existing note-hashtags"
else
    fail=$((fail+1)); failures+=("install-seeds did not skip note-hashtags")
    say "✗  install-seeds did not skip note-hashtags"
    debug "$reinstall"
fi

# ----- Summary -----
say ""
say "──────────────────────────────"
say "  pass: $pass    fail: $fail"
if [ "$fail" -gt 0 ]; then
    for f in "${failures[@]}"; do say "  ✗  $f"; done
    exit 1
fi
say "  All seed-install checks passed."
