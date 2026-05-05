#!/usr/bin/env bash
# fmcli smoke test — exercises the CLI's permission-free surface.
#
# Builds fmcli and drives it through a temporary config directory so your real
# ~/Library/Application Support/FloatingMacro is never touched.
#
# Configuration redirection is done via the FLOATINGMACRO_CONFIG_DIR env var
# (see ConfigLoader.defaultBaseURL) — we can't override HOME because
# FileManager.homeDirectoryForCurrentUser bypasses $HOME on macOS.
#
# What IS covered (no macOS permissions needed):
#   - build succeeds
#   - help / unknown subcommand exit codes
#   - config path / config init
#   - preset list reflects the newly initialized default
#   - action launch shell:<cmd>
#   - action launch <non-existent-path>
#   - permissions check
#   - preset run <unknown-button> produces an error
#
# NOT covered (Accessibility / Automation required → see docs/manual_test.md):
#   - action key, action text, action terminal
#
# Usage:
#   bash scripts/fmcli_smoke.sh
#   VERBOSE=1 bash scripts/fmcli_smoke.sh
#
# Exit: 0 = all pass, 1 = any failure.

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TMP_BASE="$(mktemp -d -t fmcli-smoke)"
export FLOATINGMACRO_CONFIG_DIR="$TMP_BASE/fm-config"

pass=0
fail=0
failures=()

say()   { printf '%s\n' "$*" >&2; }
debug() { [ "${VERBOSE:-0}" = "1" ] && say "    | $*"; return 0; }

# Run fmcli and capture output + exit code without tripping set -e / || true
# pitfalls. We write stdout+stderr to a tmp file so $? comes from fmcli alone.
run_fmcli() {
    local stdout_file="$TMP_BASE/out.$$"
    "$FMCLI" "$@" >"$stdout_file" 2>&1
    local code=$?
    LAST_OUTPUT="$(cat "$stdout_file")"
    rm -f "$stdout_file"
    return "$code"
}

expect_exit() {
    local label="$1"; shift
    local expected="$1"; shift
    run_fmcli "$@"
    local code=$?
    if [ "$code" -eq "$expected" ]; then
        pass=$((pass+1)); say "✓  $label  (exit=$code)"
        debug "$LAST_OUTPUT"
    else
        fail=$((fail+1))
        failures+=("$label — expected exit $expected, got $code")
        say "✗  $label  (exit=$code, expected $expected)"
        printf '%s\n' "$LAST_OUTPUT" | sed 's/^/    /'
    fi
}

expect_contains() {
    local label="$1"; shift
    local needle="$1"; shift
    run_fmcli "$@"
    local code=$?
    if [ "$code" -eq 0 ] && printf '%s' "$LAST_OUTPUT" | grep -q -- "$needle"; then
        pass=$((pass+1)); say "✓  $label"
        debug "$LAST_OUTPUT"
    else
        fail=$((fail+1))
        failures+=("$label — did not contain '$needle' (exit=$code)")
        say "✗  $label"
        printf '%s\n' "$LAST_OUTPUT" | sed 's/^/    /'
    fi
}

assert_file() {
    local label="$1"; shift
    local path="$1"; shift
    if [ -f "$path" ]; then
        pass=$((pass+1)); say "✓  $label"
    else
        fail=$((fail+1)); failures+=("$label — file missing at $path")
        say "✗  $label"
        say "    path: $path"
    fi
}

# ------------------------------------------------------------------------- #
# 1. Build
# ------------------------------------------------------------------------- #

say "Building fmcli..."
if ! ( cd "$ROOT" && swift build --product fmcli ) >/dev/null 2>&1; then
    say "✗  build failed — aborting"
    ( cd "$ROOT" && swift build --product fmcli ) 2>&1 | sed 's/^/    /' | tail -30
    exit 1
fi
FMCLI="$(cd "$ROOT" && swift build --product fmcli --show-bin-path)/fmcli"
if [ ! -x "$FMCLI" ]; then
    say "✗  built fmcli not found at $FMCLI"
    exit 1
fi
say "✓  fmcli built at $FMCLI"
say "Using config dir: $FLOATINGMACRO_CONFIG_DIR"

# ------------------------------------------------------------------------- #
# 2. Help / unknown command
# ------------------------------------------------------------------------- #

expect_contains "help prints usage"                "fmcli" help
expect_contains "--help prints usage"              "fmcli" --help
expect_exit     "unknown top-level exits non-zero"    1    notacommand
expect_exit     "empty action arg exits non-zero"     1    action

# ------------------------------------------------------------------------- #
# 3. config path / init
# ------------------------------------------------------------------------- #

# config path should echo the override directory we set.
run_fmcli config path
if [ "$?" -eq 0 ] && printf '%s' "$LAST_OUTPUT" | grep -q "$FLOATINGMACRO_CONFIG_DIR"; then
    pass=$((pass+1)); say "✓  config path honors FLOATINGMACRO_CONFIG_DIR"
else
    fail=$((fail+1)); failures+=("config path did not echo override dir")
    say "✗  config path did not echo override dir"
    printf '%s\n' "$LAST_OUTPUT" | sed 's/^/    /'
fi

expect_exit "config init succeeds" 0 config init

assert_file "config.json was written"                                 \
    "$FLOATINGMACRO_CONFIG_DIR/config.json"
assert_file "default preset was written"                              \
    "$FLOATINGMACRO_CONFIG_DIR/presets/default.json"
if [ -d "$FLOATINGMACRO_CONFIG_DIR/logs" ]; then
    pass=$((pass+1)); say "✓  logs dir created"
else
    fail=$((fail+1)); failures+=("logs dir NOT created")
    say "✗  logs dir NOT created"
fi

expect_exit "second config init still succeeds" 0 config init

# ------------------------------------------------------------------------- #
# 4. preset list
# ------------------------------------------------------------------------- #

expect_contains "preset list mentions default" "default" preset list

# ------------------------------------------------------------------------- #
# 5. launch shell: branch
# ------------------------------------------------------------------------- #

MARKER="$TMP_BASE/marker-$(date +%s)-$RANDOM"
expect_exit "shell: launch creates file"          0 action launch "shell:touch '$MARKER'"
assert_file "marker file was created"              "$MARKER"

expect_exit "shell: non-zero exit propagates"     1 action launch "shell:exit 1"
expect_exit "shell: stderr captured"              1 action launch "shell:echo fail 1>&2; exit 2"
expect_exit "launch of nonexistent path fails"    1 action launch "/nope/does/not/exist/$RANDOM"

# ------------------------------------------------------------------------- #
# 6. permissions check
# ------------------------------------------------------------------------- #

expect_exit     "permissions check runs"              0              permissions check
expect_contains "permissions check mentions Access"  "Accessibility" permissions check

# ------------------------------------------------------------------------- #
# 7. preset run error paths
# ------------------------------------------------------------------------- #

expect_exit "preset run missing args errors"        1 preset run
expect_exit "preset run unknown button errors"      1 preset run default btn-does-not-exist
expect_exit "preset run unknown preset errors"      1 preset run no-such-preset whatever

# ------------------------------------------------------------------------- #
# 8. Logging subsystem
# ------------------------------------------------------------------------- #

expect_contains "log path echoes logs/floatingmacro.log" "floatingmacro.log" log path

# After all the above commands, the log file should exist and contain events.
LOG_FILE="$FLOATINGMACRO_CONFIG_DIR/logs/floatingmacro.log"
assert_file "log file was written"                                   "$LOG_FILE"

# Each line should be parseable as JSON.
if [ -f "$LOG_FILE" ]; then
    bad_lines=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if ! printf '%s' "$line" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
            bad_lines=$((bad_lines+1))
        fi
    done < "$LOG_FILE"
    if [ "$bad_lines" -eq 0 ]; then
        pass=$((pass+1)); say "✓  every log line is valid JSON"
    else
        fail=$((fail+1)); failures+=("log file has $bad_lines malformed lines")
        say "✗  log file has $bad_lines malformed JSON lines"
    fi
fi

# log tail JSON mode should produce output that decodes
run_fmcli log tail --limit 5 --json
if [ "$?" -eq 0 ] && [ -n "$LAST_OUTPUT" ]; then
    pass=$((pass+1)); say "✓  log tail --json emits output"
else
    fail=$((fail+1)); failures+=("log tail --json produced no output")
    say "✗  log tail --json produced no output"
fi

# log tail with level filter
expect_exit "log tail --level info succeeds"  0 log tail --level info  --limit 5
expect_exit "log tail --level error succeeds" 0 log tail --level error --limit 5
expect_exit "log tail --since 1h succeeds"    0 log tail --since 1h    --limit 5

# Unknown log subcommand
expect_exit "log unknown subcommand errors"   1 log bogus

# --log-level debug should produce more verbose output than info
run_fmcli --log-level debug action launch "shell:true"
debug_lines=$(printf '%s' "$LAST_OUTPUT" | grep -c DEBUG || true)
if [ "$debug_lines" -gt 0 ]; then
    pass=$((pass+1)); say "✓  --log-level debug emits DEBUG lines"
else
    fail=$((fail+1)); failures+=("--log-level debug did not emit DEBUG lines")
    say "✗  --log-level debug did not emit DEBUG lines"
    printf '%s\n' "$LAST_OUTPUT" | sed 's/^/    /'
fi

# With --log-level warn, DEBUG/INFO should not appear on stderr
run_fmcli --log-level warn action launch "shell:true"
warn_debug=$(printf '%s' "$LAST_OUTPUT" | grep -c "DEBUG\|INFO " || true)
if [ "$warn_debug" -eq 0 ]; then
    pass=$((pass+1)); say "✓  --log-level warn suppresses DEBUG/INFO on console"
else
    fail=$((fail+1)); failures+=("--log-level warn still emitted DEBUG/INFO")
    say "✗  --log-level warn still emitted DEBUG/INFO"
fi

# ------------------------------------------------------------------------- #
# Summary
# ------------------------------------------------------------------------- #

say ""
say "================================"
say " fmcli smoke: $pass passed, $fail failed"
say "================================"
for f in "${failures[@]:-}"; do
    [ -n "$f" ] && say "  ✗ $f"
done

if [ "$fail" -eq 0 ]; then
    rm -rf "$TMP_BASE"
    exit 0
else
    say "Temp dir kept for inspection: $TMP_BASE"
    exit 1
fi
