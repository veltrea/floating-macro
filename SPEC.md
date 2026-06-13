# FloatingMacro — Specification

**Read this in other languages:** [日本語](SPEC.ja.md)

Last updated: 2026-04-16

---

## 1. Overview

**FloatingMacro** is a floating macro launcher for macOS. From a small persistent window on screen, the following can be executed with a single click:

- Keyboard shortcut emission
- Arbitrary text pasting (via clipboard)
- Launching apps / files / URLs
- Launching a terminal and auto-typing commands into it
- **Macros** — sequential execution of combinations of the above

This project takes a clean-room approach inspired by similar software for Windows (FloatingButton by Trifolium Studio), but redesigned natively for Mac. We do not reference the original software's code at all. Only externally observable behavior and screenshots are used as references.

### AI-oriented design — treating AI agents as first-class users

FloatingMacro is designed from the start with **AI agents being able to observe, configure, and operate the app end-to-end** as a requirement. Rather than bolting AI onto an existing app, this is a project that explores **what design emerges when you assume AI as a first-class user** within the scope of a small utility:

- Logs are JSON one-event-per-line (AI can pipe and read them)
- Built-in HTTP Control API (localhost only, zero external dependencies)
- The API is compatible with standard protocols equivalent to ACP / MCP / A2A
- The CLI (`fmcli`) is invokable directly from bash by AI

---

## 2. Target users and primary use cases

### Assumed users
- Users who use pen tablets / trackpads primarily and find keyboard shortcuts hard to invoke frequently
- Developers who want to quickly inject prompts into AI agents (Claude Code / Claude CLI / etc.)
- Developers who want to open multiple terminals + change directories + start commands in one shot
- **Developers exploring AI-first workflows where AI agents are the primary operators of the app**

### Primary use cases
1. **AI prompt injection** — paste boilerplate prompts like "Think with ultrathink" with one button press
2. **One-shot dev environment expansion** — one button opens 4–5 terminals, `cd`s each to a directory, and launches `claude`
3. **Work scene switching** — switch presets to swap button sets like "Writing mode" / "Dev mode" / "Debug mode"
4. **App launcher** — group and place frequently used apps / folders / URLs (with auto-fetched app icons)
5. **Remote operation by AI** — Claude / Gemini operates buttons via the Control API: add/edit, move the window, execute actions

---

## 3. Non-goals

- Windows / Linux support (Mac only)
- Detailed multi-monitor position memory (under consideration for v2+)
- Cloud sync (local config only)
- OCR / image recognition-based automation
- Script language execution engine (one-shot shell commands are fine, but no JS/Python VM)
- Full replacement for existing macro tools (Keyboard Maestro, BetterTouchTool)

---

## 4. Platform / tech stack

| Item | Choice |
|---|---|
| Language | Swift 5.9 |
| UI | Hybrid SwiftUI + AppKit (NSPanel) |
| Minimum OS | macOS 13 (Ventura) |
| Build | Swift Package Manager |
| Binary | universal (arm64 + x86_64) |
| Dependencies | Standard frameworks only (AppKit / SwiftUI / Carbon / ApplicationServices / Network.framework) |

### Why Swift 5.9
Carrying Swift 6's strict concurrency from the MVP would burn time on UI / async conflict handling. Migration to 6 is deferred to v2+.

### Why no external dependencies
For persistent tools, startup speed / security / maintainability matter. Since implementation is possible with standard frameworks alone, we maintain a minimal configuration. The HTTP server is also implemented in-house using `Network.framework`'s `NWListener` (swift-nio / Vapor are not introduced).

---

## 5. Project layout

```
floatingmacro/
├── Package.swift
├── SPEC.md                       # This document
├── README.md                     # (later)
├── Sources/
│   ├── FloatingMacroCore/        # Pure logic (UI / AppKit deps are only in Platform/)
│   │   ├── Config/
│   │   │   ├── ButtonDefinition.swift
│   │   │   ├── Preset.swift                  # Preset / ButtonGroup / WindowConfig / ControlAPIConfig / AppConfig
│   │   │   ├── ConfigLoader.swift
│   │   │   ├── ConfigWriter.swift
│   │   │   └── PresetEditor.swift            # Pure CRUD logic for preset/group/button
│   │   ├── Actions/
│   │   │   ├── Action.swift
│   │   │   ├── KeyCombo.swift
│   │   │   ├── KeyActionExecutor.swift
│   │   │   ├── TextActionExecutor.swift
│   │   │   ├── LaunchActionExecutor.swift
│   │   │   ├── TerminalActionExecutor.swift
│   │   │   └── ActionError.swift
│   │   ├── Macro/
│   │   │   └── MacroRunner.swift
│   │   ├── Platform/
│   │   │   ├── Clipboard.swift
│   │   │   ├── AppleScriptRunner.swift
│   │   │   ├── WorkspaceLauncher.swift
│   │   │   └── EventSynthesizer.swift
│   │   ├── Permissions/
│   │   │   ├── AccessibilityChecker.swift
│   │   │   └── AutomationChecker.swift
│   │   ├── Icons/
│   │   │   └── IconResolver.swift            # Path resolution logic (AppKit-independent)
│   │   ├── Logging/
│   │   │   ├── LogLevel.swift
│   │   │   ├── LogEvent.swift
│   │   │   ├── Logger.swift                  # FMLogger / NullLogger / InMemoryLogger / ComposedLogger / LoggerContext
│   │   │   ├── FileLogWriter.swift
│   │   │   └── ConsoleLogWriter.swift
│   │   └── ControlAPI/
│   │       ├── HTTPMessage.swift             # HTTPRequest / HTTPResponse
│   │       ├── HTTPParser.swift              # Raw HTTP/1.1 parser (not JSON)
│   │       ├── ControlServer.swift           # NWListener wrapper
│   │       ├── SystemPrompt.swift            # Self-intro prompt for AI + manifest()
│   │       ├── ToolCatalog.swift             # All tool definitions + MCP/OpenAI/Anthropic 3-format conversions
│   │       ├── OpenAPIGenerator.swift        # Auto-generate OpenAPI 3.1 JSON
│   │       ├── AgentCard.swift               # A2A Agent Card output
│   │       └── MCPAdapter.swift              # JSON-RPC 2.0 over HTTP (Anthropic MCP)
│   ├── FloatingMacroCLI/
│   │   └── main.swift                        # `fmcli` - CLI test harness + log viewer
│   └── FloatingMacroApp/
│       ├── App.swift                         # AppDelegate
│       ├── FloatingPanel.swift               # NSPanel subclass
│       ├── ButtonView.swift                  # SwiftUI button render + icon
│       ├── PresetManager.swift               # ObservableObject + edit API
│       ├── IconLoader.swift                  # NSImage cache + NSWorkspace icon retrieval
│       ├── Settings/
│       │   ├── SettingsView.swift            # Root of SwiftUI settings window
│       │   ├── SettingsDetail.swift          # Button attribute editor form
│       │   └── SettingsWindowController.swift
│       └── ControlAPI/
│           └── ControlHandlers.swift         # HTTP endpoint implementation (REST + /tools/call + /mcp)
├── Tests/
│   └── FloatingMacroCoreTests/               # 226 tests (as of 2026-04-16)
├── scripts/
│   ├── fmcli_smoke.sh                        # Automated smoke for fmcli (31 items)
│   └── control_api_smoke.sh                  # E2E with real GUI process + curl (78 items)
└── docs/
    ├── manual_test.md                        # Human visual verification list
    └── AI_PROTOCOL.md                        # AI agent connection manual
```

**Design principles**:
- `FloatingMacroCore` does not depend on UI / AppKit. `import AppKit` is limited to `Platform/`.
- All Executors have DI-capable static singletons (`synthesizer`, `clipboard`, `launcher`, `scriptRunner`) for mock substitution during testing.
- All logic is testable from `FloatingMacroCLI`.
- 4-layer test: unit tests + `fmcli` smoke + Control API smoke + manual tests.

---

## 6. Configuration file specification

### 6.1 Location

```
~/Library/Application Support/FloatingMacro/
├── config.json        # Preset list and selection state + window settings + controlAPI settings
├── presets/
│   ├── default.json
│   ├── dev.json
│   └── writing.json
└── logs/
    ├── floatingmacro.log
    └── floatingmacro.log.old   # Rotates above 10MB
```

Override with the `FLOATINGMACRO_CONFIG_DIR` environment variable (for testing / external disk operations).

### 6.2 `config.json` schema

```json
{
  "version": 1,
  "activePreset": "default",
  "window": {
    "x": 100,
    "y": 100,
    "width": 200,
    "height": 300,
    "orientation": "vertical",
    "alwaysOnTop": true,
    "hideAfterAction": false,
    "opacity": 1.0
  },
  "controlAPI": {
    "enabled": false,
    "port": 17430,
    "testMode": false
  },
  "presetOrder": ["default", "midjourney", "note-hashtags"]
}
```

`presetOrder` is the order shown in the preset picker. Presets not in the array (e.g., files dropped externally) are appended alphabetically at the end, and presets in the array that don't exist are auto-removed (self-heal). Falls back to pure alphabetical order if missing or empty.

For backward compatibility, all missing fields fall back to defaults (based on `decodeIfPresent`).

### 6.3 Preset file (`presets/*.json`) schema

```json
{
  "version": 1,
  "name": "default",
  "displayName": "Default",
  "memo": "Prerequisites:\n• Bring target app to front before pressing\n• Clipboard history is overwritten briefly",
  "groups": [
    {
      "id": "group-1",
      "label": "AI",
      "collapsed": false,
      "buttons": [
        {
          "id": "btn-ultrathink",
          "label": "ultrathink",
          "icon": null,
          "iconText": "🧠",
          "backgroundColor": "#FF6B00",
          "width": 140,
          "height": 36,
          "action": {
            "type": "text",
            "content": "Please tackle the next task with ultrathink."
          }
        }
      ]
    }
  ]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `version` | int | × | Schema version (defaults to 1) |
| `name` | string | ◯ | Internal id (matches filename) |
| `displayName` | string | × | Display name in menus etc. (defaults to `name` if omitted) |
| `memo` | string? | × | Free-form memo for the entire preset. Place to leave prerequisites, OS settings, intended use cases, etc. Shown as a collapsible block at the top of the panel. Empty string or missing means "no memo". |
| `groups` | Group[] | ◯ | Group array |

### 6.4 Button (`buttons[]`) fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | ◯ | Unique within preset |
| `label` | string | ◯ | Display string |
| `icon` | string? | × | Image file path (PNG/ICO/ICNS/JPEG) OR app bundle id OR `.app` absolute path |
| `iconText` | string? | × | Emoji / 1–2 character display icon |
| `thumbnail` | string? | × | Image for large display when parent group's `displayType == "card"`. Absolute path recommended. Save convention `presets/<name>/images/<button-id>.{ext}` (added v0.11) |
| `backgroundColor` | string? | × | `#RRGGBB` or `#RRGGBBAA` hex |
| `width` | number? | × | Explicit width (points). null for auto |
| `height` | number? | × | Explicit height. null for auto |
| `confirm` / `confirmMessage` / `confirmDestructive` | — | × | Pre-execution confirmation dialog (see separate section) |
| `action` | Action | ◯ | Behavior on click |

#### Auto-resolution of `icon`
Even when `icon` is not set, if `action.type == "launch"` and `target` is an app path / bundle id, **that target is auto-inferred as icon** and the app icon is retrieved via `NSWorkspace.icon(forFile:)`. The result is stored in an in-process cache.

### 6.5 Group (`groups[]`) fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | ◯ | Unique within preset |
| `label` | string | ◯ | Group header |
| `collapsed` | boolean | × | Collapsed state (default false) |
| `displayType` | string? | × | Button rendering style. `icon` (default) / `wide` / `card`. Treated as `icon` if missing (added v0.11) |
| `buttons` | Button[] | ◯ | Button array |

#### `displayType` behavior (v0.11)

- **`icon`** (default): existing small icon + label. Compact vertical layout
- **`wide`**: full-width, large-icon + label-centric horizontal cells. Labels wrap to 2 lines max
- **`card`**: thumbnail + title in a 2-column `LazyVGrid`. Prioritizes `button.thumbnail`; if absent, falls back to icon → iconText in that order

Because `displayType=icon` is omitted on encode, existing preset files have zero diff when loaded/saved after Phase 2's release. Only groups set to `wide` / `card` get `"displayType": "..."` written to JSON.

---

## 7. Action type specification

All actions are a tagged union distinguished by the JSON `type` field. On the Swift side, represented as `enum Action`. (No changes — §7.1–7.6 details follow the original spec.)

### 7.1 `key` — emit key combo

```json
{ "type": "key", "combo": "cmd+v" }
```

Synthesizes keyDown + keyUp with `CGEventCreateKeyboardEvent` and dispatches via `CGEventPost(.cghidEventTap, event)`.

**combo syntax** (`+`-delimited):

- Modifier keys: `cmd` (alias: `command`) / `shift` / `option` (alias: `alt`, `opt`) / `ctrl` (alias: `control`)
- Character keys: `a-z`, `0-9`, US-layout symbols (`=`, `-`, `[`, `]`, `;`, `'`, `\`, `,`, `.`, `/`, `` ` ``)
- Special keys: `delete` (alias: `backspace`), `forwarddelete`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`, `return` (alias: `enter`), `tab`, `space`, `escape` (alias: `esc`)
- Function keys: `f1`–`f20`

Examples: `cmd+shift+v` / `f5` / `cmd+left` / `option+forwarddelete` / `delete`

**Input from Settings UI** (v0.9.2): the key-action editor panel in the edit window has (a) a **"Press a key to record" button** that generates `combo` from a single physical keypress, and (b) a **"Special Key…" pulldown** to pick the above special keys with labels. Delete / arrow keys etc. cannot be entered as characters into a TextField, so without these input aids they would be unregisterable.

**Discovery from ACP** (v0.9.2): the `list_key_codes` tool (GET `/key-codes`) returns a complete normative catalog of modifier keys / aliases / special keys / F1–F20 / examples. Lets AI consult the catalog dynamically rather than memorizing it.

### 7.2 `text` — text injection

```json
{
  "type": "text",
  "content": "Think with ultrathink",
  "pasteDelayMs": 120,
  "restoreClipboard": true,
  "appendMode": false
}
```

Execution flow (`appendMode: false`, default):
1. Save all clipboard items (all UTI types)
2. `defer` guarantees restoration (returns to original even on synth failure — prevents secrets leakage)
3. setString the text
4. Wait `pasteDelayMs`
5. Dispatch Cmd+V via CGEvent synthesis

Execution flow (`appendMode: true`, added in v0.10 — prompt builder):
1. Get the current clipboard string (treats as empty string if not a string type)
2. Concatenate `content` to the end (no separator inserted — the caller controls by including `", "` etc. in content)
3. Write back via setString
4. **Do not** paste, **do not** restore (keeps the concatenated state persistent)

The use case for `appendMode: true` is **prompt fragment composition** like Midjourney's "style + pose + outfit + background". The user presses multiple buttons in order to stack fragments, then manually does Cmd+V at the end. Backward-compatible decoder loads existing preset JSON without `appendMode` key as false.

### 7.3 `launch` — launch app / file / URL

```json
{ "type": "launch", "target": "..." }
```

target interpretation (priority order):
1. `shell:` prefix → execute with `/bin/sh -c`
2. Contains `://` → `NSWorkspace.open(URL)`
3. `com.xxx.xxx` format → via bundle identifier
4. Absolute path or `~/` → file/folder/app
5. Otherwise → `launchTargetNotFound`

### 7.4 `terminal` — launch terminal and inject command

Terminal.app / iTerm2 via AppleScript; otherwise NSWorkspace + clipboard-based paste.

### 7.5 `delay` — wait

```json
{ "type": "delay", "ms": 500 }
```

### 7.6 `macro` — sequential execution of an action array

Nesting is forbidden (rejected by the parser). `stopOnError` controls abort/continue behavior.

---

## 8. Window specification

### 8.1 Basic properties

| Item | Specification |
|---|---|
| Window class | `NSPanel` subclass |
| style mask | `.nonactivatingPanel`, `.titled`, `.closable`, `.resizable`, `.fullSizeContentView` |
| level | `.floating` |
| collection behavior | `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary` |
| Focus stealing | None (canBecomeKey/canBecomeMain = false) |
| Drag move | Long-press on blank area to move freely |
| Always on top | Default ON |
| Opacity | Default 1.0, variable from 0.25 to 1.0 (4 levels in menu, any value via API) |
| Position/size persistence | Written back to `config.json` on `applicationWillTerminate` |

### 8.2 Layout

- **Orientation**: vertical stack (v0.1), horizontal in the future
- **Grouping**: each group has a small header + button column
- **Collapsing**: click group header to collapse
- **Width/height**: default 200×300, user-resizable by drag, also changeable via API

### 8.3 Menu bar

- Persistent in menu bar via `NSStatusItem`
- Menu items:
  - Show / Hide
  - Preset switch (submenu)
  - **Opacity** (25% / 50% / 75% / 100% submenu, ✓ on current value)
  - **Button Edit...** (`Cmd+E` for the settings window)
  - Open Settings Folder
  - Reload
  - Quit
- Dock icon not shown (`LSUIElement = YES`)

---

## 9. Permission requirements

### 9.1 Accessibility permission
Required for key event synthesis via `CGEventPost`. Checked continuously via `AXIsProcessTrustedWithOptions`. When not granted, `AccessibilityChecker.openSystemPreferences()` guides the user to the settings.

### 9.2 Automation permission
Required for AppleScript dispatch to Terminal / iTerm. Get 4 states (`.authorized / .denied / .notDetermined / .targetUnavailable`) via `AutomationChecker.check(bundleIdentifier:)`.

### 9.3 Code signing
- MVP: a state where it can be verified to work with self-signing
- v2: Developer ID signing + notarization

---

## 10. Logging

### 10.1 Design intent

**Foundation for AI observability**. Logs are designed for "AI to tail and auto-judge" as the primary purpose, not "humans to verify with their eyes".

- Format: JSON one event per line (JSONL / ndjson compliant)
- Location: `<ConfigDir>/logs/floatingmacro.log`
- Rotation: renamed to `.old` over 10MB
- `fmcli log tail --json` lets AI read via pipe

### 10.2 LogEvent schema

```json
{
  "timestamp": "2026-04-16T00:30:00.123Z",
  "level": "info",
  "category": "MacroRunner",
  "message": "Starting macro",
  "metadata": {
    "count": "3",
    "stopOnError": "true"
  }
}
```

Timestamp is ISO 8601 + fractional seconds (UTC). Keys are stable in sorted output (diffable). `metadata` is `null` if empty.

### 10.3 LogLevel

`debug` < `info` < `warn` < `error` (Comparable in severity order). Each Logger has a `minimumLevel`; entries below are dropped.

### 10.4 Logger types

| Implementation | Use case |
|---|---|
| `NullLogger` | Default, silent implementation used until something else is explicitly configured in production |
| `InMemoryLogger` | For tests; assertions via `contains(category:messageContains:)` |
| `FileLogWriter` | Production, serialized on DispatchQueue + rotation + `flush()` |
| `ConsoleLogWriter` | For fmcli; human-readable text on stderr |
| `ComposedLogger` | Fan-out to multiple Loggers (file + console) |

Global replacement: `LoggerContext.shared = ...`. Tests inject `InMemoryLogger` in setUp/tearDown.

### 10.5 Log emission points

- `MacroRunner`: macro start / completion / error / abort
- Each `*ActionExecutor`: dispatch / error details per failure
- `ConfigLoader`: load success / failure
- `ControlServer`: connect / bind failure
- Each `ControlAPI` handler: failure only

### 10.6 Environment variables

- `FLOATINGMACRO_CONFIG_DIR` — override config/log directory
- `FLOATINGMACRO_LOG_LEVEL` — `debug|info|warn|error` (equivalent to CLI `--log-level`)

---

## 11. CLI (`fmcli`)

Command-line tool for verifying logic without launching the UI.

```
fmcli action key "cmd+shift+4"
fmcli action text "Hello world"
fmcli action launch "/Applications/Slack.app"
fmcli action terminal --app iTerm --command "ls -la"
fmcli preset list
fmcli preset run default btn-ultrathink
fmcli permissions check
fmcli config path
fmcli config init
fmcli log path
fmcli log tail [--level LEVEL] [--since DUR] [--limit N] [--json]
fmcli --log-level debug action key "cmd+v"
```

**Goals**:
- Test single actions without UI dependencies
- **Minimal path for AI to invoke all functionality via bash**
- Smoke test in CI
- Post-hoc analysis via log queries (`--since 5m --level warn --json | jq`)

---

## 12. HTTP Control API

### 12.1 Design intent

Enable **AI (Claude / Gemini / others) to observe internal app state and execute all functionality**. Maintain compatibility with inter-agent protocols equivalent to MCP / A2A / ACP, while being implementable with zero external dependencies.

### 12.2 Basic properties

| Item | Specification |
|---|---|
| Implementation | `Network.framework`'s `NWListener` (no external deps) |
| Bind | `127.0.0.1` (loopback) only, `requiredInterfaceType: .loopback` |
| Auth | None (since it's localhost-only) |
| Protocol | HTTP/1.1, no Keep-Alive (1 request per connection) |
| Format | JSON in / JSON out (UTF-8) |
| Port | Default 17430, falls back +1 up to 10 times on conflict |
| Startup | Only when `controlAPI.enabled` is set; binds **within 1–2 seconds** on a separate thread |

### 12.3 Startup guidelines (avoiding MCP server pitfalls)

Strict guidelines from prior MCP server implementation experience:
- Do not block the main thread (launch via DispatchQueue.global)
- Initialization completes within 1–2 seconds (`start(timeout: 2.0)`)
- Even on failure, app keeps starting normally (only logs are left)
- Don't create new windows ("attach to existing app" model)

### 12.4 Endpoint list

#### Self-intro / discovery
| Method | Path | Purpose |
|---|---|---|
| GET | `/manifest` | First read for AI: self-intro + full tool list + systemPrompt |
| GET | `/help` | Alias for `/manifest` |
| GET | `/ping` | Liveness check |
| GET | `/openapi.json` | Auto-generated **OpenAPI 3.1** document (ACP / REST compatible) |
| GET | `/.well-known/agent.json` | **A2A Agent Card** (Google-compatible) |
| GET | `/tools?format=mcp\|openai\|anthropic` | Tool definitions in 3 dialects |

#### Unified dispatch
| Method | Path | Purpose |
|---|---|---|
| POST | `/tools/call` | Invoke any tool with `{name, arguments}` |
| POST | `/mcp` | **JSON-RPC 2.0 / MCP HTTP transport** (Anthropic-compatible) |

#### Window operations
- `POST /window/show | hide | toggle`
- `POST /window/opacity` — `{value: 0.25..1.0}`
- `POST /window/move` — `{x, y}`
- `POST /window/resize` — `{width, height}`

#### Observation
- `GET /state` — panel visibility + active preset + window coords + errors
- `GET /log/tail?level=&since=&limit=` — JSON one event per line
- `GET /icon/for-app?bundleId= | path=` — base64 PNG

#### Preset / group / button CRUD
- `GET /preset/list`, `GET /preset/current`
- `POST /preset/switch | reload | create | rename | delete | reorder`
- `POST /group/add | update | delete`
- `POST /button/add | update | delete | reorder | move`

#### Action execution
- `POST /action` — send an Action JSON for immediate execution (202 Accepted)

### 12.5 MCP JSON-RPC support (`/mcp`)

Methods accepted on `POST /mcp` with JSON-RPC 2.0 envelope:
- `initialize` — returns serverInfo + capabilities + protocolVersion
- `tools/list` — full tool definitions
- `tools/call` — dispatches to REST handler; wraps the result in `content[].text` as a JSON string
- `ping` — liveness check

Errors use standard JSON-RPC codes: `-32700/-32600/-32601/-32602/-32603` + app-specific `-32000`.

### 12.6 Security

- **Loopback only** — unreachable from other hosts
- For dangerous operations (e.g., `/action` with `terminal`), the caller bears responsibility for considering the user's context
- Text pasting with `restoreClipboard: true` restores the clipboard even on failure (prevents leakage of passwords etc.)

---

## 13. Icon system

### 13.1 `IconResolver` (Core)

Pure logic resolving a string reference (the `icon` field) into one of 3 cases:

| Case | Detection | Result |
|---|---|---|
| Image file | `.png / .jpg / .icns / .ico / ...` extension + exists | `.imageFile(URL)` |
| `.app` bundle | `.app` extension + exists | `.appBundle(URL)` |
| Bundle ID | `com.xxx.yyy` pattern, no slashes | `.bundleIdentifier(String)` |

### 13.2 `IconLoader` (App)

Converts `IconResolver` results into `NSImage`:
- `.imageFile` → `NSImage(contentsOf: URL)`
- `.appBundle` → `NSWorkspace.icon(forFile:)`
- `.bundleIdentifier` → `NSWorkspace.urlForApplication(withBundleIdentifier:)` + icon

With in-process cache. Also fetchable externally via the API (`/icon/for-app`) as base64 PNG.

### 13.3 Priority order at button rendering

`MacroButtonView` displays the icon in this order:
1. Explicitly set `icon`
2. Auto-inferred from `target` when `action.type == "launch"`
3. `iconText` (emoji)
4. None

### 13.4 `icon` field prefix specification

| Prefix | Example | Resolution |
|---|---|---|
| `sf:` | `sf:star.fill` | SF Symbol (Apple-provided, `NSImage(systemSymbolName:)`) |
| `lucide:` | `lucide:folder` | **Bundled Lucide SVG** (`Bundle.module`, 1695 icons, ISC) |
| `com.xxx.yyy` | `com.apple.Safari` | macOS app bundle identifier (`NSWorkspace`) |
| Starts with `/` or `~/` | `/Applications/Slack.app` | Absolute path or tilde-expanded |

### 13.5 Lucide bundling

`Sources/FloatingMacroApp/Resources/lucide/` bundles **Lucide's 1695 SVG icons**
(**ISC license**, `LICENSE` file also in the same directory).

- Total approx 0.65 MB
- macOS 13+'s `NSImage(contentsOf:)` natively interprets SVG (no external library needed)
- Credits: see `DESIGN.md` §10

---

## 14. GUI Settings window

### 14.1 Invocation

Menu bar → "Button Edit..." or `Cmd+E`. Shares a single NSWindow via `SettingsWindowController.shared.show(presetManager:)`.

### 14.2 Composition

2-column HSplitView:

**Left column** (`SettingsSidebar`):
- Preset selection Picker + add (+) / delete (-)
- Group/button tree (folder icons + selection highlight)
- Group-add text field
- Button-add button (adds to selected group)

**Right column** (`SettingsDetail`):
- Detailed edit form for the selected button:
  - Label
  - iconText (emoji)
  - icon image / app (`NSOpenPanel` for browsing, clear)
  - Background color (SwiftUI `ColorPicker` + hex string two-way bind)
  - Width / height (auto or number)
  - Action (segmented picker: text/key/launch/terminal)
- Delete button / Save button (Enter to confirm)

### 14.3 Consistency guarantees

GUI edits go through **the same CRUD methods on PresetManager that HTTP API / fmcli edits use**, ensuring identical paths.

---

## 15. Testability

### 15.1 4-layer test composition

| Layer | Target | Count (2026-04-16) | Command |
|---|---|---|---|
| Unit | All logic in `FloatingMacroCore` | **226** | `swift test` |
| fmcli smoke | Permission-free CLI surface | **31** | `bash scripts/fmcli_smoke.sh` |
| Control API smoke | Real GUI process + curl E2E | **78** | `bash scripts/control_api_smoke.sh` |
| Manual | Visual verification of GUI | — | `docs/manual_test.md` |

### 15.2 DI pattern

All external dependencies (`EventSynthesizer` / `Clipboard` / `AppleScriptRunner` / `WorkspaceLauncher`) are implemented as `Protocol` + `static var`. Tests substitute mocks all at once via `TestMocks`:

```swift
override func setUp() {
    mocks = TestMocks()  // Replace all Executor static vars with mocks
}
override func tearDown() {
    mocks.restore()
}
```

### 15.3 Logger substitution

`LoggerContext.shared = InMemoryLogger()` captures logs into a buffer. Confirm firing via `contains(category:messageContains:)`.

### 15.4 HTTP API testing

- **Unit**: pure logic of `HTTPParser` / `ToolCatalog` / `MCPAdapter` / `OpenAPIGenerator` / `AgentCard`
- **Integration**: launches `ControlServer` on a random port and hits it via real URLSession
- **E2E**: `scripts/control_api_smoke.sh` launches the real GUI binary and verifies all endpoints via curl

---

## 16. Runtime environment and environment variables

| Variable | Use |
|---|---|
| `FLOATINGMACRO_CONFIG_DIR` | Override config/log directory |
| `FLOATINGMACRO_LOG_LEVEL` | Minimum log level (equivalent to CLI `--log-level`) |
| `DEVELOPER_DIR` | Reference Xcode.app on `swift test` execution (XCTest missing with CommandLineTools only) |

---

## 17. Milestones (implementation status as of 2026-04-16)

### MVP (v0.1) — Implemented ✅

- [x] `Package.swift` + 3 targets (Core / CLI / App)
- [x] `Action` enum + JSON parser + nesting disallowed
- [x] `KeyCombo` parser + CGEvent dispatch
- [x] `TextActionExecutor` (clipboard save/restore + guaranteed restoration via defer)
- [x] `LaunchActionExecutor` (shell/URL/bundle/path branches)
- [x] `TerminalActionExecutor` (Terminal / iTerm / generic)
- [x] `MacroRunner` + logs
- [x] `ConfigLoader` / `ConfigWriter` + FLOATINGMACRO_CONFIG_DIR
- [x] `AccessibilityChecker` + `AutomationChecker`
- [x] `fmcli` (action / preset / permissions / config / log)
- [x] SwiftUI + NSPanel floating window
- [x] Vertical button rendering + drag move
- [x] Persistent in menu bar (`NSStatusItem`)
- [x] Preset switch menu
- [x] Opacity menu (4 steps)
- [x] Button edit GUI (preset/group/button CRUD + icon/color pickers)
- [x] Auto save/restore of position and size
- [x] Banner notifications (3 seconds on error)
- [x] Icon display (image file / app auto-inference)
- [x] Structured logging (JSON one-event-per-line + rotation)
- [x] HTTP Control API (REST + /tools + /tools/call)
- [x] AI self-intro `/manifest` + `/help`
- [x] OpenAPI 3.1 auto-generation (`/openapi.json`)
- [x] A2A Agent Card (`/.well-known/agent.json`)
- [x] MCP JSON-RPC 2.0 HTTP transport (`POST /mcp`)

### v0.2 (UI hardening)
- [ ] Drag reordering (SwiftUI `.onDrop`)
- [ ] Horizontal layout switch
- [ ] Preset import / export
- [ ] Window shape presets (small/medium/large)
- [ ] GUI editor for macros (composite actions)

### v0.3 (Terminal enhancements)
- [ ] iTerm pane-split macros
- [ ] Optimized paste path for Warp / Ghostty
- [ ] Terminal profile specification
- [ ] tmux integration

### v0.4 (AI collaboration enhancements) — Implemented ✅
- [x] Expanded AI integration window clients (Cursor / Gemini CLI / VS Code / Windsurf)
- [x] MCP stdio transport (bundled in app as `npm/floatingmacro-mcp`)
- [x] ACP manifest (`/agents`, `/runs`)

### v0.5 (Accessibility auto-recovery + GUI E2E test foundation) — Implemented ✅
- [x] Launch-time hash comparison via BinaryIdentity + auto `tccutil reset`
- [x] Permission-lost badge + one-click recovery (reset + open System Settings)
- [x] AccessibilityChecker probe improvements (`AXIsProcessTrusted` + `.apiDisabled`-limited counter-signal)
- [x] fm-test-target harness + `text_inject_e2e.sh` (baseline + 2-axis verification)
- [x] `button_press` tool (synthesized real click via AX + CGEvent)
- [x] Preset bundling / import / export (`SeedPresetInstaller` + ACP API)
- [x] `PresetDirectoryWatcher` (detect external changes)

### v0.6 (UX cleanup + Keychain removal) — Implemented ✅
- [x] Changed Control API token from Keychain → file primary (`~/Library/Application Support/FloatingMacro/control_api_token`, mode 0600)
- [x] Cleaned up Accessibility repair flow (removed NSAlert → unified into OS `prompt:true`, 0.8s `openSystemPreferences` fallback, hardened via `/usr/bin/open`)
- [x] Changed Repair button to self-restart approach (re-launch with `--prompt-accessibility` argument; calls `prompt:true` from clean state)
- [x] Resolved double-fire of TCC reset (removed launch-time reset in `scripts/rebuild-and-relaunch.sh`; unified into `BinaryIdentity` single-shot)
- [x] Right-click menu on mini icon (parity with status bar)
- [x] Right-click menu on group headers (delete / add new)
- [x] Expanded panel body right-click hit-test to fill the entire area

### v0.7 (Edit window unification and DnD reorder) — Implemented ✅
- [x] DnD reorder in edit window's left pane (buttons: same/different group move; groups: reorder)
- [x] Renamed window from "Button Edit" to "Edit" (tabs / menus included)
- [x] Unified group-add UI with button-add (one-click "New Group", rename via row's pencil button)
- [x] Unified preset / group right-click menus into "Edit..." / "Delete...". Preset's "Edit..." now opens the edit window.
- [x] Added a pencil icon to the left of the gear icon on the floating panel (link to edit window)
- [x] Group / button right-click "Duplicate" (`PresetManager.duplicateGroup` added; buttons also duplicated with fresh ids)
- [x] Repositioned delete button to the left of save button (ButtonEditor / GroupEditor)

### v0.8 (Accessibility permission flow fix and preset ordering) — Implemented ✅
- [x] Structural fix for infinite-loop in Accessibility permission dialog (removed launch-time auto `tccutil reset`, `prompt: true` only via `--prompt-accessibility`, removed our own `openSystemPreferences()` and explanation NSAlert)
- [x] User-configurable preset ordering (right-click "Reorder…", persisted in `config.json` `presetOrder`, Control API `preset_reorder`)
- [x] Added knowledge doc `macos_accessibility_permission.md` (Sequoia's TCC daemon behavior and workarounds)

### v0.10 (Visual expansion Phase 1) — Implemented ✅
- [x] Added `appendMode: Bool` to `Action.text` (append mode for prompt builder). Backward-compatible decoder keeps existing presets working.
- [x] Added `appendMode` parameter to `TextActionExecutor.execute`. When true, concatenates content to end of current clipboard; does not paste or restore.
- [x] Added "Append Mode (Prompt Builder)" checkbox to the button editor panel
- [x] Control API: added `appendMode` field to `text` action schema (default false)
- [x] Auto-generated buttons via drag & drop onto the floating panel (`.app` → bundle-id-based launch; other files → absolute-path launch)
- [x] Extracted icons of dropped apps/files via `NSWorkspace.icon(forFile:)` and saved as `presets/<name>/icons/<button-id>.png`
- [x] Visual feedback during drag (accent-colored thick border)
- [x] Confirmation dialog "Add N items to group" before bulk registration
- [x] Added roadmap `docs/plans/visual-expansion-roadmap.md` (Phase 1–5 staged expansion plan)

### v0.10.5 (Phase 1.5: Icon extraction foundation rebuild + app picker) — Implemented ✅
- [x] Added `ImageIOIconExtractor` (`FloatingMacroCore/Icons/`). Direct read of `.icns` via `CGImageSource` to PNG, sync + async APIs. Zero AppKit dependency.
- [x] Added `AppEntry` / `AppEntryResolver` / `FileSystemAppListProvider` (`FloatingMacroCore/Apps/`). Enumerates `/Applications` / `/System/Applications` / `~/Applications`, extracts `CFBundleIdentifier` / `CFBundleDisplayName` / `CFBundleName` via direct Info.plist read, dedups by Bundle ID, sorts by displayName
- [x] Added `AppDropClassifier` / `IconAssetSaver`. DnD classification and icon PNG saving centralized in Core. With `applicationSupportDirectory:` injection, tests can write to a temporary directory.
- [x] Moved `PanelDropHandler` onto Core logic (removed `NSWorkspace.icon`). Remaining AppKit dependency is just the NSAlert confirmation dialog.
- [x] Added an "**Add from App…**" button to the button editor tab in Settings; implemented a dedicated sheet `AppLauncherPickerSheet.swift`. Search (app name / Bundle ID), async preview of the selected icon, double-click / Enter for instant add.
- [x] Rejected qlmanage-based path via real verification. `scripts/spikes/qlmanage-pipe-spike/` tested 4 patterns (anti-pattern / null device / readabilityHandler / background readToEnd) and reproduced a 20-second hang against Calculator.app (Quick Look daemon problem, not resolved by daemon restart). Changed direction to ImageIO.
- [x] Added an **NSWorkspace path** to the UI layer (`FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift`). For Catalyst / modern apps like UTM (Assets.car-only) or Books (empty .icns placeholder). Core stays Foundation + ImageIO only; AppKit dependency is contained in the UI layer. Uses the community-standard `NSWorkspace.shared.icon(forFile:)` (orchetect's Gist, etc.).
- [x] **AppIconCache** (Core actor) — memory + disk two-stage cache. Disk save at `~/Library/Caches/FloatingMacro/AppIcons/<bundleId>.png`; file mtime aligned to app mtime for auto invalidation. Lightweight hit check via `contains()`, thread-safe `get()/put()`.
- [x] **AppIconPrewarmer** (Core) — parallel prewarm of all `/Applications` apps at launch (default parallelism 4). Uses `Task.detached(priority: .utility)` to not block UI. Called from `applicationDidFinishLaunching`, so by the time the picker is shown, nearly all apps are cached.
- [x] **IconContentValidator** (Core) — decodes PNG bytes / CGImage and inspects "has content" at the pixel level. Early-returns true upon finding any pixel with `alpha > 8` or `RGB > 8`. Reliably rejects icons that are "successful but empty PNGs" (like Books.app's icns).
- [x] Made AppLauncherPickerSheet, PanelDropHandler, AppIconPrewarmer `async`-aware for cache reference and content inspection. Cascade: shared cache → ImageIO → NSWorkspace. Runs `IconContentValidator` at each stage; thin PNGs (from empty .icns) are dropped to the next stage, forming the auto-repair loop.
- [x] Resolved Phase 1's P1-12 "DnD button-creation E2E untestable". Core logic (8 files) covered by **46 unit tests** (`AppEntryResolverTests` 7, `FileSystemAppListProviderTests` 7, `AppDropClassifierTests` 6, `IconAssetSaverTests` 4, `ImageIOIconExtractorTests` 5, `AppIconCacheTests` 6, `AppIconPrewarmerTests` 3, `IconContentValidatorTests` 8).
- [x] Made the design principle **"Foundation-class API > GUI-class API"** explicit in the roadmap Phase 1.5 chapter and memory (`feedback_prefer_foundation_over_gui_apis`). Used as the API selection criterion for Phase 2 and beyond.

### v0.10.6 (Phase 1.5 finishing: App picker UI overhaul + internal stabilization) — Implemented ✅
- [x] Reworked app picker sheet (`AppLauncherPickerSheet`) from "list + right-side preview" to **Launchpad-style grid** in `LazyVGrid` 96px cells. Single-click selects, double-click (or "Add" button) adds immediately; selected app details shown in the footer.
- [x] Sheet size grew from 640×500 to 880×620, 8–9 columns. Since it uses `LazyVGrid`, off-screen cells don't trigger icon extraction (kept the design assuming prewarm cache at launch).
- [x] Added `AppIconCache.mtimeStillValid(cached:app:)` and applied **1.0-second tolerance** to `get()` / `contains()` mtime comparison. Resolved flakiness in `testDiskCachePromotesToMemoryAcrossInstances` caused by APFS sub-second truncation and clock jitter.
- [x] Updated `ConfigIOTests.testWriteDefaultConfigCreatesConfigAndDefaultPreset` to expect the new default preset's first button: `btn-ultrathink` → `btn-ai-copy-prompt`.

### v0.13.0 (Phase 5: Multi-device) — Implemented ✅
- [x] **LAN exposure mode**: `ControlAPIConfig.lanExposureEnabled` toggle. When enabled, widens bind scope to `0.0.0.0`; auth via ephemeral LAN token (expires on restart).
- [x] **Web Panel** (`/webpanel`): mobile-browser-oriented SSR + HTML/CSS/JS panel UI. Auto-detects card / icon-card; instant first paint via critical CSS inline + skeleton.
- [x] **QR / Bonjour / mDNS**: menu bar "📱 Send to Device..." + QR button in floating panel's top-right. Advertises `_floatingmacro._tcp.` for zero-config discovery.
- [x] **WebP delivery**: libwebp (via SwiftPM, BSD-3) encodes thumbnails. Transfer size is approx 1/100 of original PNG.
- [x] **Parallelism**: per-connection independent queues + main bypass fast path. App Nap suppression.
- [x] **`WebPanelToolWhitelist`**: tools callable from Web Panel are restricted to safe ones like `button_press` (destructive tools return 403).
- [x] **Added `preset_get` tool**: read-only retrieval of non-active presets.
- [x] **Management endpoints**: `GET /lan-token`, `POST /lan-token/rotate`.
- [x] **Tests**: 421 tests pass (+62 added in Phase 5).
- [x] **Version bump**: Info.plist `0.13.0` / build `24`, `SystemPrompt.version`, `CHANGELOG.md` v0.13.0 chapter.

### v0.16.3 (Localization foundation: Externalize tool descriptions and manifests) — Implemented ✅
- [x] **JSON externalization of tool descriptions**: separated 50 tools + ~70 parameter descriptions into `tool_descriptions.json`. `ToolCatalog.swift` is now 2-stage: JSON load → fallback.
- [x] **Bilingual manifests / ACP**: made endpoints table / helpTool description in `SystemPrompt.swift`, agent description / tool_invocation_format in `ACPManifest.swift` EN/JP-bilingual.
- [x] **L()-ification of UI dialogs**: converted 12 hardcoded confirmation dialog strings in `ButtonView.swift` to `L()` / `L_()` calls.
- [x] **Version bump**: Info.plist `0.16.3` / build `33`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.3 chapter.

### v0.16.2 (Internal refactoring: oversized file split) — Implemented ✅
- [x] **Split `ControlHandlers.swift` (2,235 lines) into 7 files**: main (613 lines) + 6 extensions: WebPanel / Panel / Settings / Preset / ButtonGroup / ACP. Due to Swift constraint, stored properties stay in the main body; only methods are in extensions.
- [x] **Split `App.swift` (1,736 lines) into 5 files**: main (623 lines) + `ContentHostView` extraction + 3 AppDelegate extensions: ContextMenu / Dock / LANBonjour. `@objc` methods stay in main for selector binding safety.
- [x] **Split `SettingsDetail.swift` (1,676 lines) into 5 files**: main (121 lines) + ButtonEditor / GroupEditor / MacroStep / KeyRecorders.
- [x] **Split `PresetManager.swift` (1,194 lines) into 6 files**: main (266 lines) + 5 extensions: PresetIO / ExternalRequest / PanelOps / Editing / ImportExecute. `@Published` etc. stored properties consolidated into main.
- [x] **Split `SettingsView.swift` (1,181 lines) into 5 files**: main (129 lines) + SecuritySettingsView / SettingsSidebar / PresetReorderSheet / RowDropDelegate.
- [x] **Max line count reduced from 2,235 to 778**. No changes to public API / protocols / behavior. `swift build` passes; smoke-tested with `/ping` `/state` `/preset/list`.
- [x] **Version bump**: Info.plist `0.16.2` / build `32`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.2 chapter.

### v0.16.1 (Card layout top-edge alignment fix) — Implemented ✅
- [x] **Card top-edge alignment**: fixed label text area to a fixed height so cards align at the top within each row in WaterfallGrid.
- [x] **Version bump**: Info.plist `0.16.1` / build `31`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.1 chapter.

### v0.16.0 (Grid display + i18n + preset storage separation) — Implemented ✅
- [x] **Grid display type added**: `GroupDisplayType.grid` (Finder/Launchpad-style icon grid).
- [x] **Column count specification**: `ButtonGroup.columns` lets you choose `auto` / `fixed(1/2/3)` (equivalent to CSS Grid minmax).
- [x] **Icon size selection**: `IconSize` enum (small 16pt / medium 32pt / large 48pt / xlarge 64pt).
- [x] **Label visibility toggle**: `ButtonGroup.showLabels` controls label visibility for icon/grid.
- [x] **i18n foundation**: `L10n.swift` helper, `Localizable.strings` (en/ja) 335 entries each, `scripts/localize.py` for auto-extraction / substitution of hardcoded strings.
- [x] **Preset storage separation**: physically separated seed (`~/Library/Application Support/FloatingMacro/presets/`) and user (`~/Documents/FloatingMacro/presets/`). Copy-on-write on edit.
- [x] **Added environment variable**: `FLOATINGMACRO_USER_DIR` can override user directory.
- [x] **Basic manual**: `docs/manual-basic.md` (with screenshots).
- [x] **Fixed scroll region calculation in card/grid**: replaced `LazyVGrid` with `paololeonardi/WaterfallGrid` (MIT). Height aggregation to NSScrollView is now correct, so vertical scrolling works even when many thumbnail-bearing cards are placed.
- [x] **Panel header support for long preset names**: released horizontal anchoring on Menu label; long names truncate with ellipsis.
- [x] **Version bump**: Info.plist `0.16.0` / build `30`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.0 chapter.

### v0.15.1 (Bug fix: dock bar orientation) — Implemented ✅
- [x] **Edge field in DockBarPosition**: stores orientation during drag-to-move; prefers saved edge on re-dock.
- [x] **EdgeDetector clamp fix**: fixed a bug where the distance went negative when the panel center was outside visibleFrame, selecting an unintended edge.

### v0.15.0 (Phase 3.5 enhancements + panel background color) — Implemented ✅
- [x] **Customizable panel background color**: per preset (`WindowConfig.backgroundColor` stores `#RRGGBB` hex). Right-click menu "Background Color ▸", added a color picker to the Settings panel tab. Control API: `panel_background_color` tool.
- [x] **Dock transition animation**: added a slide + fade animation with bordered rectangular overlay for the panel-to-dock-bar transition (`DockTransitionAnimator`).
- [x] **Dock bar drag-to-move**: dock bars can now be moved freely. Position is persisted in `PanelConfig.dockBarPosition`. Custom position is kept across expand → re-dock. Clamps during drag to keep all edges inside the visible screen.
- [x] **Panel restore changed to double-click**: prevents accidental expansion from misclicks.
- [x] **Differentiated × and yellow buttons**: × collapses to circular icon, yellow uses Edge Dock.
- [x] **Rescue operations**: added "Reset Position" and "Gather Dock Bars" to right-click menu "Panel ▸". Control API: `panel_reset_dock_position` / `panel_gather_dock_bars`.
- [x] **Tests**: all 445 pass.

### v0.14.0 (Phase 3.5: Dock-to-edge minimization) — Implemented ✅
- [x] **`DockEdge` enum** (left/right/top/bottom) added to `Preset.swift`.
- [x] **`PanelConfig.minimizedToEdge: Bool`** → **`PanelConfig.dockedEdge: DockEdge?`** (type change). Legacy JSON `minimizedToEdge: true` is auto-migrated to `.right` by the decoder. On encode, only `dockedEdge` is written; the legacy key is not kept.
- [x] **`AppConfig+Panels`**: added `dockingPanel(id:edge:)` / `undockingPanel(id:)`. Removed legacy `settingPanelMinimizedToEdge`.
- [x] **`EdgeDetector`** (Core layer): pure function that determines the nearest edge from panel center coordinates.
- [x] **`EdgeDockLayout`** (Core layer): pure function that calculates positions of bars sharing an edge, centered.
- [x] **`EdgeDockBar`** (App layer): a thin bar that sticks to the screen edge. Purple gradient background, icon + label, left-click expands and right-click opens a menu.
- [x] **PanelManager extension**: added `collapseToDock` / `expandFromDock` / `relayoutDockBars`, added `dockBar` to Entry.
- [x] **× button** behavior changed from MiniIconPanel to edge dock.
- [x] **Menu bar**: added "Dock to Edge ▸" submenu; for docked panels, "Expand" and "Move to Another Edge ▸".
- [x] **Control API**: added `panel_dock` / `panel_undock` handlers; changed `minimizedToEdge` → `dockedEdge` in `panel_list` response.
- [x] **Launch restore**: docked panels are restored as `EdgeDockBar`.
- [x] **Tests**: EdgeDetectorTests (6), EdgeDockLayoutTests (7), legacy migration tests (3), dock operation tests (3), ToolCatalog (3). All 445 pass.

### v0.12.0 (Phase 3: Multi-panel) — Implemented ✅
- [x] Added **`PanelConfig`** struct and **`AppConfig.panels: [PanelConfig]`** field (`Sources/FloatingMacroCore/Config/Preset.swift`). 1 panel = id (UUID) + presetName + WindowConfig + visible + minimizedToEdge.
- [x] **v1 → v2 auto migration**: JSON with legacy `activePreset` + single `window` is decoded into `panels[0]` and written back. Legacy fields are also written in sync with `panels[0]` during Phase 3 transition.
- [x] **`AppConfig+Panels.swift`** extension provides pure functions (addingPanel / removingPanel / updatingPanelFrame / updatingPanelOpacity / settingPanelPreset / settingPanelVisible / withSyncedLegacyFields). AppKit-independent and unit-testable.
- [x] **`PanelManager`** class (`Sources/FloatingMacroApp/PanelManager.swift`): manages an id → (FloatingPanel, MiniIconPanel) map. openInitial / openNew / close / collapseToMini / expandFromMini / toggle / setOpacity / currentFrames; encapsulates `floatingPanelWantsCollapse` notification subscription.
- [x] **AppDelegate reconcile sink**: watches `presetManager.$appConfig.panels` via Combine sink; auto-reflects add/remove into NSWindow creation/destruction. Unifies panel operation across menu bar, Settings, and Control API.
- [x] **Per-panel preset rendering**: refactored `ContentHostView` to accept `panelID`. With `presetManager.panelPreset(forPanelID:)`, each panel can display a different preset.
- [x] **`PresetManager.loadedPresets`** multi-preset cache (`@Published`) and `preset(named:)` / `panelPreset(forPanelID:)` / `switchPanelPreset(panelID:to:)` / `setEditTarget(panelID:)`.
- [x] **Menu bar "Panels" submenu**: add a new panel / visibility toggle / close-and-delete.
- [x] **Settings "Panels" tab** (`PanelsSettingsView.swift`): panel list + preset switch + delete.
- [x] **Control API panel_* tools** 5 added to ToolCatalog: `panel_list` / `panel_create` / `panel_close` / `panel_show` / `panel_hide`. `window_*` marked "DEPRECATED: prefer panel_*"; re-targeted to the primary panel.
- [x] **Tests**: added 6 Phase 3 cases to `ConfigLoaderTests` (PanelConfig roundtrip, minimal JSON, auto id generation, v1 migration, empty array migration, multiple panels, explicit panels priority). Added 14 cases to `AppConfigPanelOpsTests` (add/remove/update/legacy sync). Added panel_* registration / window_* deprecation / panel_create schema validation to `ControlAPICatalogTests`. All 349 tests pass.
- [x] **Version bump**: Info.plist `0.12.0` / build `21`, `SystemPrompt.version`, `CHANGELOG.md` v0.12.0 chapter.

### v0.11.0 (Phase 2: Expressive expansion) — Implemented ✅
- [x] Added **`GroupDisplayType`** enum (`icon` / `wide` / `card`) and `ButtonGroup.displayType` field. Backward-compatible decoder treats legacy presets as `.icon`. `.icon` is omitted on encode (zero diff).
- [x] Added **`ButtonDefinition.thumbnail`** field. Path to large image used in card type. null falls back to icon → iconText.
- [x] Implemented **wide / card renderers** as `buttonContent` branches in `MacroButtonView`. `.wide` is a full-width large cell; `.card` arranges "thumbnail + title" vertically in a `LazyVGrid(adaptive: 96)` gallery.
- [x] **State feedback indicator** (P2-9/P2-10): `ExecutionFeedback` state machine for press → yellow border (in-progress, 250ms) → green border (success 800ms) → idle animation. Failure (red) display will be wired up after sorting out the return value of `executeButton`.
- [x] Added `imagesDirectory(presetName:)` and `saveThumbnail(_, buttonId:, ext:)` to **`IconAssetSaver`**. Provides the save convention `presets/<name>/images/<button-id>.<ext>`.
- [x] **Settings UI**: added a segmented picker for `displayType` to `GroupEditor`; added thumbnail input + file picker + preview frame to `ButtonEditor`.
- [x] **Control API**: added `displayType` (`icon`|`wide`|`card`) to `group_add` / `group_update`; added `thumbnail` (string | null) to `button_add` / `button_update`.
- [x] **Fixed existing bug**: fixed a path where `applyPatch` was not passing `confirm` / `confirmMessage` / `confirmDestructive` to `updateButton`. Phase 2's `thumbnail` passes through the same route.
- [x] **Tests**: added `testButtonGroupDisplayTypeRoundTrip` / `testButtonGroupDefaultDisplayTypeOmittedFromEncoding` / `testButtonGroupLegacyJSONWithoutDisplayType` / `testButtonDefinitionThumbnailRoundTrip` to `ConfigLoaderTests`. Added `testSaveThumbnailWritesToImagesDirectory` / `testImagesDirectoryPath` to `IconAssetSaverTests`. All 317 tests pass.
- [x] **Version bump**: Info.plist `0.11.0` / build `19`, `SystemPrompt.version`, `CHANGELOG.md` v0.11.0 chapter.

### Future (unassigned)
- [ ] A2A Task API + SSE streaming (for long-running macros)
- [ ] `fmcli remote` subcommand (thin wrapper for Control API)
- [ ] OpenTelemetry OTLP export of logs
- [ ] Horizontal layout switch
- [ ] iTerm pane-split macros
- [ ] Optimized paste path for Warp / Ghostty
- [ ] tmux integration

### v1.0
- [ ] Developer ID signing + notarization
- [ ] Distribution DMG
- [ ] Auto-update

---

## 18. Known design decisions

### Why Swift instead of Tauri
- Cross-platform support is unnecessary since we're targeting Mac only
- `NSPanel`'s non-activating behavior is one line in Swift; Tauri would need an objc bridge
- `NSAppleScript` / `NSWorkspace` / `CGEvent` / `AXIsProcessTrusted` / `NWListener` all accessible natively and instantly

### Why no swift-nio / Vapor
- Don't want to increase startup time of a persistent tool
- More dependencies complicate maintenance
- `NWListener` is sufficient for HTTP/1.1 localhost server implementation

### Keyboard input via keycode dispatch, text via clipboard paste
- Japanese / symbols don't get garbled
- Doesn't depend on IME state
- No key-repeat accidents

### Logs as JSON one event per line
- AI can pipe-process with `tail -f | jq`
- Line-based makes rotation simple
- OTLP migration is also easy

### HTTP Control API supports multiple protocol specs
- ACP (OpenAPI): REST-native, usable immediately with Postman / curl
- A2A (Agent Card): discoverable from Google / ADK ecosystem
- MCP (JSON-RPC 2.0): registerable as MCP server from Claude Desktop / Claude Code
- All auto-generated from the same `ToolCatalog`, so it's 1 implementation / multiple distribution formats

---

## 19. Clean-room design policy

This project aims to make a Mac equivalent of Windows-side FloatingButton (Trifolium Studio), but the following are strictly observed:

- **Do not look at** the original software's code / binary
- **Do not** disassemble / reverse-engineer the original
- References are limited to **the official website's screenshots and feature descriptions**
- Naming / UI colors / icon designs are **intentionally different**

Renaming to `FloatingMacro` is part of differentiating from the original.

---

## 20. Glossary

| Term | Definition |
|---|---|
| Preset | A set of buttons. Switch between them per scene |
| Group | A unit for bundling buttons within a preset |
| Action | One operation that a button executes |
| Macro | Sequential execution of multiple actions |
| Combo | A string combining modifier keys + base key |
| Control API | Operation interface via the localhost HTTP server |
| Tool catalog | Function definition list expressible in 3 dialects: MCP/OpenAI/Anthropic |
| Agent Card | A2A spec self-intro JSON (`/.well-known/agent.json`) |
| MCP | Model Context Protocol (proposed by Anthropic) |
| A2A | Agent-to-Agent protocol (proposed by Google) |
| ACP | Agent Communication Protocol (IBM / BeeAI, REST-based) |

---

## 21. References

### Apple Documentation
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)
- [NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [NWListener](https://developer.apple.com/documentation/network/nwlistener)

### Protocol specs
- MCP (Anthropic): https://modelcontextprotocol.io/specification
- A2A (Google): https://a2aproject.github.io/A2A/specification/
- OpenAPI 3.1: https://spec.openapis.org/oas/v3.1.0
- JSON-RPC 2.0: https://www.jsonrpc.org/specification

### Related tools (inspiration, not implementation reference)
- Keyboard Maestro / BetterTouchTool / Hammerspoon
- FloatingButton (Windows, Trifolium Studio) — external feature specs only
