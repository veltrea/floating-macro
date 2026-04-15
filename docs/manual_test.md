# FloatingMacro — Manual Test Checklist

This checklist covers items **not reachable by the automated test suite**:
things that require Accessibility / Automation permissions, real window
behavior, or human visual judgment.

Run through this after `swift test`, `fmcli_smoke.sh` and
`control_api_smoke.sh` are all green.

> 日本語版: [manual_test.ja.md](manual_test.ja.md)

---

## What the automated tests already cover (skip here)

- `FloatingMacroCore` logic (actions, key combos, executors, macro runner)
- Clipboard save/restore fidelity
- Config read/write + defaults generation
- `fmcli` permission-free surface (help, config, preset list, launch shell:, log tail, error exit codes)
- Control API (REST + `/tools/call` + `/mcp`) against a real GUI process

## What this document covers

1. Real **key synthesis / text paste / terminal launch** behavior (requires macOS permissions)
2. **NSPanel / SwiftUI** window look and feel (hard to automate)
3. **Clipboard restoration** — visual confirmation

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

- [ ] No Dock icon appears (LSUIElement-like behavior via `NSApp.setActivationPolicy(.accessory)`)
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
- [ ] After relaunch, the panel appears at the previous location (config is written on `applicationWillTerminate`)

### 2-4. Button behavior

- [ ] The default preset's "ultrathink" button is visible
- [ ] Hovering slightly tints the background
- [ ] With TextEdit focused, clicking "ultrathink" pastes the default prompt
- [ ] Clicking a group header ("AI") collapses / expands the group

### 2-5. Menu bar

- [ ] Clicking the menu bar icon shows: "Show / Hide", "Preset", "Button Edit…", "Open config folder", "Reload", "Quit"
- [ ] "Show / Hide" toggles panel visibility
- [ ] "Open config folder" opens `~/Library/Application Support/FloatingMacro` in Finder
- [ ] "Button Edit…" (or `⌘E`) opens the settings window
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
- [ ] Panel updates to show the Writing preset
- [ ] Switching back to "default" restores the original buttons

### 2-7. Error banner

1. Add a button whose action is a bad key combo (e.g. `{"type":"key","combo":"cmd+xyz"}`).
2. Reload and click that button.
- [ ] A red banner appears below the buttons
- [ ] The banner auto-dismisses after ~3 seconds

---

## 3. Security sanity checks (important)

- [ ] After running `fmcli action text "$(cat /etc/hostname)"`, `pbpaste` returns the original clipboard content (clipboard fully restored).
- [ ] Put a secret (a password, API key) on the clipboard, run `fmcli action text "dummy"`, then paste elsewhere — the original secret is back, not the dummy.

---

## 4. High-risk regressions (verify per release)

- [ ] IME-on state: `fmcli action text "あいう"` pastes correctly (the design avoids the keycode synthesizer, so IME state should not matter).
- [ ] Panel remains usable across both monitors in a multi-display setup.
- [ ] Panel follows the user across Spaces (`.canJoinAllSpaces`).
- [ ] Panel remains visible over a full-screen app (`.fullScreenAuxiliary`).

---

## 5. Troubleshooting table

| Symptom | Likely cause | Check |
|---|---|---|
| Keys are not registered | Accessibility not granted | `fmcli permissions check` |
| `action terminal` does nothing | Automation not granted / Terminal / iTerm not installed | System Settings → Automation, `ls /Applications/` |
| Text corruption | Probably quoting issues at the shell | Inspect the JSON definition directly |
| Clipboard not restored | `restoreClipboard: false`, or `TextActionExecutor` crashed mid-flight | Check logs |
| Panel vanished | User hid it from the menu bar | Menu bar → "Show / Hide" |

---

## 6. Passing criteria

Consider manual testing complete when all ☑ items above are ticked.
Any failure caught here should be filed as an automated test if it is
reproducible in isolation, so the manual checklist keeps shrinking over time.
