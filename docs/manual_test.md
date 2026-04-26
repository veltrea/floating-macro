# FloatingMacro — Manual Test Checklist

This checklist covers items **not reachable by the automated test suite**:
things that require Accessibility / Automation permissions, real window
behavior, human visual judgment, or live Control API calls against a running GUI process.

Run through this after `swift test` and `scripts/fmcli_smoke.sh` are all green.

> 日本語版: [manual_test.ja.md](manual_test.ja.md)

---

## What the automated tests already cover (skip here)

- `FloatingMacroCore` logic (actions, key combos, executors, macro runner)
- Clipboard save/restore fidelity
- Config read/write + defaults generation
- `fmcli` permission-free surface (help, config, preset list, launch shell:, error exit codes)

## What this document covers

1. Real **key synthesis / text paste / terminal launch** behavior (requires macOS permissions)
2. **NSPanel / SwiftUI** window look and feel (hard to automate)
3. **Clipboard restoration** — visual confirmation
4. **Control API (HTTP)** — all endpoints, validated in realistic sequential scenarios

---

## Pre-flight

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` must succeed.
2. Build the product:
   - **CLI only**: `swift build --product fmcli`
   - **GUI included**: `swift build --product FloatingMacro` or `swift run FloatingMacro`
3. Accessibility permission granted to the binary (System Settings → Privacy & Security → Accessibility).
4. To keep your real config directory untouched, export a temp path before launching:
   ```
   export FLOATINGMACRO_CONFIG_DIR=/tmp/fmtest-$$
   ```
5. **Enable the Control API** (required for Section 3 only):
   ```json
   // ~/Library/Application Support/FloatingMacro/config.json
   { "controlAPI": { "enabled": true } }
   ```
   After launching, look for `ControlServer Started on 127.0.0.1:17430` in the log.

---

## 1. CLI: `fmcli action` series (Accessibility required)

Open a text editor (for example TextEdit) with an empty document and the caret active.

### 1-1. `fmcli action key`

| Step | Expected |
|---|---|
| Run `fmcli action key "cmd+shift+4"` | Screenshot reticle appears |
| Run `fmcli action key "f5"` | Same behavior as pressing F5 |
| Run `fmcli action key "cmd+space"` | Spotlight opens (environment-dependent) |

### 1-2. `fmcli action text`

| Step | Expected |
|---|---|
| Copy some arbitrary text (e.g. "PRE-TEST") | Clipboard contains "PRE-TEST" |
| Run `fmcli action text "Hello 🌏"` | The text appears at the caret |
| Press Cmd+V again | **"PRE-TEST"** is pasted (confirming clipboard restoration) |
| Run `fmcli action text "line1\nline2"` (escape the newline properly in your shell) | Two separate lines are pasted |

### 1-3. `fmcli action terminal`

| Step | Expected |
|---|---|
| `fmcli action terminal --app Terminal --command "echo hello"` | Terminal.app opens and runs `echo hello` |
| `fmcli action terminal --app iTerm --command "ls ~"` | iTerm2 (if installed) opens a new window and runs `ls ~` |
| `fmcli action terminal --app Terminal --command "date" --no-execute` | `date` is typed into Terminal but Enter is NOT pressed |

### 1-4. `fmcli preset run`

After `fmcli config init` creates the default preset:

| Step | Expected |
|---|---|
| Focus TextEdit | — |
| `fmcli preset run default btn-ultrathink` | The default AI prompt text is pasted |
| `fmcli preset run default btn-stop-loop` | The "pause" prompt text is pasted |

---

## 2. GUI: Floating panel

Launch with `swift run FloatingMacro`.

### 2-1. First launch / permissions

- [ ] No Dock icon appears (`NSApp.setActivationPolicy(.accessory)`)
- [ ] A `command.square` SF Symbol appears in the menu bar
- [ ] If Accessibility is not granted, a modal pops up
- [ ] The modal's "Open System Settings" button opens the Privacy pane

### 2-2. Window basics

- [ ] The floating panel appears at the configured origin
- [ ] Clicking another app keeps the panel in front (`.floating` level)
- [ ] Clicking the panel does **not** steal focus from the active app
  - Verification: focus TextEdit with caret → click panel → type into TextEdit → text appears

### 2-3. Drag

- [ ] Drag by empty space inside the panel moves it freely on-screen
- [ ] Cannot be dragged past the screen edge (standard macOS behavior)
- [ ] After relaunch, the panel appears at the previous location (`applicationWillTerminate` writes config)

### 2-4. Button behavior

- [ ] The default preset's "ultrathink" button is visible
- [ ] Hovering slightly tints the background
- [ ] With TextEdit focused, clicking "ultrathink" pastes the default prompt
- [ ] Clicking a group header ("AI") collapses / expands the group

### 2-5. Menu bar

- [ ] Clicking the menu bar icon shows: "Show / Hide", "Preset", "Button Edit…", "Open config folder", "Reload", "Quit"
- [ ] "Show / Hide" toggles panel visibility
- [ ] "Open config folder" opens `~/Library/Application Support/FloatingMacro` in Finder
- [ ] "Button Edit…" (or `⌘E`) opens the Settings window
- [ ] "Quit" terminates the app cleanly

### 2-6. Preset switching

1. Create `~/Library/Application Support/FloatingMacro/presets/writing.json` with:
   ```json
   {
     "version": 1,
     "name": "writing",
     "displayName": "Writing",
     "groups": [
       { "id": "g1", "label": "Snippets", "buttons": [
         { "id": "b1", "label": "Hello", "iconText": "✍️",
           "action": { "type": "text", "content": "Hello, and thanks." }
         }
       ]}
     ]
   }
   ```
2. Menu bar → "Reload"
3. Menu bar → "Preset" → "writing"
- [ ] Panel updates to show the Writing preset with only the "Hello" button
- [ ] Switching back to "default" restores the original buttons

### 2-7. Error banner

1. Add a button whose action is a bad key combo (e.g. `{"type":"key","combo":"cmd+xyz"}`).
2. Reload and click that button.
- [ ] A red banner appears below the buttons
- [ ] The banner auto-dismisses after ~3 seconds

---

## 3. Control API — Sequential scenario tests

> **The steps in this section form a single continuous flow and must be executed in order.**
> Each step assumes the result of the one before it. Skipping or reordering will break the scenario.

The app must be running with `controlAPI.enabled: true` (see Pre-flight step 5).

### 3-0. Environment variable

```bash
BASE="http://127.0.0.1:17430"
```

All `curl` commands below use `$BASE`. Always include `-H 'Content-Type: application/json'` when passing a `-d` body.

---

### 3-1. Session start sequence

Run this before anything else in this section.

```bash
# ① Server reachability
curl -s $BASE/ping
# → {"ok":true,"product":"FloatingMacro"}
```
- [ ] `ok: true` is returned (timeout or connection refused → check config and launch log)

```bash
# ② App state snapshot
curl -s $BASE/state | jq
# → JSON containing panel visibility, active preset name, window geometry, etc.
```
- [ ] Valid JSON is returned (no parse errors)

```bash
# ③ Manifest — verify all tools are listed
curl -s $BASE/manifest | jq '[.tools[].name]'
# → Array of all tool names
```
- [ ] Recent tools such as `arrange`, `settings_commit`, `settings_set_key_combo` appear in the list

```bash
# ④ Arrange windows so they don't overlap (also opens Settings)
curl -s -X POST $BASE/arrange \
    -H 'Content-Type: application/json' \
    -d '{"open_settings": true}' | jq
# → {"panel":{"x":...,"y":...},"settings":{"x":...,"y":...}}
```
- [ ] The floating panel and Settings window are on screen without overlapping
- [ ] The Settings window is open

---

### 3-2. Create the test preset and build its structure

> **⚠️ This test preset (`test-api`) is created here and deleted in 3-8. Steps 3-2 through 3-7 operate on it.**

```bash
# ⑤ Baseline preset list
curl -s $BASE/preset/list | jq
```

```bash
# ⑥ Create the test preset
curl -s -X POST $BASE/preset/create \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api","displayName":"API Test"}' | jq
```
- [ ] No error

```bash
# ⑦ Switch to the test preset (makes it the target for subsequent mutations)
curl -s -X POST $BASE/preset/switch \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api"}' | jq
```
- [ ] The panel becomes empty (zero buttons)

```bash
# ⑧ Add the main group
curl -s -X POST $BASE/group/add \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main","label":"Main Group"}' | jq

# ⑨ Add a secondary group (target for button_move later; starts collapsed)
curl -s -X POST $BASE/group/add \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-sub","label":"Sub Group","collapsed":true}' | jq
```
- [ ] Panel shows "Main Group" and a collapsed "Sub Group"

```bash
# ⑩ Add a button to the main group
curl -s -X POST $BASE/button/add \
    -H 'Content-Type: application/json' \
    -d '{
      "groupId": "g-main",
      "button": {
        "id": "btn-test",
        "label": "Test",
        "iconText": "🧪",
        "action": {"type":"text","content":"API test passed"}
      }
    }' | jq
```
- [ ] A "🧪 Test" button appears in the panel

```bash
# ⑪ Verify the preset structure
curl -s $BASE/preset/current | jq '.preset.groups[] | {id,label,buttons:[.buttons[].id]}'
# → g-main contains btn-test; g-sub is empty
```

```bash
# ⑫ Smoke-test the button (focus TextEdit first)
# Click the "Test" button on the floating panel
```
- [ ] "API test passed" is pasted into TextEdit

---

### 3-3. Button and group API mutations

> Continuing from 3-2. `test-api` is still active.

```bash
# ⑬ Update button label and icon
curl -s -X POST $BASE/button/update \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test","label":"Tested","iconText":"✅"}' | jq
```
- [ ] The panel button changes to "✅ Tested"

```bash
# ⑭ Add a second button so reorder can be verified
curl -s -X POST $BASE/button/add \
    -H 'Content-Type: application/json' \
    -d '{
      "groupId": "g-main",
      "button": {
        "id": "btn-dummy",
        "label": "Dummy",
        "action": {"type":"text","content":"dummy"}
      }
    }' | jq

# ⑮ Reverse the button order
curl -s -X POST $BASE/button/reorder \
    -H 'Content-Type: application/json' \
    -d '{"groupId":"g-main","ids":["btn-dummy","btn-test"]}' | jq
```
- [ ] "Dummy" is now above "Tested" in the panel

```bash
# ⑯ Move btn-dummy to the sub group
curl -s -X POST $BASE/button/move \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-dummy","toGroupId":"g-sub","position":0}' | jq
```
- [ ] Expanding "Sub Group" reveals "Dummy"

```bash
# ⑰ Update the sub group (rename + expand)
curl -s -X POST $BASE/group/update \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-sub","label":"Sub (expanded)","collapsed":false}' | jq
```
- [ ] The group header updates and the group is expanded

```bash
# ⑱ Delete the main group (must move its button out first)
curl -s -X POST $BASE/button/move \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test","toGroupId":"g-sub"}' | jq

curl -s -X POST $BASE/group/delete \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main"}' | jq
```
- [ ] "Main Group" disappears from the panel

```bash
# ⑲ Recreate g-main and move btn-test back (needed for Settings tests below)
curl -s -X POST $BASE/group/add \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main","label":"Main Group"}' | jq

curl -s -X POST $BASE/button/move \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test","toGroupId":"g-main","position":0}' | jq
```

```bash
# ⑳ Smoke-test preset_reload (re-reads from disk; state should be unchanged)
curl -s -X POST $BASE/preset/reload | jq
```
- [ ] No error; panel display is maintained

```bash
# ㉑ Rename the preset's display name
curl -s -X POST $BASE/preset/rename \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api","displayName":"API Test v2"}' | jq
```
- [ ] The menu bar preset list shows "API Test v2"

---

### 3-4. Button editing via the Settings UI

> The Settings window is already open (from step ④ in 3-1).
> This section validates the full `select → edit → commit → clear` flow.

```bash
# ㉒ Select btn-test in Settings (opens ButtonEditor)
curl -s -X POST $BASE/settings/select-button \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test"}' | jq
```
- [ ] The ButtonEditor pane expands in the right side of the Settings window

```bash
# ㉓ Switch action type to text
curl -s -X POST $BASE/settings/set-action-type \
    -H 'Content-Type: application/json' \
    -d '{"type":"text"}' | jq

# ㉔ Set the text content
curl -s -X POST $BASE/settings/set-action-value \
    -H 'Content-Type: application/json' \
    -d '{"type":"text","value":"Written via Settings API"}' | jq
```
- [ ] The text field in ButtonEditor shows the new content

```bash
# ㉕ Set background color (live preview — before Save)
curl -s -X POST $BASE/settings/set-background-color \
    -H 'Content-Type: application/json' \
    -d '{"color":"#1A73E8"}' | jq
```
- [ ] The panel button background turns blue `#1A73E8` immediately (before saving)

```bash
# ㉖ Set text color to white
curl -s -X POST $BASE/settings/set-text-color \
    -H 'Content-Type: application/json' \
    -d '{"color":"#FFFFFF"}' | jq
```
- [ ] The panel button label turns white immediately (before saving)

```bash
# ㉗ Save changes (equivalent to clicking the Save button)
curl -s -X POST $BASE/settings/commit | jq

# ㉘ Deselect (collapses ButtonEditor)
curl -s -X POST $BASE/settings/clear-selection | jq
```
- [ ] The ButtonEditor closes and returns to the empty-state placeholder
- [ ] The blue button and white text persist after saving

```bash
# ㉙ Confirm via API
curl -s $BASE/preset/current | jq '.preset.groups[0].buttons[0] | {label,backgroundColor,textColor,action}'
# → backgroundColor: "#1A73E8", textColor: "#FFFFFF", action.content: "Written via Settings API"
```

---

### 3-5. Group editing via the Settings UI

> Continuing from 3-4. Settings window is open.

```bash
# ㉚ Select g-main in Settings (opens GroupEditor)
curl -s -X POST $BASE/settings/select-group \
    -H 'Content-Type: application/json' \
    -d '{"id":"g-main"}' | jq
```
- [ ] The GroupEditor pane opens on the right

```bash
# ㉛ Set group background color
curl -s -X POST $BASE/settings/set-background-color \
    -H 'Content-Type: application/json' \
    -d '{"color":"#34A853"}' | jq
```
- [ ] The group header background turns green immediately

```bash
# ㉜ Save and deselect
curl -s -X POST $BASE/settings/commit | jq
curl -s -X POST $BASE/settings/clear-selection | jq
```
- [ ] The green group header persists after saving

---

### 3-6. Picker sheet open/close flow

> Continuing from 3-5. Settings window is open.

```bash
# ㉝ Select btn-test, then open the app-icon picker
curl -s -X POST $BASE/settings/select-button \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test"}' | jq

curl -s -X POST $BASE/settings/open-app-icon-picker | jq
```
- [ ] An app-icon picker sheet overlays the Settings window

```bash
# ㉞ Dismiss without selecting
curl -s -X POST $BASE/settings/dismiss-picker | jq
```
- [ ] The sheet closes; ButtonEditor is visible again

```bash
# ㉟ Open the SF Symbol picker (settings_open_sf_picker also opens Settings if closed)
curl -s -X POST $BASE/settings/open-sf-picker | jq
```
- [ ] The SF Symbol picker sheet appears

```bash
# ㊱ Dismiss
curl -s -X POST $BASE/settings/dismiss-picker | jq
curl -s -X POST $BASE/settings/clear-selection | jq
```

---

### 3-7. Key combo configuration flow

> Continuing from 3-6.

```bash
# ㊲ Re-select btn-test
curl -s -X POST $BASE/settings/select-button \
    -H 'Content-Type: application/json' \
    -d '{"id":"btn-test"}' | jq

# ㊳ Set a key combo (automatically switches the action type tab to "key")
curl -s -X POST $BASE/settings/set-key-combo \
    -H 'Content-Type: application/json' \
    -d '{"combo":"cmd+shift+4"}' | jq
```
- [ ] The action type tab switches to "Key" in ButtonEditor
- [ ] The key combo field shows `⌘⇧4` (or equivalent display)

```bash
# ㊴ Save and deselect
curl -s -X POST $BASE/settings/commit | jq
curl -s -X POST $BASE/settings/clear-selection | jq
```

```bash
# ㊵ Confirm via API
curl -s $BASE/preset/current | jq '.preset.groups[0].buttons[0].action'
# → {"type":"key","combo":"cmd+shift+4"}
```

---

### 3-8. Cleanup — delete the test preset

> Run after 3-7. Restores the environment to baseline.

```bash
# ㊶ Switch back to the default preset
curl -s -X POST $BASE/preset/switch \
    -H 'Content-Type: application/json' \
    -d '{"name":"default"}' | jq
```
- [ ] The panel shows the default preset buttons again

```bash
# ㊷ Delete the test preset
curl -s -X POST $BASE/preset/delete \
    -H 'Content-Type: application/json' \
    -d '{"name":"test-api"}' | jq

# ㊸ Confirm deletion
curl -s $BASE/preset/list | jq '[.[].name]'
# → "test-api" must not appear
```
- [ ] `test-api` is absent from the list

---

### 3-9. Window operation sequence

> Test the floating panel's window API after the preset cleanup.

```bash
# ㊹ Reduce opacity
curl -s -X POST $BASE/window/opacity \
    -H 'Content-Type: application/json' \
    -d '{"value":0.4}' | jq
```
- [ ] The panel becomes semi-transparent (~40%)

```bash
# ㊺ Move the panel
curl -s -X POST $BASE/window/move \
    -H 'Content-Type: application/json' \
    -d '{"x":300,"y":300}' | jq

# ㊻ Resize the panel
curl -s -X POST $BASE/window/resize \
    -H 'Content-Type: application/json' \
    -d '{"width":220,"height":320}' | jq
```
- [ ] The panel is at the specified position and size

```bash
# ㊼ Hide the panel
curl -s -X POST $BASE/window/hide | jq
```
- [ ] The panel disappears from the screen

```bash
# ㊽ Toggle it back
curl -s -X POST $BASE/window/toggle | jq
```
- [ ] The panel reappears

```bash
# ㊾ Restore full opacity
curl -s -X POST $BASE/window/opacity \
    -H 'Content-Type: application/json' \
    -d '{"value":1.0}' | jq
```

---

### 3-10. Direct action execution + log verification

> Open TextEdit with the caret active before running these steps.

```bash
# ㊿ Paste text via run_action (with clipboard restoration)
# First copy something to the clipboard (e.g. "PREV")
curl -s -X POST $BASE/action \
    -H 'Content-Type: application/json' \
    -d '{"type":"text","content":"Pasted directly via API","restoreClipboard":true}' | jq
```
- [ ] "Pasted directly via API" appears in TextEdit
- [ ] Pressing Cmd+V returns the original clipboard content ("PREV")

```bash
# 51. Check for errors in the log
curl -s "$BASE/log/tail?since=30s&level=warn" | jq '.events | length'
# → 0 (zero warn-or-above events)
```

```bash
# 52. Send a key shortcut (Undo in TextEdit)
curl -s -X POST $BASE/action \
    -H 'Content-Type: application/json' \
    -d '{"type":"key","combo":"cmd+z"}' | jq
```
- [ ] TextEdit undoes the text insertion

```bash
# 53. Fetch an app icon (Safari)
curl -s "$BASE/icon/for-app?bundleId=com.apple.Safari" | jq '{mimeType,iconSize:(.icon|length)}'
# → {mimeType:"image/png", iconSize: <large number>}
```
- [ ] A base64 PNG is returned (`iconSize` should exceed 1000)

---

### 3-11. Settings window management

```bash
# 54. Close Settings (start clean)
curl -s -X POST $BASE/settings/close | jq

# 55. Re-open it
curl -s -X POST $BASE/settings/open | jq
```
- [ ] The Settings window opens

```bash
# 56. Move the Settings window
curl -s -X POST $BASE/settings/move \
    -H 'Content-Type: application/json' \
    -d '{"x":150,"y":350}' | jq
```
- [ ] The Settings window moves to the specified coordinates

```bash
# 57. Close it again
curl -s -X POST $BASE/settings/close | jq
```
- [ ] The Settings window closes

```bash
# 58. Final error log check — the entire section should be clean
curl -s "$BASE/log/tail?since=10m&level=error" | jq '.events'
# → [] (empty array)
```

---

## 4. Security sanity checks (important)

- [ ] After running `fmcli action text "$(cat /etc/hostname)"`, `pbpaste` returns the original clipboard content (clipboard fully restored).
- [ ] Put a secret (password, API key) on the clipboard, run `fmcli action text "dummy"`, then paste elsewhere — the original secret is back, not the dummy.

---

## 5. High-risk regressions (verify per release)

- [ ] IME-on state: `fmcli action text "あいう"` pastes correctly (clipboard path is used, so IME state should not matter).
- [ ] Panel remains usable across both monitors in a multi-display setup.
- [ ] Panel follows the user across Spaces (`.canJoinAllSpaces`).
- [ ] Panel remains visible over a full-screen app (`.fullScreenAuxiliary`).
- [ ] With Control API enabled, relaunching the app keeps `controlAPI.enabled` and `GET /ping` responds.
- [ ] After `settings_set_background_color` + `commit` + app relaunch, the button color is preserved.

---

## 6. Troubleshooting table

| Symptom | Likely cause | Check |
|---|---|---|
| Keys are not registered | Accessibility not granted | `fmcli permissions check` |
| `action terminal` does nothing | Automation not granted / app not installed | System Settings → Automation, `ls /Applications/` |
| Text corruption | Probably quoting issues at the shell | Inspect the JSON definition directly |
| Clipboard not restored | `restoreClipboard: false`, or executor crashed | Check logs |
| Panel vanished | Hidden from menu bar | Menu bar → "Show / Hide" |
| `GET /ping` times out | `controlAPI.enabled` is false or port conflict | Check `config.json`; look for `ControlServer Started` in launch log |
| `settings_commit` errors | ButtonEditor / GroupEditor is not open | Call `settings_select_button` or `settings_select_group` first |
| `group_add` fails | Unsaved edits in the Settings UI | Call `settings_commit` or `settings_clear_selection` first, then retry |
| `button_update` fails | `id` does not exist | Call `preset_current` to confirm the correct id |
| `preset_switch` doesn't update the panel | Render timing | Call `preset_reload` to force a refresh |

---

## 7. Passing criteria

Consider manual testing complete when all ☑ items above are ticked.
Any failure caught here should be converted into an automated test if reproducible in isolation — the goal is for this checklist to keep shrinking over time.
