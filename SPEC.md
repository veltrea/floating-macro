# FloatingMacro — Specification

Last updated: 2026-04-16

---

## 1. Overview

**FloatingMacro** is a floating macro launcher for macOS. From a small window that stays on screen at all times, users can execute the following with a single click:

- Send keyboard shortcuts
- Paste arbitrary text (via clipboard)
- Launch apps / files / URLs
- Open terminal + auto-type commands
- **Macros** combining the above (sequential execution)

This project takes inspiration from a similar Windows application (FloatingButton by Trifolium Studio) using a clean-room approach, redesigned natively for Mac. No code from the original software is referenced. Only observable behavior and screenshots are used as reference.

### AI-Oriented Design — Treating AI Agents as First-Class Users

FloatingMacro has **enabling AI agents to observe, configure, and operate the app end-to-end** as a design requirement from the start. Rather than bolting AI onto an existing app, this project explores **what design looks like when AI is treated as a first-class user**, within a small utility:

- Logs are JSON, one event per line (AI can pipe-read them)
- Built-in HTTP control API (localhost only, zero external dependencies)
- API is compatible with standard protocols equivalent to ACP / MCP / A2A
- CLI (`fmcli`) can be invoked directly by AI from bash

---

## 2. Target Users and Primary Use Cases

### Target Users
- Users who primarily use pen tablets / trackpads and find it difficult to frequently invoke keyboard shortcuts
- Developers who want to quickly feed prompts to AI agents (Claude Code / Claude CLI, etc.)
- Developers who want to open multiple terminals + navigate directories + launch commands in one shot
- **Developers who want to try AI-first workflows where AI agents are the primary operators of app interactions**

### Primary Use Cases
1. **AI Prompt Injection** — Paste boilerplate prompts like "think with ultrathink" with a single button press
2. **One-Shot Dev Environment Deployment** — Open 4–5 terminals with one button, `cd` to each directory and launch `claude`
3. **Work Scene Switching** — Switch presets to swap between "writing mode" / "dev mode" / "debug mode" button sets
4. **App Launcher** — Group and arrange frequently used apps / folders / URLs (with automatic app icon retrieval)
5. **Remote Control from AI** — Claude / Gemini adds/edits buttons, moves windows, and executes actions via the control API

---

## 3. Non-goals

- Windows / Linux support (Mac only)
- Detailed multi-monitor position memory (to consider in v2+)
- Cloud sync (local config only)
- OCR / image recognition-based automation
- Script language execution engine (one-shot shell commands are fine, but no JS/Python VM)
- Full replacement for existing macro tools (Keyboard Maestro, BetterTouchTool)

---

## 4. Platform / Technology Stack

| Item | Selection |
|---|---|
| Language | Swift 5.9 |
| UI | SwiftUI + AppKit (NSPanel) hybrid |
| Minimum OS | macOS 13 (Ventura) |
| Build | Swift Package Manager |
| Binary | universal (arm64 + x86_64) |
| Dependencies | Standard frameworks only (AppKit / SwiftUI / Carbon / ApplicationServices / Network.framework) |

### Why Swift 5.9
Taking on Swift 6's strict concurrency in the MVP would consume time resolving conflicts between UI and async processing. Migration to 6 is deferred to v2+.

### Why No External Dependencies
Resident tools prioritize startup speed / security / maintainability. Since everything can be implemented with standard frameworks alone, the minimal configuration is maintained. The HTTP server is also self-implemented using `Network.framework`'s `NWListener` (swift-nio / Vapor are not introduced).

---

## 5. Project Structure

```
floatingmacro/
├── Package.swift
├── SPEC.md                       # This document
├── README.md                     # (later)
├── Sources/
│   ├── FloatingMacroCore/        # Pure logic (UI / AppKit dependencies only in Platform/)
│   │   ├── Config/
│   │   │   ├── ButtonDefinition.swift
│   │   │   ├── Preset.swift                  # Preset / ButtonGroup / WindowConfig / ControlAPIConfig / AppConfig
│   │   │   ├── ConfigLoader.swift
│   │   │   ├── ConfigWriter.swift
│   │   │   └── PresetEditor.swift            # preset/group/button CRUD pure logic
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
│   │       ├── SystemPrompt.swift            # Self-introduction prompt for AI + manifest()
│   │       ├── ToolCatalog.swift             # All tool definitions + MCP/OpenAI/Anthropic 3-format conversion
│   │       ├── OpenAPIGenerator.swift        # OpenAPI 3.1 JSON auto-generation
│   │       ├── AgentCard.swift               # A2A Agent Card output
│   │       └── MCPAdapter.swift              # JSON-RPC 2.0 over HTTP (Anthropic MCP)
│   ├── FloatingMacroCLI/
│   │   └── main.swift                        # `fmcli` - CLI test harness + log viewer
│   └── FloatingMacroApp/
│       ├── App.swift                         # AppDelegate
│       ├── FloatingPanel.swift               # NSPanel subclass
│       ├── ButtonView.swift                  # SwiftUI button rendering + icons
│       ├── PresetManager.swift               # ObservableObject + editing API
│       ├── IconLoader.swift                  # NSImage cache + NSWorkspace icon retrieval
│       ├── Settings/
│       │   ├── SettingsView.swift            # SwiftUI settings window root
│       │   ├── SettingsDetail.swift          # Button attribute editing form
│       │   └── SettingsWindowController.swift
│       └── ControlAPI/
│           └── ControlHandlers.swift         # HTTP endpoint implementations (REST + /tools/call + /mcp)
├── Tests/
│   └── FloatingMacroCoreTests/               # 226 tests (as of 2026-04-16)
├── scripts/
│   ├── fmcli_smoke.sh                        # fmcli automated smoke tests (31 items)
│   └── control_api_smoke.sh                  # E2E with real GUI process + curl (78 items)
└── docs/
    ├── manual_test.md                        # Manual visual verification checklist
    └── AI_PROTOCOL.md                        # Connection manual for AI agents
```

**Design Principles**:
- `FloatingMacroCore` has no UI / AppKit dependencies. `import AppKit` is restricted to `Platform/` and below
- All Executors have DI-capable static singletons (`synthesizer`, `clipboard`, `launcher`, `scriptRunner`) that can be swapped with mocks during testing
- All logic can be tested from `FloatingMacroCLI`
- 4-layer testing: unit tests + `fmcli` smoke + control API smoke + manual testing

---

## 6. Configuration File Specification

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
    └── floatingmacro.log.old   # Rotation when exceeding 10MB
```

Can be overridden with the environment variable `FLOATINGMACRO_CONFIG_DIR` (for testing / external disk use).

### 6.2 `config.json` Schema

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

`presetOrder` is the display order in the preset picker. Presets not in the array (e.g., files dropped from external sources) are appended at the end in alphabetical order, and non-existent presets in the array are automatically removed (self-heal). An empty array or missing field falls back to full alphabetical order.

For backward compatibility, all missing fields fall back to default values (`decodeIfPresent`-based).

### 6.3 Preset File (`presets/*.json`) Schema

```json
{
  "version": 1,
  "name": "default",
  "displayName": "Default",
  "memo": "Usage assumptions:\n• Bring the target app to the front before pressing\n• Clipboard history will be briefly overwritten",
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
            "content": "Please work on the next task with ultrathink."
          }
        }
      ]
    }
  ]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `version` | int | No | Schema version (defaults to 1 if omitted) |
| `name` | string | Yes | Internal id (matches filename) |
| `displayName` | string | No | Display name shown in menus, etc. (uses `name` if omitted) |
| `memo` | string? | No | Free-form memo for the entire preset. For noting usage prerequisites, OS settings, intended use cases, etc. Displayed as a collapsible block at the top of the panel. Empty string or missing means "no memo" |
| `groups` | Group[] | Yes | Array of groups |

### 6.4 Button (`buttons[]`) Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | Yes | Unique within the preset |
| `label` | string | Yes | Display string |
| `icon` | string? | No | Image file path (PNG/ICO/ICNS/JPEG) OR app bundle id OR `.app` absolute path |
| `iconText` | string? | No | Emoji / 1–2 character display icon |
| `thumbnail` | string? | No | Large image displayed when parent group's `displayType == "card"`. Absolute path recommended. Convention: save to `presets/<name>/images/<button-id>.{ext}` (added in v0.11) |
| `backgroundColor` | string? | No | `#RRGGBB` or `#RRGGBBAA` hex |
| `width` | number? | No | Explicit width (points). null for auto |
| `height` | number? | No | Explicit height. null for auto |
| `confirm` / `confirmMessage` / `confirmDestructive` | — | No | Confirmation dialog before execution (details in separate section) |
| `action` | Action | Yes | Action on click |

#### Automatic icon resolution
Even when `icon` is not set, if `action.type == "launch"` and `target` is an app path / bundle id, **that target is automatically inferred as the icon** and the app icon is retrieved via `NSWorkspace.icon(forFile:)`. Results are cached in-process.

### 6.5 Group (`groups[]`) Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | Yes | Unique within the preset |
| `label` | string | Yes | Group heading |
| `collapsed` | boolean | No | Collapsed state (default false) |
| `displayType` | string? | No | Button rendering style. `icon` (default) / `wide` / `card`. Missing field treated as `icon` (added in v0.11) |
| `buttons` | Button[] | Yes | Array of buttons |

#### `displayType` Behavior (v0.11)

- **`icon`** (default): Existing compact icon + label. Compact vertical layout
- **`wide`**: Full-width, larger icon + label-centered horizontal cells. Labels wrap up to 2 lines
- **`card`**: Thumbnails + titles arranged in a 2-column `LazyVGrid`. `button.thumbnail` is displayed with priority; falls back to icon → iconText when missing

Since `displayType=icon` is omitted during encoding, existing preset files produce zero diff after loading/saving following Phase 2 release. Only groups with `wide` / `card` set will output `"displayType": "..."` in JSON.

---

## 7. Action Type Specification

All actions are a tagged union identified by the JSON `type` field. Represented as `enum Action` on the Swift side. (Unchanged — details in §7.1–7.6 follow the original spec)

### 7.1 `key` — Key Combo Dispatch

```json
{ "type": "key", "combo": "cmd+v" }
```

Synthesizes keyDown + keyUp via `CGEventCreateKeyboardEvent`, dispatched with `CGEventPost(.cghidEventTap, event)`.

**combo syntax** (`+` delimited):

- Modifier keys: `cmd` (alias: `command`) / `shift` / `option` (alias: `alt`, `opt`) / `ctrl` (alias: `control`)
- Character keys: `a-z`, `0-9`, US layout symbols (`=`, `-`, `[`, `]`, `;`, `'`, `\`, `,`, `.`, `/`, `` ` ``)
- Special keys: `delete` (alias: `backspace`), `forwarddelete`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`, `return` (alias: `enter`), `tab`, `space`, `escape` (alias: `esc`)
- Function keys: `f1`–`f20`

Examples: `cmd+shift+v` / `f5` / `cmd+left` / `option+forwarddelete` / `delete`

**Input from Settings UI** (v0.9.2): The key action editing panel in the edit window includes (a) a **"Press key to record" button** that generates `combo` from a single physical key press, and (b) a **"Special key..." dropdown** that lists the above special keys with labels. Delete, arrow keys, etc. cannot be typed as characters in a TextField, so these input aids are essential for registration.

**Discovery from ACP** (v0.9.2): The `list_key_codes` tool (GET `/key-codes`) returns modifier keys, aliases, special keys, F1–F20, and examples all together. This allows AI to dynamically reference the canonical catalog instead of relying on memorization.

### 7.2 `text` — Text Injection

```json
{
  "type": "text",
  "content": "think with ultrathink",
  "pasteDelayMs": 120,
  "restoreClipboard": true,
  "appendMode": false
}
```

Execution flow (`appendMode: false`, default):
1. Save all clipboard items (all UTI types)
2. Guarantee restoration via `defer` (restores even on synth failure — prevents credential leakage)
3. setString with text
4. Wait `pasteDelayMs`
5. Dispatch Cmd+V via CGEvent synthesis

Execution flow (`appendMode: true`, added in v0.10 — prompt builder):
1. Get current clipboard string (treated as empty string if not string type)
2. Concatenate content to end (no separator — caller controls by including `", "` etc. in content)
3. Write back with setString
4. Does **not** paste, does **not** restore (preserves the concatenated state)

The purpose of `appendMode: true` is **prompt fragment composition** like Midjourney's "style + pose + clothing + background". Press multiple buttons sequentially to build up fragments, then the user manually Cmd+V at the end. Due to backward-compatible decoder, existing preset JSON without the `appendMode` key is loaded as false.

### 7.3 `launch` — App / File / URL Launch

```json
{ "type": "launch", "target": "..." }
```

Target interpretation (priority order):
1. `shell:` prefix → execute via `/bin/sh -c`
2. Contains `://` → `NSWorkspace.open(URL)`
3. `com.xxx.xxx` format → via bundle identifier
4. Absolute path or `~/` → file/folder/app
5. Otherwise → `launchTargetNotFound`

### 7.4 `terminal` — Terminal Launch + Command Input

Terminal.app / iTerm2 use AppleScript; others use NSWorkspace + clipboard paste.

### 7.5 `delay` — Wait

```json
{ "type": "delay", "ms": 500 }
```

### 7.6 `macro` — Sequential Execution of Action Array

Nesting is prohibited (rejected by parser). `stopOnError` controls abort/continue behavior.

---

## 8. Window Specification

### 8.1 Basic Properties

| Item | Specification |
|---|---|
| Window class | `NSPanel` subclass |
| style mask | `.nonactivatingPanel`, `.titled`, `.closable`, `.resizable`, `.fullSizeContentView` |
| level | `.floating` |
| collection behavior | `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary` |
| Focus stealing | Does not steal (canBecomeKey/canBecomeMain = false) |
| Drag movement | Long-press on empty area for free movement |
| Always on top | Default ON |
| Opacity | Default 1.0, variable from 0.25–1.0 (4 levels in menu, any value via API) |
| Position/size persistence | Written back to `config.json` on `applicationWillTerminate` |

### 8.2 Layout

- **Direction**: Vertical stacking (v0.1), horizontal layout planned for future
- **Grouping**: Small header + button rows per group
- **Collapsing**: Click group header to collapse
- **Width/Height**: Default 200×300, user can drag-resize, changeable via API

### 8.3 Menu Bar

- Resident in menu bar via `NSStatusItem`
- Menu items:
  - Show / Hide
  - Preset switching (submenu)
  - **Opacity** (25% / 50% / 75% / 100% submenu, ✓ on current value)
  - **Edit Buttons...** (settings window via `Cmd+E`)
  - Open config folder
  - Reload
  - Quit
- No Dock icon (`LSUIElement = YES`)

---

## 9. Permission Requirements

### 9.1 Accessibility Permission
Required for key event synthesis via `CGEventPost`. Constantly checked with `AXIsProcessTrustedWithOptions`. When not authorized, guides user to settings via `AccessibilityChecker.openSystemPreferences()`.

### 9.2 Automation Permission
Required for AppleScript sending to Terminal / iTerm. `AutomationChecker.check(bundleIdentifier:)` can obtain 4 states: `.authorized / .denied / .notDetermined / .targetUnavailable`.

### 9.3 Code Signing
- MVP: Functional state with self-signing
- v2: Developer ID signing + notarization

---

## 10. Logging

### 10.1 Design Purpose

**Foundation for AI observability**. Logs are designed not for "users checking visually" but primarily for **"AI tailing and auto-judging"**.

- Format: JSON, one event per line (JSONL / ndjson compliant)
- Location: `<ConfigDir>/logs/floatingmacro.log`
- Rotation: Renamed to `.old` when exceeding 10MB
- `fmcli log tail --json` for AI to pipe-read

### 10.2 LogEvent Schema

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

Timestamp is ISO 8601 + fractional seconds (UTC). Keys are sorted output for stability (diffable). `metadata` is `null` when empty.

### 10.3 LogLevel

`debug` < `info` < `warn` < `error` (Comparable by severity). Each Logger has a `minimumLevel`; anything below is dropped.

### 10.4 Logger Types

| Implementation | Purpose |
|---|---|
| `NullLogger` | Default, quiet implementation used until another is explicitly configured in production |
| `InMemoryLogger` | For testing, assertion via `contains(category:messageContains:)` |
| `FileLogWriter` | Production, serialized via DispatchQueue + rotation + `flush()` |
| `ConsoleLogWriter` | For fmcli, human-readable text to stderr |
| `ComposedLogger` | Fan-out to multiple Loggers (file + console) |

Global replacement: `LoggerContext.shared = ...`. In tests, InMemoryLogger is injected in setUp/tearDown.

### 10.5 Log Output Points

- `MacroRunner`: Macro start / completion / error / abort
- Each `*ActionExecutor`: Error details per dispatch / failure
- `ConfigLoader`: Load success / failure
- `ControlServer`: Connection / bind failure
- `ControlAPI` handlers: On failure only

### 10.6 Environment Variables

- `FLOATINGMACRO_CONFIG_DIR` — Override config/log directory
- `FLOATINGMACRO_LOG_LEVEL` — `debug|info|warn|error` (equivalent to CLI `--log-level`)

---

## 11. CLI (`fmcli`)

A command-line tool for verifying logic without launching the UI.

```
fmcli action key "cmd+shift+4"
fmcli action text "Hello World"
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

**Purpose**:
- Test individual actions without UI dependency
- **Minimal path for AI to invoke all features via bash**
- Smoke tests in CI
- Post-hoc analysis via log queries (`--since 5m --level warn --json | jq`)

---

## 12. HTTP Control API

### 12.1 Design Purpose

**Enable AI (Claude / Gemini / others) to observe the app's internal state and execute all features**. Maintains compatibility with agent-to-agent protocols equivalent to MCP / A2A / ACP while implementing with zero external dependencies.

### 12.2 Basic Properties

| Item | Specification |
|---|---|
| Implementation | `Network.framework`'s `NWListener` (no external dependencies) |
| Binding | `127.0.0.1` (loopback) only, `requiredInterfaceType: .loopback` |
| Authentication | None (localhost-only) |
| Protocol | HTTP/1.1, no Keep-Alive (1 connection per request) |
| Format | JSON in / JSON out (UTF-8) |
| Port | Default 17430, fallback +1 up to 10 times on conflict |
| Startup | Only when `controlAPI.enabled` is set, binds on a separate thread **within 1–2 seconds** |

### 12.3 Startup Guidelines (Avoiding MCP Server Pitfalls)

Based on lessons learned from existing MCP server implementations, the following is strictly observed:
- Do not block the main thread (start on DispatchQueue.global)
- Initialization completes within 1–2 seconds (`start(timeout: 2.0)`)
- On failure, the main app continues normal startup (only logs are recorded)
- No new window creation (a "patch onto" existing app model)

### 12.4 Endpoint List

#### Self-Introduction / Discovery
| Method | Path | Purpose |
|---|---|---|
| GET | `/manifest` | Self-introduction for AI to read first + full tool list + systemPrompt |
| GET | `/help` | Alias for `/manifest` |
| GET | `/ping` | Liveness check |
| GET | `/openapi.json` | **OpenAPI 3.1** auto-generated documentation (ACP / REST compatible) |
| GET | `/.well-known/agent.json` | **A2A Agent Card** (Google compatible) |
| GET | `/tools?format=mcp\|openai\|anthropic` | Tool definitions in 3 dialects |

#### Unified Dispatch
| Method | Path | Purpose |
|---|---|---|
| POST | `/tools/call` | Invoke any tool with `{name, arguments}` |
| POST | `/mcp` | **JSON-RPC 2.0 / MCP HTTP transport** (Anthropic compatible) |

#### Window Operations
- `POST /window/show | hide | toggle`
- `POST /window/opacity` — `{value: 0.25..1.0}`
- `POST /window/move` — `{x, y}`
- `POST /window/resize` — `{width, height}`

#### Observation
- `GET /state` — Panel visibility + active preset + window coordinates + errors
- `GET /log/tail?level=&since=&limit=` — JSON, one event per line
- `GET /icon/for-app?bundleId= | path=` — base64 PNG

#### Preset / Group / Button CRUD
- `GET /preset/list`, `GET /preset/current`
- `POST /preset/switch | reload | create | rename | delete | reorder`
- `POST /group/add | update | delete`
- `POST /button/add | update | delete | reorder | move`

#### Action Execution
- `POST /action` — Send Action JSON for immediate execution (202 Accepted)

### 12.5 MCP JSON-RPC Support (`/mcp`)

The following methods can be sent to `POST /mcp` in a JSON-RPC 2.0 envelope:
- `initialize` — Returns serverInfo + capabilities + protocolVersion
- `tools/list` — All tool definitions
- `tools/call` — Dispatches to REST handlers, wraps result as JSON string in `content[].text`
- `ping` — Liveness check

Errors use standard JSON-RPC codes: `-32700/-32600/-32601/-32602/-32603` + app-specific `-32000`.

### 12.6 Security

- **Loopback only** — Unreachable from other hosts
- Dangerous operations (e.g., `terminal` via `/action`) depend on the caller's context awareness
- Text paste with `restoreClipboard: true` restores the clipboard even on failure (prevents leakage of passwords, etc.)

---

## 13. Icon System

### 13.1 `IconResolver` (Core)

Pure logic that resolves string references (`icon` field) into 3 types of cases:

| Case | Determination | Result |
|---|---|---|
| Image file | `.png / .jpg / .icns / .ico / ...` extension + exists | `.imageFile(URL)` |
| `.app` bundle | `.app` extension + exists | `.appBundle(URL)` |
| Bundle ID | `com.xxx.yyy` pattern, no slashes | `.bundleIdentifier(String)` |

### 13.2 `IconLoader` (App)

Converts `IconResolver` results to `NSImage`:
- `.imageFile` → `NSImage(contentsOf: URL)`
- `.appBundle` → `NSWorkspace.icon(forFile:)`
- `.bundleIdentifier` → `NSWorkspace.urlForApplication(withBundleIdentifier:)` + icon

Includes in-process cache. Also retrievable externally as base64 PNG via the API (`/icon/for-app`).

### 13.3 Button Rendering Priority

`MacroButtonView` displays icons in the following order:
1. Explicitly configured `icon`
2. Auto-inferred from `target` when `action.type == "launch"`
3. `iconText` (emoji)
4. None

### 13.4 `icon` Field Prefix Specification

| Prefix | Example | Resolution Method |
|---|---|---|
| `sf:` | `sf:star.fill` | SF Symbol (Apple-provided, `NSImage(systemSymbolName:)`) |
| `lucide:` | `lucide:folder` | **Bundled Lucide SVG** (`Bundle.module`, 1695 icons, ISC) |
| `com.xxx.yyy` | `com.apple.Safari` | macOS app bundle identifier (`NSWorkspace`) |
| Starts with `/` or `~/` | `/Applications/Slack.app` | Absolute path or tilde expansion |

### 13.5 Bundled Lucide Icons

**1695 Lucide SVG icons** are bundled in `Sources/FloatingMacroApp/Resources/lucide/` (**ISC license**, `LICENSE` file also placed in the same directory).

- Total: approximately 0.65 MB
- macOS 13+ `NSImage(contentsOf:)` natively interprets SVG (no external libraries needed)
- Credits: See `DESIGN.md` §10

---

## 14. GUI Settings Screen

### 14.1 Invocation

Menu bar → "Edit Buttons..." or `Cmd+E`. Shares a single NSWindow via `SettingsWindowController.shared.show(presetManager:)`.

### 14.2 Structure

2-column HSplitView:

**Left column** (`SettingsSidebar`):
- Preset selection Picker + add (+) / delete (-)
- Group and button tree (folder icons + selection highlight)
- Group add text field
- Button add button (adds to selected group)

**Right column** (`SettingsDetail`):
- Detailed editing form for selected button:
  - Label
  - iconText (emoji)
  - icon image / app (`NSOpenPanel` for browsing, clear)
  - Background color (SwiftUI `ColorPicker` + bidirectional binding with hex string)
  - Width / Height (auto or numeric)
  - Action (segmented picker: text/key/launch/terminal)
- Delete button / Save button (confirm with Enter)

### 14.3 Consistency Guarantee

GUI editing **internally calls PresetManager's CRUD methods**, so it goes through the exact same path as editing from the HTTP API / fmcli.

---

## 15. Testability

### 15.1 4-Layer Test Structure

| Layer | Target | Count (2026-04-16) | Run Command |
|---|---|---|---|
| Unit | All logic in `FloatingMacroCore` | **226** | `swift test` |
| fmcli smoke | Permission-free CLI surface | **31** | `bash scripts/fmcli_smoke.sh` |
| Control API smoke | E2E with real GUI process + curl | **78** | `bash scripts/control_api_smoke.sh` |
| Manual | GUI visual verification | — | `docs/manual_test.md` |

### 15.2 DI Pattern

All external dependencies (`EventSynthesizer` / `Clipboard` / `AppleScriptRunner` / `WorkspaceLauncher`) are implemented with `Protocol` + `static var`. Swapped wholesale with `TestMocks` during testing:

```swift
override func setUp() {
    mocks = TestMocks()  // Replace all Executor static vars with mocks
}
override func tearDown() {
    mocks.restore()
}
```

### 15.3 Logger Replacement

`LoggerContext.shared = InMemoryLogger()` captures logs in a buffer. Verify firing with `contains(category:messageContains:)`.

### 15.4 HTTP API Testing

- **Unit**: Pure logic of `HTTPParser` / `ToolCatalog` / `MCPAdapter` / `OpenAPIGenerator` / `AgentCard`
- **Integration**: Start `ControlServer` on a random port and access with URLSession
- **E2E**: `scripts/control_api_smoke.sh` launches the real GUI binary and verifies all endpoints via curl

---

## 16. Runtime Environment and Environment Variables

| Variable | Purpose |
|---|---|
| `FLOATINGMACRO_CONFIG_DIR` | Override config/log directory |
| `FLOATINGMACRO_LOG_LEVEL` | Minimum log level (equivalent to CLI `--log-level`) |
| `DEVELOPER_DIR` | Reference Xcode.app when running `swift test` (XCTest is missing with CommandLineTools alone) |

---

## 17. Milestones (Implementation Status as of 2026-04-16)

### MVP (v0.1) — Implemented ✅

- [x] `Package.swift` + 3 targets (Core / CLI / App)
- [x] `Action` enum + JSON parser + nesting prohibition
- [x] `KeyCombo` parser + CGEvent dispatch
- [x] `TextActionExecutor` (clipboard save/restore + guaranteed restoration via defer)
- [x] `LaunchActionExecutor` (shell/URL/bundle/path branching)
- [x] `TerminalActionExecutor` (Terminal / iTerm / generic)
- [x] `MacroRunner` + logging
- [x] `ConfigLoader` / `ConfigWriter` + FLOATINGMACRO_CONFIG_DIR
- [x] `AccessibilityChecker` + `AutomationChecker`
- [x] `fmcli` (action / preset / permissions / config / log)
- [x] SwiftUI + NSPanel floating window
- [x] Vertical button rendering + drag movement
- [x] Menu bar resident (`NSStatusItem`)
- [x] Preset switching menu
- [x] Opacity menu (4 levels)
- [x] Button editing GUI (preset/group/button CRUD + icon/color picker)
- [x] Automatic position/size save/restore
- [x] Banner notification (3 seconds on error)
- [x] Icon display (image file / automatic app inference)
- [x] Structured logging (JSON one event per line + rotation)
- [x] HTTP control API (REST + /tools + /tools/call)
- [x] AI self-introduction `/manifest` + `/help`
- [x] OpenAPI 3.1 auto-generation (`/openapi.json`)
- [x] A2A Agent Card (`/.well-known/agent.json`)
- [x] MCP JSON-RPC 2.0 HTTP transport (`POST /mcp`)

### v0.2 (UI Enhancement)
- [ ] Drag reordering (SwiftUI `.onDrop`)
- [ ] Horizontal layout toggle
- [ ] Preset import / export
- [ ] Window shape presets (small/medium/large)
- [ ] Macro (compound action) GUI editor

### v0.3 (Terminal Enhancement)
- [ ] iTerm pane split macros
- [ ] Warp / Ghostty paste path optimization
- [ ] Terminal profile specification
- [ ] tmux integration

### v0.4 (AI Collaboration Enhancement) — Implemented ✅
- [x] AI-linked window support client extensions (Cursor / Gemini CLI / VS Code / Windsurf)
- [x] MCP stdio transport (bundled `npm/floatingmacro-mcp` within app bundle)
- [x] ACP manifest (`/agents`, `/runs`)

### v0.5 (Accessibility Auto-Recovery + GUI E2E Test Infrastructure) — Implemented ✅
- [x] BinaryIdentity for startup hash comparison + automatic `tccutil reset`
- [x] Permission loss badge + one-click recovery (reset + System Settings open)
- [x] AccessibilityChecker probe improvement (`AXIsProcessTrusted` + `.apiDisabled`-limited counter-signal)
- [x] fm-test-target harness + `text_inject_e2e.sh` (baseline + 2-axis verification)
- [x] `button_press` tool (synthesized real click via AX + CGEvent)
- [x] Bundled presets, import, and export (`SeedPresetInstaller` + ACP API)
- [x] `PresetDirectoryWatcher` (external change detection)

### v0.6 (UX Cleanup + Keychain Removal) — Implemented ✅
- [x] Changed Control API token from Keychain → file-based (`~/Library/Application Support/FloatingMacro/control_api_token`, mode 0600)
- [x] Cleaned up accessibility repair flow (removed NSAlert → unified to OS `prompt:true` only, `openSystemPreferences` fallback after 0.8 seconds, hardened via `/usr/bin/open`)
- [x] Changed repair button to self-restart approach (restart with `--prompt-accessibility` argument for clean-state `prompt:true`)
- [x] Eliminated TCC reset double-firing (removed pre-launch reset from `scripts/rebuild-and-relaunch.sh`, unified to single `BinaryIdentity` firing)
- [x] Right-click menu on mini icon (equivalent to status bar)
- [x] Right-click menu on group headers (delete, add new)
- [x] Extended panel body right-click hit-test to full surface

### v0.7 (Edit Window Integration and DnD Reordering) — Implemented ✅
- [x] DnD reordering in edit window left pane (button movement within/between groups, group reordering)
- [x] Renamed window from "Edit Buttons" → "Edit" (including tabs and menus)
- [x] Unified group add UI with button add (one-click for "New Group", pencil button on row for rename)
- [x] Unified preset/group right-click menus to "Edit..." "Delete...", changed preset "Edit..." to open edit window action
- [x] Added pencil icon to floating panel left of gear icon for edit window
- [x] Group and button right-click "Duplicate" (`PresetManager.duplicateGroup` added, buttons also duplicated with fresh ids)
- [x] Repositioned delete button to left of save button (ButtonEditor / GroupEditor)

### v0.8 (Accessibility Permission Flow Fix and Preset Ordering) — Implemented ✅
- [x] Structurally fixed accessibility permission dialog infinite loop (removed automatic `tccutil reset` call at startup, `prompt: true` only called via `--prompt-accessibility`, removed custom `openSystemPreferences()` and explanatory NSAlert)
- [x] User-changeable preset ordering (right-click "Reorder...", `presetOrder` persistence in `config.json`, Control API `preset_reorder`)
- [x] Added knowledge document `macos_accessibility_permission.md` (Sequoia TCC daemon behavior and workarounds)

### v0.10 (Visual Expansion Phase 1) — Implemented ✅
- [x] Added `appendMode: Bool` to `Action.text` (append mode for prompt builder). Backward-compatible decoder keeps existing presets unchanged
- [x] Added `appendMode` parameter to `TextActionExecutor.execute`. When true, concatenates content to end of current clipboard, does not paste or restore
- [x] Added "Append Mode (Prompt Builder)" checkbox to button edit panel
- [x] Control API: Added `appendMode` field to `text` action schema (default false)
- [x] Drag & drop onto floating panel auto-generates buttons (`.app` → bundle id-based launch, other files → absolute path launch)
- [x] Extracts icons from dropped apps/files via `NSWorkspace.icon(forFile:)`, saves as `presets/<name>/icons/<button-id>.png`
- [x] Visual feedback during drag (accent color thick border)
- [x] Confirmation dialog presents "Adding N items to group" before batch registration
- [x] Added roadmap `docs/plans/visual-expansion-roadmap.md` (phased expansion plan from Phase 1–5)

### v0.10.5 (Phase 1.5: Icon Extraction Infrastructure Rebuild + App Picker) — Implemented ✅
- [x] New `ImageIOIconExtractor` (`FloatingMacroCore/Icons/`). Directly reads `.icns` with `CGImageSource` and converts to PNG, both sync + async APIs. Zero AppKit dependency
- [x] New `AppEntry` / `AppEntryResolver` / `FileSystemAppListProvider` (`FloatingMacroCore/Apps/`). Enumerates `/Applications` / `/System/Applications` / `~/Applications`, reads Info.plist directly for `CFBundleIdentifier` / `CFBundleDisplayName` / `CFBundleName`, deduplicates by Bundle ID, sorts by displayName
- [x] New `AppDropClassifier` / `IconAssetSaver`. Centralizes DnD classification and icon PNG saving in Core. Testable with temp directory via `applicationSupportDirectory:` injection
- [x] Migrated `PanelDropHandler` to Core logic (`NSWorkspace.icon` removed). Remaining AppKit dependency is only NSAlert confirmation dialog
- [x] Added **"Add from App..."** button to settings screen button edit tab, implemented dedicated sheet `AppLauncherPickerSheet.swift`. Search (app name / Bundle ID), async preview of selected icon, instant add via double-click / Enter
- [x] Rejected qlmanage path through practical testing. Tested 4 patterns in `scripts/spikes/qlmanage-pipe-spike/` (anti-pattern / null device / readabilityHandler / background readToEnd), reproduced 20-second hang for Calculator.app (Quick Look daemon issue, not resolved even with daemon restart). Changed direction to ImageIO approach
- [x] Added **NSWorkspace path** to UI layer (`FloatingMacroApp/Settings/NSWorkspaceIconFallback.swift`). For Catalyst / modern apps like UTM (Assets.car-only) and Books (empty .icns placeholder). Core remains Foundation + ImageIO only, AppKit dependency is confined to UI layer. Uses community-standard `NSWorkspace.shared.icon(forFile:)` (orchetect's Gist, etc.)
- [x] **AppIconCache** (Core actor) — memory + disk two-tier cache. Saves to disk at `~/Library/Caches/FloatingMacro/AppIcons/<bundleId>.png`, aligns file mtime with app mtime for automatic invalidation. Thread-safe `contains()` for lightweight hit detection, `get()/put()` guarantees
- [x] **AppIconPrewarmer** (Core) — Parallel prewarming of all app icons from `/Applications` at startup (default parallelism 4). Runs via `Task.detached(priority: .utility)` to not interfere with UI. Called from `applicationDidFinishLaunching`, so nearly all apps are cached by the time the picker is displayed
- [x] **IconContentValidator** (Core) — Inspects PNG bytes / CGImage by decoding at pixel level for "has content". Early returns if it finds even 1 pixel with `alpha > 8` or `RGB > 8`. Reliably rejects "succeeded but empty PNG" from Books.app's icns
- [x] Converted AppLauncherPickerSheet, PanelDropHandler, and AppIconPrewarmer to `async` for cache reference and content inspection. Cascade: shared cache → ImageIO → NSWorkspace. Each stage passes through `IconContentValidator`, thin PNGs (from empty .icns) are demoted to next stage forming an auto-repair loop
- [x] Resolved Phase 1 P1-12 "DnD buttonization E2E test impossible". Core logic (8 files) covered with **46 unit tests** (`AppEntryResolverTests` 7, `FileSystemAppListProviderTests` 7, `AppDropClassifierTests` 6, `IconAssetSaverTests` 4, `ImageIOIconExtractorTests` 5, `AppIconCacheTests` 6, `AppIconPrewarmerTests` 3, `IconContentValidatorTests` 8)
- [x] Documented design guideline "**Foundation-based APIs > GUI-based APIs**" in roadmap Phase 1.5 section and memory (`feedback_prefer_foundation_over_gui_apis`). Used as decision axis for API selection in Phase 2+

### v0.10.6 (Phase 1.5 Finishing: App Picker UI Refresh + Internal Stabilization) — Implemented ✅
- [x] Redesigned app picker sheet (`AppLauncherPickerSheet`) from "list + right preview pane" to **Launchpad-style grid** with `LazyVGrid` 96px cells. Single-click to select, double-click (or "Add" button) for instant add, selected app details shown in bottom footer
- [x] Expanded sheet size from 640×500 → 880×620, 8–9 column display. `LazyVGrid` doesn't trigger icon extraction for off-screen cells, maintaining the startup prewarm cache-first design
- [x] Added `AppIconCache.mtimeStillValid(cached:app:)` and applied **1.0 second tolerance** to mtime comparison in `get()` / `contains()`. Resolved flaky `testDiskCachePromotesToMemoryAcrossInstances` caused by APFS sub-second truncation or clock jitter
- [x] Updated `ConfigIOTests.testWriteDefaultConfigCreatesConfigAndDefaultPreset` default preset first button expectation from `btn-ultrathink` → `btn-ai-copy-prompt`

### v0.13.0 (Phase 5: Multi-Device) — Implemented ✅
- [x] **LAN Exposure Mode**: `ControlAPIConfig.lanExposureEnabled` toggle. When enabled, expands bind scope to `0.0.0.0`, authenticates with ephemeral LAN token (expires on restart)
- [x] **Web Panel** (`/webpanel`): SSR + HTML/CSS/JS panel UI for mobile browsers. Auto-detects card / icon-card, critical CSS inline + skeleton for immediate first paint
- [x] **QR / Bonjour / mDNS**: Menu bar "📱 Send to Device..." + floating top-right QR button. Zero-config detection via `_floatingmacro._tcp.` advertisement
- [x] **WebP Delivery**: Thumbnail encoding via libwebp (SwiftPM, BSD-3). Transfer size approximately 1/100 of original PNG
- [x] **Concurrent Processing**: Independent queue per connection + main bypass fast path. App Nap suppression
- [x] **`WebPanelToolWhitelist`**: Limits tools callable from Web Panel to safe ones like `button_press` (destructive tools return 403)
- [x] **`preset_get` tool added**: Read-only retrieval of non-active presets
- [x] **Management Endpoints**: `GET /lan-token`, `POST /lan-token/rotate`
- [x] **Tests**: 421 tests passing (+62 added in Phase 5)
- [x] **Version bump**: Info.plist `0.13.0` / build `24`, `SystemPrompt.version`, `CHANGELOG.md` v0.13.0 section added

### v0.16.3 (Localization Infrastructure: Externalizing Tool Descriptions & Manifest) — Implemented ✅
- [x] **Tool description JSON externalization**: Separated descriptions for 50 tools + ~70 parameters into `tool_descriptions.json`. `ToolCatalog.swift` uses 2-tier JSON load → fallback structure
- [x] **Bilingual manifest & ACP**: `SystemPrompt.swift` endpoint tables and helpTool descriptions, `ACPManifest.swift` agent description and tool_invocation_format now in EN/JP
- [x] **UI dialog L() conversion**: Converted 12 hardcoded confirmation dialog locations in `ButtonView.swift` to `L()` / `L_()` calls
- [x] **Version bump**: Info.plist `0.16.3` / build `33`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.3 section added

### v0.16.2 (Internal Refactoring: Large File Splitting) — Implemented ✅
- [x] **Split `ControlHandlers.swift` (2,235 lines) into 7 files**: Main body (613 lines) + WebPanel / Panel / Settings / Preset / ButtonGroup / ACP as 6 extensions. Stored properties remain in main body due to Swift constraints, only methods moved to extensions
- [x] **Split `App.swift` (1,736 lines) into 5 files**: Main body (623 lines) + `ContentHostView` standalone + ContextMenu / Dock / LANBonjour as 3 AppDelegate extensions. `@objc` methods kept in main body for selector binding safety
- [x] **Split `SettingsDetail.swift` (1,676 lines) into 5 files**: Main body (121 lines) + ButtonEditor / GroupEditor / MacroStep / KeyRecorders separated
- [x] **Split `PresetManager.swift` (1,194 lines) into 6 files**: Main body (266 lines) + PresetIO / ExternalRequest / PanelOps / Editing / ImportExecute as 5 extensions. `@Published` and other stored properties consolidated in main body
- [x] **Split `SettingsView.swift` (1,181 lines) into 5 files**: Main body (129 lines) + SecuritySettingsView / SettingsSidebar / PresetReorderSheet / RowDropDelegate separated
- [x] **Max line count reduced from 2,235 → 778**. No changes to public API / protocols / behavioral specs. Verified with `swift build`, smoke tested with `/ping` `/state` `/preset/list`
- [x] **Version bump**: Info.plist `0.16.2` / build `32`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.2 section added

### v0.16.1 (Card Layout Top Alignment Fix) — Implemented ✅
- [x] **Card top alignment**: Fixed label text area to fixed height so card tops align per row within WaterfallGrid
- [x] **Version bump**: Info.plist `0.16.1` / build `31`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.1 section added

### v0.16.0 (Grid Display + i18n + Preset Storage Separation) — Implemented ✅
- [x] **Grid display type added**: `GroupDisplayType.grid` (Finder/Launchpad-style icon arrangement)
- [x] **Column count specification**: `ButtonGroup.columns` allows `auto` / `fixed(1/2/3)` selection (CSS Grid minmax equivalent)
- [x] **Icon size selection**: `IconSize` enum (small 16pt / medium 32pt / large 48pt / xlarge 64pt)
- [x] **Label visibility toggle**: `ButtonGroup.showLabels` controls label display for icon/grid modes
- [x] **i18n infrastructure**: `L10n.swift` helper, `Localizable.strings` (en/ja) with 335 entries each, `scripts/localize.py` for automated hardcoded string extraction and replacement
- [x] **Preset storage separation**: Physical separation into seed (`~/Library/Application Support/FloatingMacro/presets/`) and user (`~/Documents/FloatingMacro/presets/`). Copy-on-write on edit
- [x] **Environment variable added**: `FLOATINGMACRO_USER_DIR` for overriding user directory
- [x] **Basic manual**: `docs/manual-basic.md` (with screenshots)
- [x] **Card/grid scroll area calculation fix**: Replaced `LazyVGrid` with `paololeonardi/WaterfallGrid` (MIT). Height aggregation into NSScrollView now works correctly, enabling vertical scrolling even when displaying many cards with image thumbnails
- [x] **Panel header long preset name handling**: Removed horizontal fixing of Menu label, now displays with trailing ellipsis (…)
- [x] **Version bump**: Info.plist `0.16.0` / build `30`, `SystemPrompt.version`, `CHANGELOG.md` v0.16.0 section added

### v0.15.1 (Bug Fix: Dock Bar Direction Detection) — Implemented ✅
- [x] **DockBarPosition retains edge**: Saves direction during drag movement, prioritizes saved edge on re-dock
- [x] **EdgeDetector clamp fix**: Fixed bug where distance went negative when panel center was outside visibleFrame, causing unintended edge selection

### v0.15.0 (Phase 3.5 Enhancement + Panel Background Color) — Implemented ✅
- [x] **Panel background color customization**: Background color changeable per preset (`WindowConfig.backgroundColor` saved as `#RRGGBB` hex). Right-click menu "Background Color ▸", color picker added to settings screen panel tab. Control API: `panel_background_color` tool added
- [x] **Dock transition animation**: Added border-outlined rectangle overlay slide + fade animation for panel → dock bar transition (`DockTransitionAnimator`)
- [x] **Dock bar drag movement**: Dock bars can now be freely moved by dragging. Position persisted in `PanelConfig.dockBarPosition`. Custom position preserved on expand → re-dock. Off-screen drag prevention clamp
- [x] **Panel restore changed to double-click**: Prevents unintended expansion from accidental taps
- [x] **× button vs. yellow button differentiation**: × button collapses to round icon, yellow button Edge Docks
- [x] **Recovery operations**: Added "Reset Position" and "Gather Dock Bars" to right-click menu "Panel ▸". Control API: `panel_reset_dock_position` / `panel_gather_dock_bars` tools added
- [x] **Tests**: All 445 tests passing

### v0.14.0 (Phase 3.5: Edge Dock Minimization) — Implemented ✅
- [x] **`DockEdge` enum** (left/right/top/bottom) added to `Preset.swift`
- [x] **`PanelConfig.minimizedToEdge: Bool`** → **`PanelConfig.dockedEdge: DockEdge?`** type change. Decoder auto-migrates old JSON `minimizedToEdge: true` to `.right`. Encodes only `dockedEdge`, old key not retained
- [x] **`AppConfig+Panels`** adds `dockingPanel(id:edge:)` / `undockingPanel(id:)`. Removed old `settingPanelMinimizedToEdge`
- [x] **`EdgeDetector`** (Core layer): Pure function that determines nearest edge from panel center coordinates
- [x] **`EdgeDockLayout`** (Core layer): Pure function that calculates center-aligned positions for bars on the same edge
- [x] **`EdgeDockBar`** (App layer): Thin bar attached to screen edge. Purple gradient background, icon + label, left-click to expand, right-click for menu
- [x] **PanelManager extensions**: `collapseToDock` / `expandFromDock` / `relayoutDockBars`, added `dockBar` to Entry
- [x] **× button** behavior changed from MiniIconPanel to edge docking
- [x] **Menu bar** adds "Dock to Edge ▸" submenu, docked panels get "Expand" and "Move to Another Edge ▸"
- [x] **Control API**: Added `panel_dock` / `panel_undock` handlers, `panel_list` response `minimizedToEdge` → `dockedEdge`
- [x] **Startup restoration**: Panels in docked state are restored as `EdgeDockBar`
- [x] **Tests**: EdgeDetectorTests (6), EdgeDockLayoutTests (7), legacy migration tests (3), dock operation tests (3), ToolCatalog (3). All 445 tests passing

### v0.12.0 (Phase 3: Multi-Panel) — Implemented ✅
- [x] **`PanelConfig`** struct and **`AppConfig.panels: [PanelConfig]`** field added (`Sources/FloatingMacroCore/Config/Preset.swift`). 1 panel = id (UUID) + presetName + WindowConfig + visible + minimizedToEdge
- [x] **v1 → v2 auto-migration**: JSON with old `activePreset` + single `window` generates `panels[0]` via decoder and writes back. Legacy fields are also written in sync with `panels[0]`, allowing both formats to coexist during Phase 3 transition
- [x] **`AppConfig+Panels.swift`** extension provides pure functions (addingPanel / removingPanel / updatingPanelFrame / updatingPanelOpacity / settingPanelPreset / settingPanelVisible / withSyncedLegacyFields). AppKit-independent and unit-testable
- [x] **`PanelManager`** class (`Sources/FloatingMacroApp/PanelManager.swift`): Manages id → (FloatingPanel, MiniIconPanel) map. openInitial / openNew / close / collapseToMini / expandFromMini / toggle / setOpacity / currentFrames, internalized `floatingPanelWantsCollapse` notification subscription
- [x] **AppDelegate reconcile sink**: Monitors `presetManager.$appConfig.panels` via Combine sink, auto-reflects additions/deletions to NSWindow creation/destruction. Unified regardless of whether panel operations come from menu bar, settings screen, or Control API
- [x] **Per-panel preset rendering**: Refactored `ContentHostView` to accept `panelID`. Each panel can display a different preset via `presetManager.panelPreset(forPanelID:)`
- [x] **`PresetManager.loadedPresets`** multi-preset cache (`@Published`) with `preset(named:)` / `panelPreset(forPanelID:)` / `switchPanelPreset(panelID:to:)` / `setEditTarget(panelID:)`
- [x] **Menu bar "Panels" submenu**: Add new panel / toggle visibility / close and remove
- [x] **Settings screen "Panels" tab** (`PanelsSettingsView.swift`): Panel list + preset switching + deletion
- [x] **Control API panel_* tools** 5 types added to ToolCatalog: `panel_list` / `panel_create` / `panel_close` / `panel_show` / `panel_hide`. `window_*` relabeled as "DEPRECATED: prefer panel_*" with semantics redirected to primary panel
- [x] **Tests**: 6 Phase 3 cases in `ConfigLoaderTests` (PanelConfig round-trip, minimal JSON, auto-generated id, v1 migration, empty array migration, multiple panels, explicit panels priority). 14 cases in `AppConfigPanelOpsTests` (add/remove/update/legacy sync). panel_* registration, window_* deprecation, panel_create schema verification added to `ControlAPICatalogTests`. All 349 tests passing
- [x] **Version bump**: Info.plist `0.12.0` / build `21`, `SystemPrompt.version`, `CHANGELOG.md` v0.12.0 section added

### v0.11.0 (Phase 2: Expanding Expressiveness) — Implemented ✅
- [x] **`GroupDisplayType`** enum (`icon` / `wide` / `card`) and `ButtonGroup.displayType` field added. Backward-compatible decoder auto-treats old presets as `.icon`. `.icon` is omitted during encoding (zero diff)
- [x] **`ButtonDefinition.thumbnail`** field added. Path for large images used in card type. Falls back to icon → iconText when null
- [x] **Wide / Card renderers** implemented as `buttonContent` branching in `MacroButtonView`. `.wide` is full-width large cells, `.card` arranges "thumbnail + title" vertically in a `LazyVGrid(adaptive: 96)` gallery
- [x] **State reflection indicators** (P2-9/P2-10): `ExecutionFeedback` state machine for press → yellow border (executing, 250ms) → green border (success 800ms) → idle animation. Failure (red) pending wiring after `executeButton` return value cleanup
- [x] **`IconAssetSaver`** adds `imagesDirectory(presetName:)` and `saveThumbnail(_, buttonId:, ext:)`. Provides saving convention `presets/<name>/images/<button-id>.<ext>`
- [x] **Settings UI**: Segmented picker for `displayType` in `GroupEditor`, thumbnail input + file browse + preview frame in `ButtonEditor`
- [x] **Control API**: Added `displayType` (`icon`|`wide`|`card`) to `group_add` / `group_update`, `thumbnail` (string | null) to `button_add` / `button_update`
- [x] **Existing bug fix**: Fixed path where `applyPatch` wasn't passing `confirm` / `confirmMessage` / `confirmDestructive` to `updateButton`. Phase 2's `thumbnail` also passes through the same path
- [x] **Tests**: Added `testButtonGroupDisplayTypeRoundTrip` / `testButtonGroupDefaultDisplayTypeOmittedFromEncoding` / `testButtonGroupLegacyJSONWithoutDisplayType` / `testButtonDefinitionThumbnailRoundTrip` to `ConfigLoaderTests`. Added `testSaveThumbnailWritesToImagesDirectory` / `testImagesDirectoryPath` to `IconAssetSaverTests`. All 317 tests passing
- [x] **Version bump**: Info.plist `0.11.0` / build `19`, `SystemPrompt.version`, `CHANGELOG.md` v0.11.0 section added

### Future (Unassigned)
- [ ] A2A Task API + SSE streaming (for long-running macros)
- [ ] `fmcli remote` subcommand (thin wrapper around control API)
- [ ] Log OpenTelemetry OTLP export
- [ ] Horizontal layout toggle
- [ ] iTerm pane split macros
- [ ] Warp / Ghostty paste path optimization
- [ ] tmux integration

### v1.0
- [ ] Developer ID signing + notarization
- [ ] Distribution DMG
- [ ] Auto-update

---

## 18. Known Design Decisions

### Why Swift Instead of Tauri
- No need for cross-platform capability since it's Mac-only
- `NSPanel` non-activation behavior is one line in Swift, requires objc bridge in Tauri
- `NSAppleScript` / `NSWorkspace` / `CGEvent` / `AXIsProcessTrusted` / `NWListener` are all immediately accessible natively

### Why Not swift-nio / Vapor
- Don't want to increase startup time for a resident tool
- Adding dependencies complicates maintenance
- `NWListener` is sufficient for implementing an HTTP/1.1 localhost server

### Key Input via Keycode Dispatch, Text via Clipboard Paste
- No corruption with Japanese / symbols
- No dependency on IME state
- No key repeat accidents

### Logs as JSON One Event Per Line
- AI can pipe-process with `tail -f | jq`
- Line-based makes rotation simple
- Easy migration to OTLP

### HTTP Control API Supports Multiple Protocol Specifications
- ACP (OpenAPI): REST-native, immediately usable with Postman / curl
- A2A (Agent Card): Discoverable from Google / ADK ecosystem
- MCP (JSON-RPC 2.0): Registrable as MCP server from Claude Desktop / Claude Code
- All auto-generated from the same `ToolCatalog`, so implementation is 1 set / distribution is multiple formats

---

## 19. Clean-Room Design Policy

This project aims to create a Mac equivalent of the Windows FloatingButton (Trifolium Studio), but strictly adheres to the following:

- **Do not view** the original software's code / binaries
- **Do not** disassemble / reverse-engineer the original software
- Reference sources are **only official website screenshots and feature descriptions**
- Name / UI color scheme / icon design are **intentionally different**

Changing the name to `FloatingMacro` is also part of differentiating from the original software.

---

## 20. Glossary

| Term | Definition |
|---|---|
| Preset | A set of buttons. Switched between scenes |
| Group | A unit for organizing buttons within a preset |
| Action | A single operation executed by a button |
| Macro | Sequential execution of multiple actions |
| Combo | A string combining modifier keys + main key |
| Control API | Operation interface via localhost HTTP server |
| Tool Catalog | Feature definition list expressible in MCP/OpenAI/Anthropic 3 dialects |
| Agent Card | A2A specification self-introduction JSON (`/.well-known/agent.json`) |
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

### Protocol Specs
- MCP (Anthropic): https://modelcontextprotocol.io/specification
- A2A (Google): https://a2aproject.github.io/A2A/specification/
- OpenAPI 3.1: https://spec.openapis.org/oas/v3.1.0
- JSON-RPC 2.0: https://www.jsonrpc.org/specification

### Related Tools (inspiration, not implementation reference)
- Keyboard Maestro / BetterTouchTool / Hammerspoon
- FloatingButton (Windows, Trifolium Studio) — External feature specs only used as reference
