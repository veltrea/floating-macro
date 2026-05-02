#!/bin/bash
# text_inject_e2e.sh — drive FloatingMacro's run_action against the
# fm-test-target harness and verify the pasted text byte-for-byte.
#
# Prereqs:
#   - FloatingMacro app is running (control API on 127.0.0.1:17430)
#   - Keychain item "FloatingMacro / ControlAPIToken" exists
#   - swift build has produced fm-test-target
#
# What it does:
#   1. Launch fm-test-target on :17431
#   2. For each test case: focus harness, clear text, fire run_action,
#      wait for paste to settle, read /text, diff vs expected.
#   3. Print PASS / FAIL with a summary at the end.
#
# Exit code: 0 if all PASS, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FM_PORT="${FM_PORT:-17430}"
TARGET_PORT="${TARGET_PORT:-17431}"
PASTE_SETTLE_SEC="${PASTE_SETTLE_SEC:-0.6}"

# Resolve target binary
TARGET_BIN="$(cd "$REPO_ROOT" && swift build --show-bin-path 2>/dev/null)/fm-test-target"
if [ ! -x "$TARGET_BIN" ]; then
  echo "ERR: fm-test-target not built. Run: swift build --product fm-test-target" >&2
  exit 2
fi

FM_TOKEN_FILE="$HOME/Library/Application Support/FloatingMacro/control_api_token"
if [ -r "$FM_TOKEN_FILE" ]; then
    FM_TOKEN=$(cat "$FM_TOKEN_FILE")
else
    FM_TOKEN=$(security find-generic-password -s FloatingMacro -a ControlAPIToken -w 2>/dev/null || true)
fi
if [ -z "$FM_TOKEN" ]; then
  echo "ERR: could not read FloatingMacro Bearer token (file or Keychain)." >&2
  exit 2
fi

# Sanity-check FloatingMacro is up
if ! curl -sf -m 1 "http://127.0.0.1:$FM_PORT/ping" >/dev/null; then
  echo "ERR: FloatingMacro not responding on :$FM_PORT" >&2
  exit 2
fi

# --- Launch harness ---------------------------------------------------------
echo "Launching fm-test-target on :$TARGET_PORT ..."
FM_TEST_TARGET_PORT="$TARGET_PORT" "$TARGET_BIN" >/tmp/fm-test-target.log 2>&1 &
TARGET_PID=$!
cleanup() {
  curl -s -m 1 -X POST "http://127.0.0.1:$TARGET_PORT/quit" >/dev/null 2>&1 || true
  sleep 0.2
  kill "$TARGET_PID" 2>/dev/null || true
  wait "$TARGET_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for /health
for _ in $(seq 1 50); do
  if curl -sf -m 1 "http://127.0.0.1:$TARGET_PORT/health" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! curl -sf -m 1 "http://127.0.0.1:$TARGET_PORT/health" >/dev/null; then
  echo "ERR: fm-test-target did not become ready in time." >&2
  echo "--- target log ---" >&2
  cat /tmp/fm-test-target.log >&2
  exit 2
fi

# --- Helpers ----------------------------------------------------------------
target_focus()  { curl -sf -m 2 -X POST "http://127.0.0.1:$TARGET_PORT/focus" >/dev/null; }
target_clear()  { curl -sf -m 2 -X POST "http://127.0.0.1:$TARGET_PORT/clear" >/dev/null; }
target_text()   { curl -sf -m 2 "http://127.0.0.1:$TARGET_PORT/text" \
                  | python3 -c "import json,sys; print(json.load(sys.stdin)['text'], end='')"; }
target_clear_events() { curl -sf -m 2 -X POST "http://127.0.0.1:$TARGET_PORT/events/clear" >/dev/null; }
# Count keyDown events whose characters == "v" AND modifier flags include
# Cmd (mask 0x00100000). This isolates the Cmd+V event we expect to receive.
target_cmdv_count() {
  curl -sf -m 2 "http://127.0.0.1:$TARGET_PORT/events" | python3 -c "
import json, sys
evs = json.load(sys.stdin)['events']
n = sum(1 for e in evs
        if e.get('charactersIgnoringModifiers') == 'v'
        and (e.get('modifierFlags', 0) & 0x00100000))
print(n)
"
}

# Fire run_action via /tools/call. $1 = action JSON.
fm_run_action() {
  curl -sf -m 5 -X POST \
    -H "Authorization: Bearer $FM_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"run_action\",\"arguments\":$1}" \
    "http://127.0.0.1:$FM_PORT/tools/call" >/dev/null
}

# Press a button by id — same code path as a real panel click. This is
# what we use for the FloatingMacro test cases so the test exercises
# the full production stack (PresetManager.executeButton + blacklist
# check + transient-error display) AND asserts the button definition is
# wired up correctly. Returns non-zero if the API replies non-202.
fm_press() {
  local id="$1"
  curl -sf -m 5 -X POST \
    -H "Authorization: Bearer $FM_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"button_press\",\"arguments\":{\"id\":\"$id\"}}" \
    "http://127.0.0.1:$FM_PORT/tools/call" >/dev/null
}

# Switch active preset. Required so that the buttons we want to press
# (in the "debug" preset) are actually loaded into PresetManager.
fm_preset_switch() {
  curl -sf -m 5 -X POST \
    -H "Authorization: Bearer $FM_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"preset_switch\",\"arguments\":{\"name\":\"$1\"}}" \
    "http://127.0.0.1:$FM_PORT/tools/call" >/dev/null
}

# Read the active preset name.
fm_active_preset() {
  curl -sf -m 5 -H "Authorization: Bearer $FM_TOKEN" \
    "http://127.0.0.1:$FM_PORT/state" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('activePreset',''))"
}

# --- Baseline: verify the harness behaves like a real text input -----------
# Every standard editing operation must work via osascript (System Events).
# If any of these fail, the harness isn't a credible test environment and
# we MUST NOT proceed — passing or failing the FloatingMacro tests below
# would mean nothing.
#
# We dispatch all keystrokes through System Events because:
#   - It uses the same OS-level event tap that FloatingMacro uses, so
#     "events arrive" semantics are equivalent;
#   - But unlike FloatingMacro it goes through System Events.app, which
#     has its own (already-granted) Accessibility permission, so we can
#     trust it as a known-good control.

osa_keystroke() {
  # $1 = literal text. Quotes/backslashes are escaped for osascript.
  local s="$1"
  local esc
  esc=$(printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  osascript -e "tell application \"System Events\" to keystroke \"$esc\"" >/dev/null 2>&1
}
osa_combo() {
  # $1 = key string (e.g. "v"), $2 = modifier list ("command down" or "command down, shift down")
  osascript -e "tell application \"System Events\" to keystroke \"$1\" using {$2}" >/dev/null 2>&1
}
osa_key_code() {
  # $1 = numeric key code (used for arrows / delete)
  osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1
}

# Set the system clipboard to a literal string. We go through Python +
# AppKit (NSPasteboard) directly because:
#   - `pbcopy` mangles multi-byte input under LC_CTYPE=C
#   - `osascript "set the clipboard"` mojibakes Japanese on the pasteboard
#   - NSPasteboard.setString is the same path Cocoa apps actually use
# We pass the payload via stdin to avoid shell quoting issues entirely.
osa_set_clipboard() {
  python3 -c "
import sys
from AppKit import NSPasteboard, NSStringPboardType
s = sys.stdin.read()
pb = NSPasteboard.generalPasteboard()
pb.clearContents()
pb.setString_forType_(s, 'public.utf8-plain-text')
" <<< "$1" >/dev/null 2>&1
}

# Read the clipboard via the same NSPasteboard API for symmetric semantics.
# pbpaste under LC_CTYPE=C corrupts multi-byte output, so we avoid it.
ns_pbpaste() {
  python3 -c "
from AppKit import NSPasteboard
pb = NSPasteboard.generalPasteboard()
s = pb.stringForType_('public.utf8-plain-text') or ''
import sys; sys.stdout.write(s)
"
}

# Spin until the clipboard textually equals $1 (or 1 second elapses).
# Use this to absorb the variable lag between pbcopy returning and the
# pasteboard actually being readable by other processes.
wait_clipboard_equals() {
  local want="$1"
  for _ in $(seq 1 20); do
    [ "$(ns_pbpaste)" = "$want" ] && return 0
    sleep 0.05
  done
  return 1
}

# Spin until /text equals $1 (or 1 second elapses). Same idea but for
# the harness side.
wait_text_equals() {
  local want="$1"
  for _ in $(seq 1 20); do
    [ "$(target_text)" = "$want" ] && return 0
    sleep 0.05
  done
  return 1
}

baseline_check() {
  local name="$1"; local expected="$2"; local got="$3"
  if [ "$got" = "$expected" ]; then
    printf "  \033[32mok\033[0m    %s\n" "$name"
    return 0
  else
    printf "  \033[31mFAIL\033[0m  %s\n" "$name"
    printf "        expected (%d): %q\n" "${#expected}" "$expected"
    printf "        got      (%d): %q\n" "${#got}"      "$got"
    return 1
  fi
}

echo "Baseline: verify fm-test-target's standard editing operations work..."
echo "  (everything routes through Cmd+V, Cmd+C, Cmd+X, Cmd+A — same path"
echo "   FloatingMacro uses, so IME state does not affect these checks.)"

# Focus needs real time to settle, especially with an IME loaded — the OS
# may swap input contexts and that's not instantaneous. The script-wide
# default below is intentionally generous.
SETTLE=${SETTLE:-0.7}

# Helper: prepare the harness for a fresh test. Refocus every time because
# any background app activation (notification center, Claude Desktop, etc.)
# can steal focus mid-script and silently invalidate the next paste.
prep_target() {
  target_focus
  target_clear
  target_clear_events
  sleep "$SETTLE"
}

# Helper: paste $1 (a literal string) and wait for /text to equal it.
# Uses osa_set_clipboard for multi-byte safety. Returns 0 on success.
paste_and_wait() {
  local want="$1"
  osa_set_clipboard "$want"
  wait_clipboard_equals "$want" || return 1
  osa_combo "v" "command down"
  wait_text_equals "$want"
}

prep_target
BASELINE_FAIL=0

# 1. Cmd+V: clipboard → text view. This is the OS-level paste path that
#    FloatingMacro depends on. If this fails, nothing else matters.
paste_and_wait "hello"
baseline_check "Cmd+V paste from clipboard"     "hello"   "$(target_text)" || BASELINE_FAIL=1

# 2. Cmd+A + Cmd+C: select-all then copy must place text on clipboard
osa_set_clipboard "RESET_CLIPBOARD"; wait_clipboard_equals "RESET_CLIPBOARD"
osa_combo "a" "command down"; sleep 0.3
osa_combo "c" "command down"
wait_clipboard_equals "hello"
baseline_check "Cmd+A → Cmd+C copies selection" "hello"   "$(ns_pbpaste)"     || BASELINE_FAIL=1

# 3. Cmd+A + Cmd+X: cut empties the view and puts content on clipboard
osa_set_clipboard "RESET_CLIPBOARD"; wait_clipboard_equals "RESET_CLIPBOARD"
osa_combo "a" "command down"; sleep 0.3
osa_combo "x" "command down"
wait_text_equals ""
wait_clipboard_equals "hello"
baseline_check "Cmd+A → Cmd+X empties view"     ""        "$(target_text)" || BASELINE_FAIL=1
baseline_check "Cmd+X puts cut text on clipboard" "hello" "$(ns_pbpaste)"     || BASELINE_FAIL=1

# 4. Cmd+V again must restore. This proves the round-trip is symmetric.
osa_combo "v" "command down"
wait_text_equals "hello"
baseline_check "Cmd+V restores cut text"        "hello"   "$(target_text)" || BASELINE_FAIL=1

# 5. Multi-byte (Japanese) round-trip via clipboard.
prep_target
paste_and_wait "日本語テスト"
baseline_check "Japanese paste round-trip"      "日本語テスト" "$(target_text)" || BASELINE_FAIL=1

# 6. Smart substitution MUST be off — straight quotes stay straight.
prep_target
paste_and_wait '"hi" -- ...'
baseline_check "no smart-substitution rewrite"  '"hi" -- ...' "$(target_text)" || BASELINE_FAIL=1

# 7. Long paste (proves the responder chain isn't truncating). osa_set_clipboard
#    embeds the literal in an AppleScript string, so 500 chars is fine.
LONG_BL="$(python3 -c "print('X' * 500, end='')")"
prep_target
paste_and_wait "$LONG_BL"
baseline_check "500-char paste arrives intact"  "$LONG_BL" "$(target_text)" || BASELINE_FAIL=1

if [ "$BASELINE_FAIL" -ne 0 ]; then
  echo
  echo "Baseline FAILED — fm-test-target's clipboard editing path is broken."
  echo "FloatingMacro test results would be meaningless. Aborting."
  echo
  echo "Most likely causes:"
  echo "  - System Events lacks Accessibility permission, OR"
  echo "  - the controlling Terminal lacks Automation permission for"
  echo "    System Events (System Settings → Privacy → Automation → Terminal)."
  echo "  - SETTLE=$SETTLE is still too short for this machine — bump it"
  echo "    (e.g. SETTLE=1.5 bash scripts/text_inject_e2e.sh)."
  exit 2
fi
echo "  baseline OK — paste / copy / cut / select-all all behave correctly."

PASS=0
FAIL=0
FAILED_NAMES=()
ALL_EMPTY=true
KEYDOWN_NEVER_ARRIVED=true   # set false the first time we observe a Cmd+V keyDown

run_case() {
  local name="$1"
  local expected="$2"
  local button_id="$3"

  prep_target   # focus + clear + clear-events + SETTLE wait

  # Press by id — synthesizes a real mouse click on the panel via AX
  # lookup + CGEvent. This goes through the full OS event dispatch chain
  # (window manager → hit-test → SwiftUI Button gesture → onTap), so the
  # test catches failure modes a direct executeButton call would mask:
  # window obstruction, broken hit-test, disabled views, etc.
  fm_press "$button_id"

  # Spin-wait for either the expected text to land OR the bound to elapse.
  # We can't just poll for "non-empty" because some cases legitimately
  # paste empty content; we poll for the actual expected string.
  for _ in $(seq 1 20); do
    [ "$(target_text)" = "$expected" ] && break
    sleep 0.1
  done
  # One extra settle so any late paste still gets recorded before we read.
  sleep "$PASTE_SETTLE_SEC"

  local got
  got="$(target_text)"

  # Two-axis observation:
  #   keyDown count: did the OS deliver Cmd+V to fm-test-target at all?
  #   text match:    did the resulting paste produce the expected string?
  # The 2x2 outcome distinguishes upstream failures (CGEvent.post silently
  # dropped) from downstream failures (clipboard race, encoding mangling).
  local cmdv_n
  cmdv_n="$(target_cmdv_count)"
  [ "$cmdv_n" -gt 0 ] && KEYDOWN_NEVER_ARRIVED=false

  local key_tag text_tag
  if [ "$cmdv_n" -gt 0 ]; then key_tag="\033[32mkey✓\033[0m"; else key_tag="\033[31mkey✗\033[0m"; fi
  if [ "$got" = "$expected" ]; then text_tag="\033[32mtext✓\033[0m"; else text_tag="\033[31mtext✗\033[0m"; fi

  if [ "$got" = "$expected" ]; then
    printf "  [%b %b] %s\n" "$key_tag" "$text_tag" "$name"
    PASS=$((PASS + 1))
    ALL_EMPTY=false
  else
    printf "  [%b %b] %s\n" "$key_tag" "$text_tag" "$name"
    printf "        expected (%d chars): %q\n" "${#expected}" "$expected"
    printf "        got      (%d chars): %q\n" "${#got}"      "$got"
    printf "        Cmd+V keyDowns received: %s\n" "$cmdv_n"
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name")
    [ -n "$got" ] && ALL_EMPTY=false
  fi
}

# --- Switch to the "debug" preset so the test buttons are loaded. -----------
# Remember the previous active preset and restore it on exit so a casual
# `bash text_inject_e2e.sh` doesn't leave the user stranded on debug.
ORIGINAL_PRESET="$(fm_active_preset)"
restore_preset() {
  if [ -n "${ORIGINAL_PRESET:-}" ] && [ "$ORIGINAL_PRESET" != "debug" ]; then
    fm_preset_switch "$ORIGINAL_PRESET" || true
  fi
}
trap 'restore_preset; cleanup' EXIT

if [ "$ORIGINAL_PRESET" != "debug" ]; then
  echo
  echo "Switching FloatingMacro active preset → debug (was: $ORIGINAL_PRESET)..."
  fm_preset_switch "debug" || { echo "ERR: failed to switch to debug preset" >&2; exit 2; }
  sleep 0.5
fi

echo
echo "Running cases (via button_press → real CGEvent mouse click on the panel)..."

# Each case maps to a button id in the debug preset. The test asserts both
# (1) that the button is correctly wired (id resolves, action dispatches)
# and (2) that the resulting paste lands as expected on the harness.

run_case "ascii single-line"                       "Hello, World!"                     "btn-test-ascii"
run_case "japanese"                                "こんにちは、世界"                  "btn-test-japanese"
run_case "multiline"                               $'line one\nline two\nline three'   "btn-test-multiline"
run_case "slash command /compact"                  "/compact"                          "btn-test-slash"
run_case "punctuation that smart-subst would mangle" $'"quote" \'apos\' ... -- '       "btn-test-punct"
run_case "long 600-char paste"                     "$(python3 -c "print('A' * 600, end='')")"  "btn-test-long"
run_case "restoreClipboard=false"                  "without restore"                   "btn-test-norestore"

# --- Summary ---------------------------------------------------------------
echo
echo "Result: $PASS passed, $FAIL failed."
if [ "$FAIL" -gt 0 ]; then
  echo "Failing cases:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  echo
  if [ "$KEYDOWN_NEVER_ARRIVED" = "true" ]; then
    echo "Diagnostic: NO Cmd+V keyDown ever reached fm-test-target."
    echo "  Baseline passed (osascript Cmd+V works), so the harness can receive"
    echo "  paste events. FloatingMacro's CGEvent.post is being SILENTLY dropped"
    echo "  by macOS — there is no API to detect this beyond observing 'no event"
    echo "  arrived', which is exactly what this harness just did."
    echo
    echo "  Cause: the rebuilt FloatingMacro binary is treated as a different app"
    echo "  by the OS even though the entry in System Settings still lists it."
    echo "  Fix:"
    echo "    1) System Settings → Privacy & Security → Accessibility"
    echo "    2) Remove the FloatingMacro entry"
    echo "    3) Add it back from /Volumes/DISK/dev/floatingmacro/build/FloatingMacro.app"
    echo "    4) Re-run this script"
    echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
    echo
  elif [ "$ALL_EMPTY" = "true" ]; then
    echo "Diagnostic: Cmd+V did arrive but no text was pasted."
    echo "  This is a downstream failure — likely the clipboard restore race"
    echo "  (TextActionExecutor restores the snapshot before the target app"
    echo "  reads the pasteboard) or a pasteboard format mismatch."
    echo
  fi
  echo "Recent target keyDown events (last 20):"
  curl -sf "http://127.0.0.1:$TARGET_PORT/events" \
    | python3 -c "
import json, sys
evs = json.load(sys.stdin)['events'][-20:]
for e in evs:
    print(f'  {e[\"timestampMs\"]:>6} ms  kc={e[\"keyCode\"]:>3}  mods=0x{e[\"modifierFlags\"]:08x}  chars={e[\"characters\"]!r}')
" || true
  exit 1
fi

exit 0
