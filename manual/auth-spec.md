# FloatingMacro Control API Authentication Specification

Last updated: 2026-05-19

---

## 1. Overview

The Control API binds to `127.0.0.1:17430` by default. Bearer token authentication protects all action-executing endpoints. Discovery endpoints are open so that AI agents can bootstrap without a chicken-and-egg problem.

### Design principles

- **File-based token storage** — `~/Library/Application Support/FloatingMacro/control_api_token` (mode 0600). No Keychain dependency.
- **All action endpoints require Bearer auth** — discovery endpoints are exempt (see section 4).
- **No external dependencies** — Security.framework (standard, for random number generation only).
- **Backward compatible** — `controlAPI.enabled = false` changes nothing; omitted `requireAuth` defaults to `true`.
- **Two-tier token model** — permanent Bearer token for loopback (AI/CLI), ephemeral LAN token for Web Panel (smartphone/tablet via QR).

### Historical note

Early versions stored the token in macOS Keychain. However, FloatingMacro is distributed without an Apple Developer certificate (ad-hoc signed). Ad-hoc signed binaries change their code hash on every rebuild, causing Keychain ACL to treat each build as a "different app" and present a password prompt on every launch. This made Keychain impractical for token storage. The current version uses a plain file (mode 0600) as the sole storage mechanism. The source code retains Keychain read/write methods only for one-time migration from older installations; they can be removed once the migration window has passed.

---

## 2. Token Storage

### `Sources/FloatingMacroCore/ControlAPI/TokenStore.swift`

The token lifecycle on `loadOrCreate()`:

1. **Read file** — `~/Library/Application Support/FloatingMacro/control_api_token`. If present, return immediately.
2. **Legacy migration** — if no file exists but an old Keychain entry remains (from pre-v0.11 installs), read it once, write it to file, and return. This path will be removed in a future version.
3. **New generation** — generate a 32-byte random hex string and write to file (mode 0600).

```swift
public enum TokenStore {
    /// Returns the token. Creates one if none exists.
    public static func loadOrCreate() throws -> String
    /// Deletes the token file (for reset).
    public static func delete() throws
    /// 32-byte random hex generator (internal visibility for testing).
    internal static func generate() -> String
}
```

### `Sources/FloatingMacroCore/ControlAPI/EphemeralLANTokenStore.swift`

A separate in-memory token for LAN-exposed Web Panel access. Key properties:

- **Not persisted** — revoked on app termination.
- **Rotatable** — menu bar "re-issue" invalidates all prior QR codes.
- **Thread-safe** — `NSLock`-synchronized (not actor, to avoid blocking HTTP handlers).
- **Constant-time comparison** — `matches(_:)` uses XOR-based comparison to mitigate timing attacks.
- **16-byte random hex** (shorter than permanent token for QR friendliness; 128-bit is still brute-force infeasible).

```swift
public final class EphemeralLANTokenStore: @unchecked Sendable {
    public static let shared: EphemeralLANTokenStore
    public var current: String?           // nil if not issued
    public func ensureIssued() -> String  // issue if not yet
    public func rotate() -> String        // invalidate old, issue new
    public func revoke()                  // clear (LAN mode OFF)
    public func matches(_ candidate: String) -> Bool
}
```

---

## 3. Configuration

### `ControlAPIConfig` in `Sources/FloatingMacroCore/Config/Preset.swift`

```swift
public struct ControlAPIConfig: Codable, Equatable {
    public var enabled: Bool              // default: false
    public var port: Int                  // default: 17430
    public var agentMode: AgentMode       // default: .normal
    public var requireAuth: Bool          // default: true
    public var testMode: Bool             // default: false
    public var lanExposureEnabled: Bool   // default: false
}
```

| Field | Description |
|---|---|
| `enabled` | Master switch for the HTTP listener |
| `port` | Preferred port. Falls back to port+1 … port+9 if taken |
| `agentMode` | System prompt flavor returned by `/manifest` (`normal` / `test` / `claudeCode`) |
| `requireAuth` | Whether Bearer token is required |
| `testMode` | Skips auth entirely (CI/smoke tests) |
| `lanExposureEnabled` | Binds to 0.0.0.0 instead of 127.0.0.1; enables Web Panel and ephemeral LAN token |

All fields use `decodeIfPresent` with sensible defaults for backward compatibility.

### config.json example

```json
{
  "version": 1,
  "controlAPI": {
    "enabled": true,
    "port": 17430,
    "agentMode": "normal",
    "requireAuth": true,
    "testMode": false,
    "lanExposureEnabled": false
  }
}
```

---

## 4. Auth Middleware

### `wrapWithAuth()` in `Sources/FloatingMacroApp/ControlAPI/ControlHandlers.swift`

Token resolution at startup (`App.swift`):

```swift
let token: String? = (apiCfg.requireAuth && !apiCfg.testMode)
    ? (try? TokenStore.loadOrCreate())
    : nil
// token == nil → all requests pass through without auth check

let server = ControlServer(
    preferredPort: UInt16(clamping: apiCfg.port),
    maxPortProbes: 10,
    bindScope: apiCfg.lanExposureEnabled ? .anyInterface : .loopback,
    handler: wrapWithAuth(token: token, handler: handlers.makeHandler())
)
```

On token file read failure, the app logs an error and starts without auth (graceful degradation).

### Public (auth-exempt) endpoints

| Path | Reason |
|---|---|
| `/ping` | Health check. Must work without token for monitoring/CI |
| `/health` | Same (future use) |
| `/manifest`, `/help` | AI agent bootstrap — agents read these to learn that auth is required and how to obtain a token |
| `/.well-known/agent.json` | ACP agent card discovery |
| `/openapi.json` | OpenAPI schema discovery |
| `/agents`, `/agents/floatingmacro` | ACP agent listing and manifest |
| `/webpanel*` | Protected by ephemeral LAN token instead (see section 5) |

### 401 response

Requests to protected endpoints without a valid `Authorization: Bearer <token>` header receive:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="FloatingMacro"
Content-Type: application/json

{"error":"invalid or missing token"}
```

---

## 5. Web Panel Authentication (LAN Mode)

When `lanExposureEnabled` is true, the server binds to `0.0.0.0` and the Web Panel becomes accessible from the local network. Web Panel routes (`/webpanel*`) bypass Bearer token auth entirely — they use the ephemeral LAN token instead.

Authentication flow:

1. App issues an ephemeral token on LAN mode activation (`EphemeralLANTokenStore.shared.ensureIssued()`).
2. Token is distributed to mobile devices via QR code.
3. `GET /webpanel?token=<ephemeral>` validates the query parameter.
4. `POST /webpanel/tools/call` also validates the ephemeral token.
5. App restart or manual rotation invalidates all previously issued tokens.

Web Panel read-only routes (`/webpanel`, `/webpanel/style.css`, `/webpanel/app.js`, `/webpanel/icon`) are served on the connection queue (not main queue) for fast concurrent image loading from mobile devices.

Management endpoints (Bearer-protected, loopback only):

- `GET /lan-token` — retrieve current ephemeral token info
- `POST /lan-token/rotate` — invalidate and re-issue

---

## 6. CLI Integration

### `fmcli token` subcommands

```
fmcli token show     Print the current token to stdout
fmcli token reset    Delete and regenerate the token
```

Implementation reads/writes via `TokenStore.loadOrCreate()` and `TokenStore.delete()`.

### Retrieving the token

```bash
# Recommended: direct file read
cat ~/Library/Application\ Support/FloatingMacro/control_api_token

# Alternative: via fmcli (requires building the CLI)
swift run fmcli token show
```

---

## 7. AI Agent / MCP Client Configuration

### Claude Code (MCP stdio via npm package)

```json
{
  "mcpServers": {
    "floatingmacro": {
      "command": "npx",
      "args": [
        "@veltrea/floatingmacro-mcp",
        "--token", "<paste token here>"
      ]
    }
  }
}
```

The npm package accepts `FLOATINGMACRO_TOKEN` environment variable or `--token` CLI argument.

### Direct HTTP (curl)

```bash
TOKEN=$(cat ~/Library/Application\ Support/FloatingMacro/control_api_token)

curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:17430/state | jq

# Auth-exempt endpoints work without token
curl -s http://127.0.0.1:17430/ping
curl -s http://127.0.0.1:17430/manifest | jq
```

---

## 8. Smoke Tests

`scripts/control_api_smoke.sh` uses `testMode: true` in config to bypass auth entirely for automated testing.

Other scripts (`settings_api_smoke.sh`, `text_inject_e2e.sh`) read the token from the file:

```bash
TOKEN_FILE="$HOME/Library/Application Support/FloatingMacro/control_api_token"
TOKEN=$(cat "$TOKEN_FILE")
```

---

## 9. Test Coverage

### TokenStore

- `loadOrCreate()` returns the same token on consecutive calls
- `delete()` + `loadOrCreate()` produces a new token
- Generated token is a 64-character hex string
- `generate()` is `internal` for direct testing

### Auth middleware (`wrapWithAuth`)

- `token: nil` passes all requests (testMode behavior)
- Public paths pass without token
- Correct Bearer token passes
- Wrong token returns 401
- Missing Authorization header returns 401

### EphemeralLANTokenStore

- `ensureIssued()` is idempotent
- `rotate()` invalidates previous token
- `revoke()` clears current token
- `matches()` uses constant-time comparison
