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
#   1. Launch fm-test-target on :17435
#   2. For each test case: focus harness, clear text, fire run_action,
#      wait for paste to settle, read /text, diff vs expected.
#   3. Print PASS / FAIL with a summary at the end.
#
# Exit code: 0 if all PASS, 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FM_PORT="${FM_PORT:-17430}"
TARGET_PORT="${TARGET_PORT:-17435}"
PASTE_SETTLE_SEC="${PASTE_SETTLE_SEC:-0.6}"

# --- Screenshot capture --------------------------------------------------- #
# Each case takes a full-screen screenshot AFTER the action lands. Reviewing
# these later is the only way to catch visual regressions that the byte-diff
# checks can't see — e.g. a dropdown menu that opens at the wrong position,
# a UI element clipped by the panel border, or an action confirmation dialog
# that should never have appeared. PNGs go to a per-run directory so multiple
# runs don't overwrite each other.
SCREENSHOT_DIR="${SCREENSHOT_DIR:-/tmp/fm-test-screens/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$SCREENSHOT_DIR"
echo "Screenshots → $SCREENSHOT_DIR"

# Take a silent (-x: no shutter sound) full-screen capture. The filename is
# zero-padded by sequence so directory listings sort chronologically.
__shot_seq=0
shoot() {
  local label="$1"
  __shot_seq=$((__shot_seq + 1))
  local fname
  fname=$(printf "%02d-%s.png" "$__shot_seq" "$(echo "$label" | tr ' /+' '-_-' | tr -d "'\"")")
  screencapture -x "$SCREENSHOT_DIR/$fname" 2>/dev/null || true
}

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
# Read the text view's content with a trailing "X" sentinel. Callers MUST
# use `${var%X}` to strip the sentinel after `$(...)` capture. This is
# the standard bash idiom for preserving trailing newlines through
# command substitution — `$(...)` strips trailing \n's from stdout, so a
# textView containing "hello\n" would otherwise read back as "hello"
# and produce false text✓ matches. The sentinel ensures \n's inside the
# real text are followed by a non-\n char and survive capture intact.
target_text() {
  curl -sf -m 2 "http://127.0.0.1:$TARGET_PORT/text" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['text'] + 'X', end='')"
}
target_clear_events() { curl -sf -m 2 -X POST "http://127.0.0.1:$TARGET_PORT/events/clear" >/dev/null; }
# Read NSTextView.selectedRange. Returns "<location> <length>" so the
# caller can split() in bash. Used by tests that check cursor movement
# (arrows) or selection state (cmd+A).
target_selection() {
  curl -sf -m 2 "http://127.0.0.1:$TARGET_PORT/selection" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['location'], d['length'])"
}
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

# Count keyDown events that match (keyCode, modifier-mask). Used by the key
# action cases: a "key" button should deliver a keyDown with the matching
# virtual keyCode; modifiers (Cmd/Shift/Option/Ctrl) must all be present in
# the event's modifierFlags (mask 0 disables the modifier check entirely).
# macOS modifier flag masks (NSEvent / CGEventFlags compatible high bits):
#   shift   0x00020000
#   ctrl    0x00040000
#   option  0x00080000
#   cmd     0x00100000
target_keycode_count() {
  local kc="$1"
  local modmask="${2:-0}"
  curl -sf -m 2 "http://127.0.0.1:$TARGET_PORT/events" | KC="$kc" MODS="$modmask" python3 -c "
import json, os, sys
kc = int(os.environ['KC'])
mods = int(os.environ['MODS'])
evs = json.load(sys.stdin)['events']
n = sum(1 for e in evs
        if e.get('keyCode') == kc
        and (mods == 0 or (e.get('modifierFlags', 0) & mods) == mods))
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
  # CRITICAL: pipe via `printf '%s'` instead of bash here-string `<<<`.
  # `<<<` appends a trailing newline that propagates onto the clipboard,
  # which silently breaks every selection-offset assertion (pre_text "hi"
  # becomes "hi\n" on paste, and every cursor position is +1 off).
  printf '%s' "$1" | python3 -c "
import sys
from AppKit import NSPasteboard
s = sys.stdin.read()
pb = NSPasteboard.generalPasteboard()
pb.clearContents()
pb.setString_forType_(s, 'public.utf8-plain-text')
" >/dev/null 2>&1
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
# the harness side. Must strip the sentinel X (see target_text comment).
wait_text_equals() {
  local want="$1"
  local _r
  for _ in $(seq 1 20); do
    _r=$(target_text)
    [ "${_r%X}" = "$want" ] && return 0
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

# Helper: read target text with sentinel stripped. Use as
#   _b=$(_baseline_text); ...
# When a value with trailing \n's is needed, callers must capture
# `target_text` directly and strip the sentinel themselves.
_baseline_text() {
  local _r=$(target_text)
  printf '%s' "${_r%X}"
}

# 1. Cmd+V: clipboard → text view. This is the OS-level paste path that
#    FloatingMacro depends on. If this fails, nothing else matters.
paste_and_wait "hello"
baseline_check "Cmd+V paste from clipboard"     "hello"   "$(_baseline_text)" || BASELINE_FAIL=1

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
baseline_check "Cmd+A → Cmd+X empties view"     ""        "$(_baseline_text)" || BASELINE_FAIL=1
baseline_check "Cmd+X puts cut text on clipboard" "hello" "$(ns_pbpaste)"     || BASELINE_FAIL=1

# 4. Cmd+V again must restore. This proves the round-trip is symmetric.
osa_combo "v" "command down"
wait_text_equals "hello"
baseline_check "Cmd+V restores cut text"        "hello"   "$(_baseline_text)" || BASELINE_FAIL=1

# 5. Multi-byte (Japanese) round-trip via clipboard.
prep_target
paste_and_wait "Japanese test"
baseline_check "Japanese paste round-trip"      "Japanese test" "$(_baseline_text)" || BASELINE_FAIL=1

# 6. Smart substitution MUST be off — straight quotes stay straight.
prep_target
paste_and_wait '"hi" -- ...'
baseline_check "no smart-substitution rewrite"  '"hi" -- ...' "$(_baseline_text)" || BASELINE_FAIL=1

# 7. Long paste (proves the responder chain isn't truncating). osa_set_clipboard
#    embeds the literal in an AppleScript string, so 500 chars is fine.
LONG_BL="$(python3 -c "print('X' * 500, end='')")"
prep_target
paste_and_wait "$LONG_BL"
baseline_check "500-char paste arrives intact"  "$LONG_BL" "$(_baseline_text)" || BASELINE_FAIL=1

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
  local _r
  for _ in $(seq 1 20); do
    _r=$(target_text)
    [ "${_r%X}" = "$expected" ] && break
    sleep 0.1
  done
  # One extra settle so any late paste still gets recorded before we read.
  sleep "$PASTE_SETTLE_SEC"

  shoot "text-${name}"

  local got
  _r=$(target_text); got="${_r%X}"

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
run_case "japanese"                                "Hello, World"                  "btn-test-japanese"
run_case "multiline"                               $'line one\nline two\nline three'   "btn-test-multiline"
run_case "slash command /compact"                  "/compact"                          "btn-test-slash"
run_case "punctuation that smart-subst would mangle" $'"quote" \'apos\' ... -- '       "btn-test-punct"
run_case "long 600-char paste"                     "$(python3 -c "print('A' * 600, end='')")"  "btn-test-long"
run_case "restoreClipboard=false"                  "without restore"                   "btn-test-norestore"

# --- Key-action cases ------------------------------------------------------
# The .key action path is structurally separate from .text — it builds a
# CGEvent for the resolved virtual keyCode + modifier mask instead of
# pasting via the clipboard. So a green light on text cases tells us
# nothing about whether key buttons actually deliver keystrokes.
#
# These cases assert: pressing a button whose action is .key(combo) causes
# fm-test-target to receive a keyDown with the expected (keyCode, modifier)
# tuple. Buttons live in the debug preset under group-debug; if they go
# missing (manual deletion, fresh user profile), recreate them with:
#
#   button_add  groupId=group-debug  button={id:btn-test-key-f5,    action:{type:key, combo:"f5"}}
#   button_add  groupId=group-debug  button={id:btn-test-key-down,  action:{type:key, combo:"down"}}
#   button_add  groupId=group-debug  button={id:btn-test-key-cmd-a, action:{type:key, combo:"cmd+a"}}
#
# keyCode references (from KeyCombo.swift):
#   f5    = 0x60 (96)
#   down  = 0x7D (125)
#   a     = 0x00 (0), with cmd modifier mask 0x00100000

# Run a key-action case. Two-axis verification:
#   key✓: did fm-test-target receive a keyDown matching (kc, modmask)?
#   text✓: did the resulting text match the expected post-press content?
#
# A pre-paste step seeds the text field with content so keys that move/
# delete/insert are observable. Without seed text, a "delete" or "down"
# press arrives at an empty buffer and produces no observable change.
#
# Args: name button_id expected_kc modmask [pre_text] [expected_text_after]
#   pre_text:            seed via Cmd+V before the press (cursor lands at end)
#   expected_text_after: required final state of the text field (skip text
#                        check if empty — appropriate for cursor-only ops
#                        like arrows / cmd+A where text is unchanged but
#                        the visible cursor / selection IS the effect, and
#                        the screenshot is what verifies that visually).
#
# Important: Escape is sent BEFORE clearing the event log. This dismisses
# any lingering IME composition or Fn overlay the previous case left
# active — without it, the OS may eat the next keystroke before it
# reaches fm-test-target's local NSEvent monitor.
run_key_case() {
  local name="$1"
  local button_id="$2"
  local expected_kc="$3"
  local modmask="${4:-0}"
  local pre_text="${5:-}"
  local expect_text="${6:-__SKIP__}"
  # Optional: "<location> <length>" string to assert against /selection.
  # Pass "__SKIP__" (or omit) to skip the selection check. This is the
  # main verification axis for cursor-only operations like arrows and
  # Cmd+A — a number-equality check is a much firmer signal than a
  # screenshot for whether the cursor actually moved or text was selected.
  local expect_selection="${7:-__SKIP__}"

  target_focus
  target_clear
  sleep "$SETTLE"
  osa_key_code 53     # Escape — flushes IME composition state
  sleep 0.3

  # Seed text if requested — paste through clipboard so the cursor is left
  # at the END of the seed. Subsequent backspace removes the last seed
  # char, return appends a newline, etc.
  if [ -n "$pre_text" ]; then
    osa_set_clipboard "$pre_text"
    wait_clipboard_equals "$pre_text" || true
    osa_combo "v" "command down"
    wait_text_equals "$pre_text" || true
  fi

  target_clear_events
  sleep 0.1

  fm_press "$button_id"

  # Spin-wait up to ~2s for the keyDown to land.
  local got_n=0
  for _ in $(seq 1 20); do
    got_n="$(target_keycode_count "$expected_kc" "$modmask")"
    [ "$got_n" -gt 0 ] && break
    sleep 0.1
  done
  sleep "$PASTE_SETTLE_SEC"
  shoot "key-${name}"
  got_n="$(target_keycode_count "$expected_kc" "$modmask")"

  local key_ok=0 text_ok=0 text_check=0
  local sel_ok=0 sel_check=0
  [ "$got_n" -gt 0 ] && key_ok=1
  if [ "$expect_text" != "__SKIP__" ]; then
    text_check=1
    local actual _r
    _r=$(target_text); actual="${_r%X}"
    [ "$actual" = "$expect_text" ] && text_ok=1
  fi
  if [ "$expect_selection" != "__SKIP__" ]; then
    sel_check=1
    local actual_sel
    actual_sel="$(target_selection)"
    [ "$actual_sel" = "$expect_selection" ] && sel_ok=1
  fi

  local key_tag text_tag sel_tag
  if [ $key_ok -eq 1 ]; then key_tag="\033[32mkey✓\033[0m"; else key_tag="\033[31mkey✗\033[0m"; fi
  if [ $text_check -eq 1 ]; then
    if [ $text_ok -eq 1 ]; then text_tag="\033[32mtext✓\033[0m"; else text_tag="\033[31mtext✗\033[0m"; fi
  else
    text_tag="text-"
  fi
  if [ $sel_check -eq 1 ]; then
    if [ $sel_ok -eq 1 ]; then sel_tag="\033[32msel✓\033[0m"; else sel_tag="\033[31msel✗\033[0m"; fi
  else
    sel_tag="sel-"
  fi

  printf "  [%b %b %b] %s\n" "$key_tag" "$text_tag" "$sel_tag" "$name"

  local case_ok=1
  if [ $key_ok -eq 0 ]; then
    case_ok=0
    printf "        keyCode=%d mods=0x%08x  NOT received\n" "$expected_kc" "$modmask"
    printf "        last keyDowns:\n"
    curl -sf "http://127.0.0.1:$TARGET_PORT/events" | python3 -c "
import json, sys
for e in json.load(sys.stdin)['events'][-10:]:
    print(f'          kc={e[\"keyCode\"]:>3}  mods=0x{e[\"modifierFlags\"]:08x}  chars={e[\"characters\"]!r}')" || true
  fi
  if [ $text_check -eq 1 ] && [ $text_ok -eq 0 ]; then
    case_ok=0
    local actual _r
    _r=$(target_text); actual="${_r%X}"
    printf "        expected text (%d): %q\n" "${#expect_text}" "$expect_text"
    printf "        got text      (%d): %q\n" "${#actual}"      "$actual"
  fi
  if [ $sel_check -eq 1 ] && [ $sel_ok -eq 0 ]; then
    case_ok=0
    local actual_sel
    actual_sel="$(target_selection)"
    printf "        expected selection (loc len): %s\n" "$expect_selection"
    printf "        got selection      (loc len): %s\n" "$actual_sel"
  fi

  if [ $case_ok -eq 1 ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("$name")
  fi
}

echo
echo "Running key-action cases (with pre-pasted seed + selection assertions)..."

# Verification axes per case:
#   key✓: did fm-test-target receive a keyDown matching (kc, modmask)?
#   text✓: did the text content match expectation after the key fired?
#   sel✓: did the cursor / selection range land at the expected location?
# All three signals together pin down whether the key was delivered AND
# the OS applied the correct semantics (responder dispatched it, not
# silently swallowed by IME or a system overlay).

# delete (= backspace, kc=51): seed "abcdef" → cursor at 6 → backspace
# removes 'f' → text "abcde", cursor at 5.
run_key_case "key delete (backspace)" \
  "btn-test-key-delete"  51   0  "abcdef"  "abcde"  "5 0"

# tab (kc=48): seed "hi" → cursor at 2 → tab inserts → text "hi\t",
# cursor at 3.
run_key_case "key tab" \
  "btn-test-key-tab"     48   0  "hi"      $'hi\t'   "3 0"

# return (kc=36): seed "hello" → cursor at 5 → return inserts newline →
# text "hello\n", cursor at 6.
run_key_case "key return" \
  "btn-test-key-return"  36   0  "hello"   $'hello\n'  "6 0"

# left arrow (kc=123): seed "abcdef" → cursor at 6 → left moves cursor
# back one char → text unchanged, selection "5 0". This is the cleanest
# arrow-key test because behavior is unambiguous regardless of column
# tracking or end-of-document edge cases.
run_key_case "key left arrow" \
  "btn-test-key-left"    123  0  "abcdef"  "abcdef"   "5 0"

# down arrow (kc=125): seed multi-line text. After paste cursor is at
# end-of-doc (loc=17). Pressing down at end-of-doc is a no-op in
# NSTextView so selection stays "17 0". This still verifies the keyDown
# was delivered (key✓) — the more useful selection-change is covered by
# the left arrow case above.
run_key_case "key down arrow" \
  "btn-test-key-down"    125  0  $'line1\nline2\nline3'  $'line1\nline2\nline3'  "17 0"

# cmd+a (kc=0 + cmd flag 0x00100000): seed "selectme" (8 chars) →
# select-all → text unchanged, selection covers the whole field
# starting at location 0, length 8.
run_key_case "key cmd+a (select-all)" \
  "btn-test-key-cmd-a"   0    $((0x100000))  "selectme"  "selectme"  "0 8"

# --- Summary ---------------------------------------------------------------
echo
echo "Result: $PASS passed, $FAIL failed."
echo "Screenshots: $SCREENSHOT_DIR"
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
