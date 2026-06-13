# FloatingMacro

> A macOS floating macro launcher with a built-in HTTP control API designed for AI-assisted operation.

[日本語版はこちら](README.ja.md) · [AI Protocol](manual/AI_PROTOCOL.md) · [Specification](SPEC.md) · [Design system](DESIGN.md) · [Changelog](CHANGELOG.md)

---

## What is this?

FloatingMacro is a small always-on-top panel for macOS that runs user-defined
**actions** — key combos, text paste (AI prompt injection), app launches,
terminal expansions, and composite macros — with one click from a
non-activating panel that never steals keyboard focus.

What makes it different from other launcher apps: it ships a **local HTTP
control API** and exposes every feature as a tool in multiple protocol
dialects (MCP / A2A / OpenAI function calling / Anthropic tool use / plain
REST with OpenAPI), so **AI agents can observe, configure, and drive the app
with no additional glue**.

This is a small experiment in what AI-oriented macOS software might look
like. Rather than bolting AI onto an existing app, the question is:
*what happens when you treat an AI agent as a first-class user from day
one* — able to observe, configure, and drive the app without any
extra integration layer? FloatingMacro is one attempt at an answer in the
scope of a tiny utility.

---

## Features

- **Native macOS UI** — SwiftUI + `NSPanel`, respects system accent / dark mode
- **Control from phone / tablet** (v0.13) — tap "📱 Send to Device" from the menu bar or the QR button in each floating panel. Scan the QR code with your phone's camera on the same Wi-Fi, and the panel opens in Safari ready to tap buttons. An open-source alternative to a Stream Deck's soft-key area
- **Multiple floating panels** (v0.12) — independent panels for different use cases, each rendering its own preset with its own position / size / opacity. Add / switch / remove from the menu bar
- **Group display types — icon / wide / card** (v0.11) — buttons can render as small icons, wide cells, or thumbnail cards. The card + `appendMode` combo is ideal for prompt galleries (MidJourney, Stable Diffusion, etc.)
- **Per-button thumbnails** (v0.11) — assign a large image to a card-type button. Stored at `presets/<name>/images/<button-id>.<ext>`
- **6 action types** — key, text, launch, terminal, delay, macro
- **Prompt builder (text appendMode)** (v0.10) — `text` action can append to the current clipboard instead of replacing it. Stack fragments by clicking buttons in sequence, then Cmd+V the full prompt
- **Background app icon cache** (v0.10.5) — icons for every `.app` under `/Applications` are extracted at launch in the background, so app pickers and DnD show icons instantly
- **Launchpad-style app picker** (v0.10.6) — `LazyVGrid` 96px cells; double-click or Enter to add
- **Preset system** — groups and buttons, hot-swappable from the menu bar
- **Preset memo** — record per-preset prerequisites (which app must be frontmost, required OS settings, side effects like clipboard overwrite). Shows as a collapsible block at the top of the panel so future-you can re-confirm before pressing buttons that have stopped working
- **Key recorder & special-key picker** (v0.9.2) — for key-action buttons, capture any keystroke (Delete, arrow keys, F1–F20 included) by pressing it once, or pick from a dropdown. Replaces the awkward "type the key name into a text field" flow that left Delete/arrows unreachable
- **AI integration window** — opens from the menu bar ("Connect AI...") or the ⚙ in the floating panel
  - **One-click MCP registration** for Claude Code / Cursor / Gemini CLI / VS Code / Windsurf
  - Copies a connection prompt with the Bearer token already embedded (so even non-MCP AIs like ChatGPT can drive the app)
  - Existing MCP configs are preserved — entries are merged, not overwritten
- **1700+ icons out of the box**
  - [Lucide](https://lucide.dev) SVG pack bundled (ISC licensed, ~1700 icons)
  - SF Symbols supported at runtime (6000+, curated in-app picker for ~120)
  - App icons auto-resolved from bundle id via `NSWorkspace`
  - Any PNG/JPEG/ICNS path works
- **Structured JSON logging** with rotation, queryable from `fmcli log tail`
- **GUI editor** — full CRUD for presets/groups/buttons, color picker, size, action type
- **Local HTTP control API** bound to `127.0.0.1` only, **Bearer token required**
  - `GET /manifest` — self-introduction for AI agents (unauthenticated)
  - `GET /tools?format=mcp|openai|anthropic` — tool catalog in three dialects
  - `POST /tools/call` — unified dispatch (**use this from AIs**)
  - `POST /mcp` — JSON-RPC 2.0 / Model Context Protocol
  - `GET /openapi.json` — OpenAPI 3.1 document
  - `GET /.well-known/agent.json` — A2A Agent Card

---

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9 toolchain (bundled with Xcode 15+, only if you build from source)
- Accessibility permission (for the key / text / terminal actions)
- Optional: Automation permission (for Terminal.app / iTerm2 control)

---

## Quick start

### Install

Download the DMG from the [releases page](https://github.com/veltrea/floating-macro/releases/latest), mount it, and drag `FloatingMacro.app` into `/Applications`.

To build from source:

```bash
git clone https://github.com/veltrea/floating-macro.git
cd floating-macro
bash scripts/build-app.sh        # produces build/FloatingMacro.app
open build/FloatingMacro.app
```

On first launch, macOS will ask for Accessibility permission. Grant it from
System Settings → Privacy & Security → Accessibility.

### Explore with the CLI

```bash
swift run fmcli help
swift run fmcli config init              # create default config
swift run fmcli preset list
swift run fmcli log tail --since 5m --json
swift run fmcli action launch shell:echo hello
```

### Calling the control API

The control API binds to `127.0.0.1:17430` automatically when the app starts. All endpoints require a Bearer token (except discovery endpoints like `/manifest`). The token is auto-generated on first launch and stored in `~/Library/Application Support/FloatingMacro/control_api_token` (mode 0600), with a Keychain mirror for `security` CLI compatibility — you don't have to set anything up.

```bash
TOKEN=$(cat ~/Library/Application\ Support/FloatingMacro/control_api_token)

# Self-introduction (no auth needed)
curl -s http://127.0.0.1:17430/manifest | jq

# Read state
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/state | jq

# Call a tool (this is the shape AIs should use)
curl -s -X POST http://127.0.0.1:17430/tools/call \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"window_opacity","arguments":{"value":0.7}}'
```

> Hitting individual endpoints like `/window/opacity` directly works but is the lower layer. From AIs, **always go through `/tools/call`**. See [CLAUDE.md](CLAUDE.md) and [AI_PROTOCOL.md](manual/AI_PROTOCOL.md) for the full story.

---

## Using it with an AI agent

### Recommended: one-click registration from the AI integration window

Open the AI integration window from the ⚙ in the floating panel (or the menu bar's "Connect AI...") and press the button on the row of the client you use.

- For Claude Code / Cursor / Gemini CLI / VS Code / Windsurf: **CLI register** (recommended, stdio MCP)
- For the same clients: **HTTP register** (HTTP MCP, advanced)
- For non-MCP AIs like ChatGPT: **Copy connection prompt** (the AI calls `/tools/call` via `curl`)

Pressing the button reads the Bearer token from Keychain and writes the entry into the client's config (`~/.claude.json` / `~/.cursor/mcp.json` / `~/.gemini/settings.json` / etc.). Existing MCP entries are kept.

Per-client guides are in [manual/mcp/](manual/mcp/):
- [Claude Code](manual/mcp/claude-code.md)
- [Claude Desktop](manual/mcp/claude-desktop.md)
- [Cursor](manual/mcp/cursor.md)
- [Gemini CLI](manual/mcp/gemini-cli.md)
- [ACP (via curl)](manual/mcp/acp.md)

### Writing the MCP config by hand

```json
{
  "mcpServers": {
    "floatingmacro": {
      "type": "http",
      "url": "http://127.0.0.1:17430/mcp",
      "headers": {
        "Authorization": "Bearer <token from Keychain>"
      }
    }
  }
}
```

Get the token with `cat ~/Library/Application\ Support/FloatingMacro/control_api_token`.

### Any OpenAI-compatible LLM

```bash
TOKEN=$(cat ~/Library/Application\ Support/FloatingMacro/control_api_token)
curl -s -H "Authorization: Bearer $TOKEN" \
  'http://127.0.0.1:17430/tools?format=openai' | jq '.tools'
```

Paste the returned `tools` array into the `tools` parameter of your Chat
Completions / Responses API call.

### Plain REST from scripts

See [AI_PROTOCOL.md](manual/AI_PROTOCOL.md) for the full endpoint
reference.

---

## Configuration

Configuration lives in `~/Library/Application Support/FloatingMacro/`
(override with `FLOATINGMACRO_CONFIG_DIR`):

```
config.json              # window geometry, active preset, controlAPI settings
presets/
  default.json           # a preset: groups -> buttons -> actions
  writing.json
  dev.json
logs/
  floatingmacro.log      # JSON one-event-per-line, rotates at 10 MB
  floatingmacro.log.old
```

See [SPEC.md §6](SPEC.md) for the full schema. The GUI editor
(Menu Bar → "Button Edit…" or `⌘E`) covers everything you normally need.

> **Don't edit `presets/*.json` by hand while the app is running.** The app overwrites them from in-memory state, so your edits will vanish. Use AI integration (`/tools/call`) or the GUI editor.

---

## Action types at a glance

```json
{ "type": "key",   "combo": "cmd+shift+v" }
{ "type": "text",  "content": "ultrathink" }
{ "type": "launch", "target": "/Applications/Slack.app" }
{ "type": "launch", "target": "com.tinyspeck.slackmacgap" }
{ "type": "launch", "target": "https://claude.ai/code" }
{ "type": "launch", "target": "shell:open ~/Downloads" }
{ "type": "terminal", "app": "iTerm", "command": "cd ~/dev && claude" }
{ "type": "delay", "ms": 300 }
{ "type": "macro", "actions": [ ... ] }
```

---

## Icon references in buttons

```json
{ "icon": "sf:star.fill" }           // SF Symbol (runtime)
{ "icon": "lucide:rocket" }          // bundled Lucide SVG
{ "icon": "com.apple.Safari" }       // macOS bundle id — auto fetch
{ "icon": "/Applications/Slack.app" }// any .app path
{ "icon": "/path/to/custom.png" }    // any image file
```

If `icon` is omitted and the action is a `launch` to an app, the app's icon
is auto-detected.

---

## Testing

```bash
# Unit tests (fast, no permissions required)
swift test

# fmcli smoke (permission-free CLI surface)
bash scripts/fmcli_smoke.sh

# Control API smoke (spins up the GUI + curl against it)
bash scripts/control_api_smoke.sh
```

If `swift test` fails with "no such module XCTest", point `DEVELOPER_DIR`
at Xcode (not Command Line Tools):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

---

## Project layout

```
Sources/
  FloatingMacroCore/     Pure logic, UI-free. Actions, logging, control-API protocol surfaces.
  FloatingMacroCLI/      fmcli binary
  FloatingMacroApp/      GUI (SwiftUI + NSPanel), settings editor, icon loader, AI integration window
Tests/                   Unit tests
scripts/                 Build, smoke-test, release, and translation shell scripts
App/                     Info.plist template for build-app.sh
npm/                     stdio MCP server for CLI registration (bundled in the DMG)
manual/                  User-facing manuals (basic usage, AI examples, images)
.github/                 GitHub Actions workflows (CI)
SPEC.md                  Full specification
DESIGN.md                Design system notes
CHANGELOG.md             Release history
```

---

## Project status

Latest release: **v0.16.5** (2026-05-17). See [CHANGELOG.md](CHANGELOG.md) for the change history and [SPEC.md §17](SPEC.md) for the roadmap. Public release, but the author makes no guarantees of stability.

> **Note on pull requests:** The codebase is currently under heavy active development — typically 1,000–5,000 lines change per day. Pull requests are very likely to conflict before they can be reviewed. Please hold off on PRs until the project enters maintenance mode. Issue reports and feature suggestions are welcome.

> **Intel (x86_64) builds:** Universal binaries including Intel are included in every release, but the author's Intel Mac is currently out of service due to an OS issue. Intel builds are cross-compiled on Apple Silicon and cannot be tested on real hardware for the time being. If you encounter Intel-specific issues, please file an issue.

---

## Credits

- Built with Swift 5.9, SwiftUI, AppKit, Network.framework.
- [Lucide](https://lucide.dev) icons (ISC) are bundled in
  `Sources/FloatingMacroApp/Resources/lucide/`.
- SF Symbols provided by Apple, used at runtime only.
- Inspired by Windows-side utilities such as FloatingButton by Trifolium
  Studio, re-designed from scratch for macOS (clean-room policy — no code
  referenced, only external behavior).

See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for full attribution.

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 veltrea

---

## See also

- [AI Protocol Manual](manual/AI_PROTOCOL.md) — how AI agents talk to this app
- [MCP per-client guides](manual/mcp/) — Claude Code / Cursor / Gemini CLI / etc.
- [Full Specification](SPEC.md)
- [Design System](DESIGN.md)
- [Changelog](CHANGELOG.md)
