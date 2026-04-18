# FloatingMacro — AI Agent Protocol Manual

**Audience**: AI agents (Claude / Gemini / GPT etc.) and the developers who
host them. Human-facing design docs live in `SPEC.md`. Manual QA items live
in `docs/manual_test.md`.

> 日本語版: [AI_PROTOCOL.ja.md](AI_PROTOCOL.ja.md)

---

## 0. TL;DR — what should an AI do first?

```bash
# 1. Make sure FloatingMacro is running with controlAPI.enabled = true
#    in its config.json.

# 2. Check liveness
curl http://127.0.0.1:17430/ping

# 3. Always read /manifest first. It returns the system prompt + tool
#    catalog + quick start in one round trip.
curl -s http://127.0.0.1:17430/manifest | jq

# 4. Inspect state
curl -s http://127.0.0.1:17430/state | jq

# 5. Invoke a tool through the unified dispatch
curl -X POST http://127.0.0.1:17430/tools/call \
    -H 'Content-Type: application/json' \
    -d '{"name":"window_opacity","arguments":{"value":0.7}}'

# 6. Verify via logs
curl -s 'http://127.0.0.1:17430/log/tail?since=1m&level=info' | jq
```

---

## 1. What you should know about this app

FloatingMacro is a macOS floating macro launcher designed so that an AI
agent is treated as a first-class user. You are expected to drive the app
end-to-end via this API rather than asking a human to operate the GUI.

**Expected behavior from the AI**:

- Prefer calling the HTTP API over asking the user to run commands or click
  things themselves.
- Run the loop "observe → decide → execute → re-observe" autonomously.
- When in doubt, call the `help` tool to re-read the manifest.

---

## 2. How to connect

### 2.1 HTTP (preferred — ACP style)

```
Base URL: http://127.0.0.1:17430
```

- TCP socket, bound to loopback only (unreachable from other hosts)
- No auth (localhost-only)
- HTTP/1.1, `Content-Type: application/json` expected
- No keep-alive (one request per connection)
- Port falls through `port+1..port+9` on collision. The actual bound port
  appears in startup logs as `ControlServer Started on 127.0.0.1:NNNNN`.

### 2.2 MCP (Anthropic standard)

```
POST http://127.0.0.1:17430/mcp
Content-Type: application/json

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
```

Register `http://127.0.0.1:17430/mcp` in Claude Desktop / Claude Code's MCP
config and every tool becomes available as native tool use.

### 2.3 OpenAI function calling / Anthropic tool use

To inject the tool catalog into an LLM call, fetch and paste:

```
GET /tools?format=openai     # OpenAI Chat Completions "tools"
GET /tools?format=anthropic  # Anthropic Messages "tools"
GET /tools?format=mcp        # MCP (default)
```

---

## 3. First thing you must do — `GET /manifest`

```bash
curl -s http://127.0.0.1:17430/manifest
```

The response contains everything needed to bootstrap in one round trip:

```json
{
  "product": "FloatingMacro",
  "version": "0.1",
  "systemPrompt": "...behavioral guidance for AI agents...",
  "quickStart": ["GET /manifest", "GET /state", ...],
  "endpoints": [{ "method": "GET", "path": "/manifest", "desc": "..." }, ...],
  "dialects": {
    "mcp":       "/tools?format=mcp",
    "openai":    "/tools?format=openai",
    "anthropic": "/tools?format=anthropic"
  },
  "helpTool": {
    "call": { "name": "help", "arguments": {} },
    "description": "Call any time to re-read the manifest."
  },
  "tools": [
    { "name": "window_move", "description": "...", "inputSchema": {...} },
    ...
  ]
}
```

**When in doubt, call the `help` tool** (identical to `GET /manifest`):

```json
POST /tools/call
{"name": "help", "arguments": {}}
```

---

## 4. Three ways to invoke tools

The same functionality has three entry points. Pick per use case.

### 4.1 Direct REST (lightest)

```bash
curl -X POST http://127.0.0.1:17430/window/move \
    -H 'Content-Type: application/json' \
    -d '{"x": 100, "y": 200}'
```

### 4.2 Unified dispatch via `/tools/call` (recommended, declarative)

```bash
curl -X POST http://127.0.0.1:17430/tools/call \
    -H 'Content-Type: application/json' \
    -d '{"name":"window_move","arguments":{"x":100,"y":200}}'
```

Response envelope:

```json
{
  "name":   "window_move",
  "status": 200,
  "result": { "x": 100, "y": 200 }
}
```

### 4.3 MCP JSON-RPC 2.0 via `/mcp` (Claude-native)

```bash
curl -X POST http://127.0.0.1:17430/mcp \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"window_move","arguments":{"x":100,"y":200}}}'
```

Response (per MCP `tools/call` spec):

```json
{
  "jsonrpc": "2.0",
  "id":      1,
  "result": {
    "content": [{ "type": "text", "text": "{\"x\":100,\"y\":200}" }],
    "isError": false
  }
}
```

---

## 5. Tool catalog summary

**The full definitions come from `GET /tools`.** This section is a summary.

### Discovery
- `help` / `manifest` — re-fetch the manifest

### Health / state
- `ping` — liveness probe
- `get_state` — panel visibility, active preset, window geometry

### Window
- `window_show` / `window_hide` / `window_toggle`
- `window_opacity` `{value: 0.25..1.0}`
- `window_move` `{x, y}`
- `window_resize` `{width, height}` (width ≥ 120, height ≥ 80)

### Preset
- `preset_list` / `preset_current`
- `preset_switch` `{name}`
- `preset_reload`
- `preset_create` `{name, displayName}`
- `preset_rename` `{name, displayName}`
- `preset_delete` `{name}`

### Group
- `group_add` `{id, label, collapsed?}`
- `group_update` `{id, label?, collapsed?}`
- `group_delete` `{id}`

### Button
- `button_add` `{groupId, button: ButtonDefinition}`
- `button_update` `{id, label?, icon?, iconText?, backgroundColor?, width?, height?, action?}`
- `button_delete` `{id}`
- `button_reorder` `{groupId, ids: [String]}`
- `button_move` `{id, toGroupId, position?}`

### Action execution
- `run_action` — run an Action JSON immediately (returns 202; inspect logs)

### Observation
- `log_tail` `{level?, since?, limit?}` — JSON one event per line
- `icon_for_app` `{bundleId? | path?}` — base64 PNG

### Settings window (basic)
- `settings_open` — open the Settings window
- `settings_close` — close the Settings window
- `settings_open_sf_picker` — open Settings and show the SF Symbol picker sheet
- `settings_move` `{x, y}` — move the Settings window to the given screen coordinates (AppKit origin: bottom-left)
- `arrange` `{open_settings?}` — tile the floating panel and Settings window so they don't overlap; pass `open_settings:true` to also open Settings

### Settings window (test automation / AI control)

These tools let the AI drive the Settings UI directly without taking
screenshots. They were added because previous automated tests got stuck
waiting for a human to click Save or select items.

- `settings_select_button` `{id}` — select a button by id, opening ButtonEditor (opens Settings if closed)
- `settings_select_group` `{id}` — select a group by id, opening GroupEditor (opens Settings if closed)
- `settings_clear_selection` — deselect, closing ButtonEditor / GroupEditor
- `settings_commit` — press the Save button in the open ButtonEditor / GroupEditor
- `settings_open_app_icon_picker` — open the app-icon picker sheet (opens Settings if needed)
- `settings_dismiss_picker` — close any open picker sheet (icon picker or SF Symbol picker)
- `settings_set_background_color` `{color?, enabled?}` — set background color; `{enabled:false}` to disable. Bypasses the macOS color wheel (which cannot be controlled via API)
- `settings_set_text_color` `{color?, enabled?}` — set text/icon color; `{enabled:false}` to restore automatic
- `settings_set_action_type` `{type}` — switch the action type tab (`text` | `key` | `launch` | `terminal`). ButtonEditor only
- `settings_set_key_combo` `{combo?, cmd?, shift?, option?, ctrl?, key?}` — configure the button to send a keyboard shortcut when clicked. Accepts a combo string (`"combo":"cmd+shift+v"`) or individual modifier flags. Switches the action type to `key` automatically. ButtonEditor only
- `settings_set_action_value` `{type, value}` — set the text content, launch target, or terminal command. Switches the action type tab to match. Use `settings_set_key_combo` for key actions. ButtonEditor only

---

## 6. Action JSON shape

Used by `run_action` and by the `action` field of `button_add` / `button_update`:

```json
// Key combo — sends the shortcut to the active application when clicked
{ "type": "key", "combo": "cmd+shift+v" }

// Text paste (via clipboard, always restored)
{
  "type": "text",
  "content": "ultrathink",
  "pasteDelayMs": 120,
  "restoreClipboard": true
}

// App / URL / shell launch
{ "type": "launch", "target": "/Applications/Slack.app" }
{ "type": "launch", "target": "com.tinyspeck.slackmacgap" }
{ "type": "launch", "target": "https://claude.ai/code" }
{ "type": "launch", "target": "shell:open ~/Downloads" }

// Terminal + command
{
  "type": "terminal",
  "app": "iTerm",
  "command": "cd ~/dev && claude",
  "newWindow": true,
  "execute": true
}

// Delay (only meaningful inside a macro)
{ "type": "delay", "ms": 500 }

// Macro (nesting disallowed)
{
  "type": "macro",
  "actions": [
    { "type": "terminal", "command": "cd /proj && claude", "newWindow": true },
    { "type": "delay", "ms": 300 },
    { "type": "terminal", "command": "cd /other && claude", "newWindow": true }
  ],
  "stopOnError": true
}
```

---

## 7. How to read the logs — essential for AI

Internal state and every failure goes into the structured log. **The AI
should check logs after every action.**

```bash
# Warnings and above in the last 5 minutes
curl -s 'http://127.0.0.1:17430/log/tail?level=warn&since=5m' | jq

# Most recent 20 events of any level
curl -s 'http://127.0.0.1:17430/log/tail?limit=20' | jq
```

Event shape:

```json
{
  "timestamp": "2026-04-16T00:30:00.123Z",
  "level":     "warn",
  "category":  "KeyAction",
  "message":   "Key dispatch failed",
  "metadata": {
    "keyCode": "9",
    "error":   "accessibilityDenied"
  }
}
```

### Categories

- `MacroRunner` — macro progression
- `KeyAction` / `TextAction` / `LaunchAction` / `TerminalAction` — per executor
- `ConfigLoader` — config IO
- `ControlServer` — HTTP server
- `ControlAPI` — individual endpoints

---

## 8. Error handling

### 8.1 REST / `/tools/call` errors

HTTP status + JSON body:

```json
{ "error": "unknown tool", "name": "no_such_tool" }  // 404
{ "error": "body must contain {id: String}" }         // 400
```

### 8.2 MCP errors

Standard JSON-RPC 2.0 codes:

| Code | Meaning | When this server emits it |
|---|---|---|
| -32700 | Parse error | Malformed JSON |
| -32600 | Invalid Request | Missing `jsonrpc:2.0` or `method` |
| -32601 | Method not found | Unknown method / unknown tool |
| -32602 | Invalid params | Missing `name`, etc. |
| -32603 | Internal error | Server-side failure |
| -32000 | Tool failed | The underlying REST handler returned non-2xx (details in `data`) |

### 8.3 Common failures and fixes

| Symptom | Cause | Fix |
|---|---|---|
| `GET /ping` times out | controlAPI disabled or port collision | Check `config.json` `controlAPI.enabled`, inspect startup logs |
| `run_action { key }` is silent | Accessibility permission not granted | `log/tail?level=error` shows `accessibilityDenied`. AI cannot grant this — ask user |
| `button_update` fails | Unknown `id` | Fetch `preset_current` to see real ids |
| Screen doesn't update after `preset_switch` | Redraw timing | Call `preset_reload` to force |

---

## 9. Typical workflows

### 9.1 Add a Slack-launcher button

```bash
# 1. Inspect current preset shape
curl -s http://127.0.0.1:17430/preset/current | jq

# 2. Add the button
curl -X POST http://127.0.0.1:17430/tools/call \
    -H 'Content-Type: application/json' \
    -d '{
      "name": "button_add",
      "arguments": {
        "groupId": "group-1",
        "button": {
          "id": "btn-slack",
          "label": "Slack",
          "icon": "com.tinyspeck.slackmacgap",
          "backgroundColor": "#4A154B",
          "width": 140,
          "height": 36,
          "action": {
            "type": "launch",
            "target": "com.tinyspeck.slackmacgap"
          }
        }
      }
    }'

# 3. Verify
curl -s http://127.0.0.1:17430/preset/current \
    | jq '.preset.groups[0].buttons[] | select(.id=="btn-slack")'

# 4. Check for warnings
curl -s 'http://127.0.0.1:17430/log/tail?since=1m&level=warn' | jq
```

### 9.2 Pin the panel to top-right

```bash
curl -X POST http://127.0.0.1:17430/window/resize -d '{"width":180,"height":400}'
curl -X POST http://127.0.0.1:17430/window/move   -d '{"x":1700,"y":900}'
```

Geometry is persisted, so next launch reopens in the same place.

### 9.3 Automated Settings UI test

```bash
# 1. Get button id from current preset
curl -s http://127.0.0.1:17430/preset/current | jq '.preset.groups[].buttons[].id'

# 2. Arrange windows and open Settings
curl -X POST http://127.0.0.1:17430/tools/call \
    -d '{"name":"arrange","arguments":{"open_settings":true}}'

# 3. Select the button (opens ButtonEditor)
curl -X POST http://127.0.0.1:17430/tools/call \
    -d '{"name":"settings_select_button","arguments":{"id":"btn-slack"}}'

# 4. Set the action value
curl -X POST http://127.0.0.1:17430/tools/call \
    -d '{"name":"settings_set_action_value","arguments":{"type":"text","value":"hello"}}'

# 5. Save
curl -X POST http://127.0.0.1:17430/tools/call \
    -d '{"name":"settings_commit","arguments":{}}'

# 6. Verify persisted value
curl -s http://127.0.0.1:17430/preset/current | jq '.preset.groups[].buttons[] | select(.id=="btn-slack")'

# 7. Check for errors
curl -s 'http://127.0.0.1:17430/log/tail?since=10s&level=warn' | jq
```

### 9.4 Autonomous test loop

```bash
# Run an action
curl -X POST http://127.0.0.1:17430/tools/call \
    -d '{"name":"run_action","arguments":{"type":"text","content":"test"}}'

# Immediately inspect warnings
RESULT=$(curl -s 'http://127.0.0.1:17430/log/tail?since=10s&level=warn' | jq '.events | length')
if [ "$RESULT" -gt 0 ]; then
    curl -s 'http://127.0.0.1:17430/log/tail?since=10s&level=warn' | jq
fi
```

---

## 10. Security & constraints

- Server binds `127.0.0.1` only; other hosts cannot reach it.
- No auth — any local process can reach it.
- Destructive shell commands via `run_action { launch: "shell:..." }` should be
  confirmed with the user first.
- For `run_action { terminal }`, `execute: false` types the command but does
  not press Enter, allowing human confirmation.
- When pasting text, **the clipboard is always restored** (including on
  failure, thanks to a `defer`-guarded path).

---

## 11. Protocol compatibility matrix

| AI client / ecosystem | Recommended endpoint | Dialect |
|---|---|---|
| Claude Code / Claude Desktop | `POST /mcp` | MCP JSON-RPC 2.0 |
| Google ADK / A2A client | `GET /.well-known/agent.json` + `POST /tools/call` | A2A Agent Card + REST |
| OpenAI Assistants / Responses API | inject `GET /tools?format=openai` | OpenAI function calling |
| Anthropic Messages API | inject `GET /tools?format=anthropic` | Anthropic tool use |
| curl / LangChain / custom | generate from `GET /openapi.json` | ACP / REST |

---

## 12. Versioning

Current version: `0.1`. Breaking changes bump the `version` in `/manifest`.
AI clients should read the version on connect and adjust behavior if an
incompatible change has landed.

This document (`AI_PROTOCOL.md`) always tracks the latest implementation.
The `/manifest` response is **auto-generated from the implementation**, so
that is the source of truth:

```bash
curl -s http://127.0.0.1:17430/manifest
```

---

## 13. See also — related protocols

- **MCP (Model Context Protocol)** — Anthropic: <https://modelcontextprotocol.io/>
- **A2A (Agent-to-Agent)** — Google: <https://a2aproject.github.io/A2A/>
- **OpenAI function calling**: <https://platform.openai.com/docs/guides/function-calling>
- **Anthropic tool use**: <https://docs.anthropic.com/en/docs/tool-use>
- **JSON-RPC 2.0**: <https://www.jsonrpc.org/specification>
- **OpenAPI 3.1**: <https://spec.openapis.org/oas/v3.1.0>
