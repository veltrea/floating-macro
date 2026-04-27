# FloatingMacro

> A macOS floating macro launcher with a built-in HTTP control API designed for AI-assisted operation.

[日本語版はこちら](README.ja.md) · [AI Protocol](docs/AI_PROTOCOL.md) · [Specification](SPEC.md) · [Design system](DESIGN.md)

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
- **6 action types** — key, text, launch, terminal, delay, macro
- **Preset system** — groups and buttons, hot-swappable from the menu bar
- **1700+ icons out of the box**
  - [Lucide](https://lucide.dev) SVG pack bundled (ISC licensed, ~1700 icons)
  - SF Symbols supported at runtime (6000+, curated in-app picker for ~120)
  - App icons auto-resolved from bundle id via `NSWorkspace`
  - Any PNG/JPEG/ICNS path works
- **Structured JSON logging** with rotation, queryable from `fmcli log tail`
- **GUI editor** — full CRUD for presets/groups/buttons, color picker, size, action type
- **Local HTTP control API** bound to `127.0.0.1` only
  - `GET /manifest` — self-introduction for AI agents
  - `GET /tools?format=mcp|openai|anthropic` — tool catalog in three dialects
  - `POST /tools/call` — unified dispatch
  - `POST /mcp` — JSON-RPC 2.0 / Model Context Protocol
  - `GET /openapi.json` — OpenAPI 3.1 document
  - `GET /.well-known/agent.json` — A2A Agent Card
- **Test coverage**: 241 unit tests + 109 smoke-test assertions, all green

---

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9 toolchain (bundled with Xcode 15+)
- Accessibility permission (for the key / text / terminal actions)
- Optional: Automation permission (for Terminal.app / iTerm2 control)

---

## Quick start

### Build and run

```bash
git clone https://github.com/veltrea/floating-macro.git
cd floating-macro
swift run FloatingMacro
```

On first launch, macOS will ask for Accessibility permission. Grant it from
System Settings → Privacy & Security → Accessibility.

### Explore with the CLI (no permissions required for most commands)

```bash
swift run fmcli help
swift run fmcli config init              # create default config
swift run fmcli preset list
swift run fmcli log tail --since 5m --json
swift run fmcli action launch shell:echo hello
```

### Enable the control API

Edit `~/Library/Application Support/FloatingMacro/config.json`:

```json
{
  "controlAPI": { "enabled": true, "port": 17430 }
}
```

Restart the app, then from any terminal on the same machine:

```bash
curl http://127.0.0.1:17430/manifest | jq
curl http://127.0.0.1:17430/state | jq
curl -X POST http://127.0.0.1:17430/window/opacity -d '{"value":0.7}'
```

---

## Using it with an AI agent

### Claude Desktop / Claude Code (MCP)

Add to your MCP server config (for example `~/.claude.json`):

```json
{
  "mcpServers": {
    "floatingmacro": {
      "url": "http://127.0.0.1:17430/mcp"
    }
  }
}
```

Claude will then discover every tool (`window_move`, `button_add`,
`run_action`, ...) automatically via `tools/list`.

### Any OpenAI-compatible LLM

```bash
curl -s 'http://127.0.0.1:17430/tools?format=openai' | jq '.tools'
```

Paste the returned `tools` array into the `tools` parameter of your Chat
Completions / Responses API call.

### Plain REST from scripts

See [docs/AI_PROTOCOL.md](docs/AI_PROTOCOL.md) for the full endpoint
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
  FloatingMacroApp/      GUI (SwiftUI + NSPanel), settings editor, icon loader
Tests/                   241 unit tests
scripts/                 Smoke-test shell scripts + publish helper
docs/                    AI_PROTOCOL, manual_test
SPEC.md                  Full specification
DESIGN.md                Design system notes
```

---

## Project status

v0.1 — minimum viable product. See [SPEC.md §17](SPEC.md) for the roadmap.
Public release, but the author makes no guarantees of stability. Pull
requests and issue reports are welcome.

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

- [AI Protocol Manual](docs/AI_PROTOCOL.md) — how AI agents talk to this app
- [Manual Test Checklist](docs/manual_test.md) — items that aren't auto-tested
- [Full Specification](SPEC.md)
- [Design System](DESIGN.md)
