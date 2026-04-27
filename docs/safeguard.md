# Command Safeguard

FloatingMacro can insert text and run commands in a terminal with a single button press.
When an AI agent is driving the app, this creates a risk: a malicious or mistaken command
(e.g. `rm -rf`) could be executed without the user's knowledge.
The **Command Safeguard** feature mitigates that risk.

> 日本語版: [safeguard.ja.md](safeguard.ja.md)

---

## How it works

Immediately before a command or text is sent to the terminal, it is checked against a list
of **forbidden patterns**.

| Situation | Behavior |
|---|---|
| No pattern matches | Execute without interruption |
| A pattern matches | Show a **confirmation dialog** — the user decides |
| Autopilot mode is enabled | Execute without a dialog even when a pattern matches |

Every execution path is covered:

- **terminal actions** triggered by button clicks (the command string)
- **text actions** triggered by button clicks (text pasted into the focused window)
- Sub-steps inside **macros**
- Commands sent by an AI through the **Control API** (`POST /action`)

The same rules apply regardless of origin.

---

## Opening the settings

Menu bar icon → **"Button Edit…"** → **"Security" tab** at the top of the window.

---

## Confirmation dialog

When a matching command is about to run, a dialog like this appears:

```
Dangerous command detected

The forbidden pattern "rm -rf" was found.

rm -rf /some/path

Do you want to proceed?

[ Cancel ]  [ Execute ]
```

- **"Cancel"** (default — pressing Return selects this) → the command is aborted
- **"Execute"** → the command runs as normal

> **Note:** "Cancel" is the default button. Accidentally pressing Return will stop the command, not run it.

---

## Forbidden patterns

Patterns are matched as **case-insensitive substrings**.
Registering `rm -rf` will also catch `RM -RF /home`.

### Default patterns

| Pattern | Intended threat |
|---|---|
| `rm -rf` / `rm -fr` | Recursive directory deletion |
| `sudo rm` | Root-level deletion |
| `> /dev/` | Direct write to a device node |
| `dd if=/dev/` | Disk copy / destruction via `dd` |
| `mkfs` | Filesystem re-format |
| `:(){ :|:& };:` | Fork bomb |
| `chmod -R 777` / `chmod 777 /` | World-writable permission dump |
| `sudo chmod` | Root-level permission change |
| `shred ` | Secure file overwrite |
| `wipefs` | Partition signature erasure |
| `diskutil eraseDisk` / `diskutil zeroDisk` | macOS disk initialisation |
| `format c:` | Windows drive format |

### Adding, editing, and removing patterns

Use the **"Confirmation pattern list"** section inside the Security tab.

**Add**
: Type a pattern into the text field and click "Add" (or press Enter).

**Edit**
: Click the "Edit" button on a row, change the text, then click "Confirm".

**Delete**
: Click the trash icon on a row.

**Restore defaults**
: Click "Restore default patterns" to replace the entire list with the 15 built-in entries.

All changes are saved immediately and persist across restarts.

---

## Disabling the safeguard entirely

Turning off the "Enable confirmation dialog" toggle disables pattern matching altogether.
**Even when you want to give an AI full autonomy, Autopilot mode is the recommended approach**
over disabling the safeguard — Autopilot requires a password, which prevents accidental deactivation.

---

## Autopilot mode

Autopilot mode is designed for workflows where you want to give an AI agent full execution
authority without any interruptions.
While this mode is active, commands are executed immediately even when they match a forbidden
pattern — no dialog is shown.

**Enabling autopilot requires a password.** This prevents an AI running in the background
from switching the mode on programmatically.

### Setting a password (first time)

1. Security tab → **"Set password…"** in the Autopilot section.
2. Enter a password in both fields and click **"Set"**.
   - Minimum 4 characters.
   - The password itself is never stored. Only its SHA-256 hash is written to `config.json`.

### Enabling autopilot

1. Click **"Enable autopilot…"**.
2. Enter the password and click **"Confirm"**.
   - Correct password: the section border turns orange and an **"Active"** badge appears.
   - Wrong password: an alert is shown; the mode does not change.

> **The orange border is a deliberate visual signal** that autopilot is on, making it easy to notice if it was left active unintentionally.

### Disabling autopilot

Click **"Disable autopilot"**. No password is required to turn it off.

> **Always disable autopilot when the autonomous session is over.**

### Changing the password

1. Click **"Change password…"**.
2. Enter the **current password** and a **new password**, then click **"Change"**.
   - If the current password is wrong, an error is shown and nothing changes.
   - On success, autopilot is **automatically disabled** — re-enabling it requires the new password.

---

## Priority order

When multiple settings interact, this is the order of evaluation:

```
autopilotEnabled = true   →  skip all checks (execute everything)
        ↓
enabled = false           →  skip all checks (execute everything)
        ↓
no pattern match          →  execute without interruption
        ↓
pattern matches           →  show confirmation dialog
        ↓
user clicks "Cancel"      →  abort execution (error banner shown)
```

---

## config.json reference

Settings are stored in `~/Library/Application Support/FloatingMacro/config.json`.

```json
{
  "commandBlacklist": {
    "enabled": true,
    "patterns": [
      "rm -rf",
      "sudo rm",
      "..."
    ],
    "autopilotEnabled": false,
    "autopilotPasswordHash": "<64-character SHA-256 hex digest>"
  }
}
```

| Field | Description |
|---|---|
| `enabled` | Set to `false` to bypass pattern matching entirely |
| `patterns` | List of forbidden substrings |
| `autopilotEnabled` | Set to `true` to skip confirmation dialogs |
| `autopilotPasswordHash` | SHA-256 hash of the passphrase. `null` means autopilot cannot be enabled |

> **Note:** Setting `autopilotEnabled` to `true` directly in `config.json` does work, but doing so while `autopilotPasswordHash` is `null` leaves autopilot without password protection. Always configure it through the UI.

---

## FAQ

**Q. Can the AI enable autopilot on its own?**

The Control API does not expose an endpoint that sets `autopilotEnabled` to `true`.
The only way to enable autopilot is through the UI password prompt.

**Q. I forgot the password.**

The password itself is not stored, so it cannot be recovered.
Open `config.json` directly, set `"autopilotPasswordHash": null`, and optionally verify that
`"autopilotEnabled": false` is also set. You can then go through the first-time setup again.

**Q. A dialog appeared mid-macro. What happens to the remaining steps?**

If you click "Cancel", and the macro was configured with `stopOnError: true` (the default),
the entire macro is aborted. With `stopOnError: false`, only the blocked step is skipped
and execution continues with the next step.

**Q. Why did a dialog appear for a text action?**

Text actions are also checked against the forbidden patterns. If the focused window is a
terminal, pasting text containing a dangerous string would execute it — so the same
safeguard applies.
