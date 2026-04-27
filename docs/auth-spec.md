# FloatingMacro 制御API 認証機能 実装仕様書

最終更新: 2026-04-18

---

## 1. 概要と方針

### 目的

現在の制御APIは認証なし（localhost限定のみ）。技術デモとして動いているが、同一マシン上の任意プロセスから全操作が可能な状態。Keychainにトークンを保存し、Bearerトークン認証を追加する。

### 設計方針

- **Keychainにランダムトークンを保存** — 初回起動時に生成、以降は同じ値を使用
- **全エンドポイントにBearer認証を要求** — 一部除外あり（後述）
- **外部依存なし** — Security.framework（標準）のみ使用
- **後方互換** — `controlAPI.enabled = false` の場合は何も変わらない
- **fmcliから参照可能** — `fmcli token show` でトークンを取得できる

---

## 2. 新規ファイル

### `Sources/FloatingMacroCore/ControlAPI/TokenStore.swift`

Keychainの読み書きラッパー。`FloatingMacroCore` ターゲットに追加。

```swift
import Foundation
import Security

/// Keychain を使ったトークンの永続化。
/// 初回 `load()` 時にトークンが存在しなければ自動生成して保存する。
public enum TokenStore {

    private static let service = "FloatingMacro"
    private static let account = "ControlAPIToken"

    /// トークンを返す。Keychainにない場合は生成して保存する。
    /// - Returns: トークン文字列（32バイトのランダム hex）
    /// - Throws: Keychain操作の失敗
    public static func loadOrCreate() throws -> String {
        if let existing = try load() { return existing }
        let token = generate()
        try save(token)
        return token
    }

    /// Keychainのトークンを削除する（リセット用）。
    public static func delete() throws {
        let query: [CFString: Any] = [
            kSecClass:   kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainError(status)
        }
    }

    // MARK: - Private

    private static func load() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw TokenStoreError.invalidData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychainError(status)
        }
    }

    private static func save(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw TokenStoreError.invalidData
        }
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecValueData:        data,
            // アプリが署名されていない場合も動くよう kSecAttrAccessible を指定
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlock,
        ]
        // 既存アイテムがあれば update、なければ add
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [CFString: Any] = [kSecValueData: data]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw TokenStoreError.keychainError(status)
        }
    }

    /// 32バイトのランダム hex 文字列を生成する。
    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public enum TokenStoreError: Error, LocalizedError {
    case keychainError(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .keychainError(let s): return "Keychain error: OSStatus \(s)"
        case .invalidData:          return "Token data is invalid"
        }
    }
}
```

---

## 3. 変更ファイル

### 3-1. `Sources/FloatingMacroCore/Config/Preset.swift` — `ControlAPIConfig` に `requireAuth` 追加

```swift
// 変更前
public struct ControlAPIConfig: Codable, Equatable {
    public var enabled: Bool
    public var port: UInt16
    public var testMode: Bool
    // ...
}

// 変更後（末尾に1フィールド追加）
public struct ControlAPIConfig: Codable, Equatable {
    public var enabled: Bool
    public var port: UInt16
    public var testMode: Bool
    public var requireAuth: Bool   // ← 追加

    // init でデフォルト true
    public init(enabled: Bool = false,
                port: UInt16 = 17430,
                testMode: Bool = false,
                requireAuth: Bool = true) {   // ← 追加
        self.enabled = enabled
        self.port = port
        self.testMode = testMode
        self.requireAuth = requireAuth
    }
}
```

`Codable` の `init(from:)` でも `decodeIfPresent` でフォールバック `true` にする（後方互換）。

---

### 3-2. `Sources/FloatingMacroApp/ControlAPI/ControlHandlers.swift` — 認証ミドルウェア追加

ControlServer の `handler` クロージャは `(HTTPRequest) -> HTTPResponse` の形。
認証チェックはこのクロージャの先頭で実施する。

```swift
// ControlHandlers.swift の makeHandler() 等でラップする例

func wrapWithAuth(token: String?, handler: @escaping ControlServer.Handler) -> ControlServer.Handler {
    return { req in
        // 認証が無効（token == nil）はスルー
        guard let expectedToken = token else { return handler(req) }

        // 除外エンドポイント
        let publicPaths: Set<String> = ["/ping", "/health"]
        if publicPaths.contains(req.path) { return handler(req) }

        // Authorization: Bearer <token> を検証
        guard let authHeader = req.header("Authorization"),
              authHeader.hasPrefix("Bearer "),
              authHeader.dropFirst("Bearer ".count) == expectedToken else {
            return HTTPResponse(
                status: 401,
                reason: "Unauthorized",
                headers: [
                    ("Content-Type", "application/json"),
                    ("WWW-Authenticate", "Bearer realm=\"FloatingMacro\""),
                ],
                body: #"{"error":"invalid or missing token"}"#.data(using: .utf8)!
            )
        }

        return handler(req)
    }
}
```

**呼び出し側（ControlHandlers.swift のサーバー起動部分）:**

```swift
// requireAuth == false のとき token = nil → 認証スキップ
let token: String? = config.requireAuth ? (try? TokenStore.loadOrCreate()) : nil
let server = ControlServer(
    preferredPort: config.port,
    handler: wrapWithAuth(token: token, handler: baseHandler)
)
```

---

### 3-3. `Sources/FloatingMacroCLI/main.swift` — `fmcli token` コマンド追加

#### 追加するサブコマンド

```
fmcli token show     → Keychainのトークンを stdout に表示
fmcli token reset    → Keychainのトークンを削除して再生成
```

#### printUsage() に追記

```
fmcli token show              制御APIトークンを表示
fmcli token reset             トークンを再生成
```

#### 実装

```swift
case ["token", "show"]:
    do {
        let token = try TokenStore.loadOrCreate()
        print(token)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }

case ["token", "reset"]:
    do {
        try TokenStore.delete()
        let token = try TokenStore.loadOrCreate()
        print("New token: \(token)")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
```

---

### 3-4. `scripts/control_api_smoke.sh` — トークン付きリクエストに更新

スモークスクリプトの冒頭でトークンを取得し、全 curl に `Authorization` ヘッダーを付与する。

```bash
# スクリプト冒頭に追加
TOKEN=$(swift run fmcli token show 2>/dev/null)
if [ -z "$TOKEN" ]; then
    echo "ERROR: could not get token"
    exit 1
fi
AUTH_HEADER="Authorization: Bearer $TOKEN"

# 既存の curl コマンドを全て以下の形に変更
curl -s -H "$AUTH_HEADER" http://127.0.0.1:17430/state | jq ...

# /ping は認証なしで通ることも確認
curl -s http://127.0.0.1:17430/ping
```

---

## 4. 認証除外エンドポイント

| パス | 理由 |
|---|---|
| `/ping` | 死活監視。トークンなしで叩けないと CI で困る |
| `/health` | 同上（現在未実装だが将来用に除外） |

`/manifest` および `/mcp` は **認証必須**にする。MCPクライアント（Claude Code等）はヘッダーを設定してから接続するのが前提。

---

## 5. Claude Code / Gemini CLI 側の設定

トークンを環境変数に入れて参照させる。

```bash
# ~/.zshrc 等に追加
export FLOATINGMACRO_TOKEN=$(swift run --package-path /path/to/floating-macro fmcli token show)
```

```json
// ~/.claude.json
{
  "mcpServers": {
    "floatingmacro": {
      "url": "http://127.0.0.1:17430/mcp",
      "headers": {
        "Authorization": "Bearer ${FLOATINGMACRO_TOKEN}"
      }
    }
  }
}
```

---

## 6. テスト追加

### `Tests/FloatingMacroCoreTests/TokenStoreTests.swift`

Keychainはテスト環境で動かしにくいため、`TokenStore` の `generate()` を `internal` に昇格させてテスト可能にする。

テストケース：
1. `loadOrCreate()` を2回呼んで同じトークンが返ることを確認
2. `delete()` 後に `loadOrCreate()` で新しいトークンが生成されることを確認
3. 生成トークンが64文字のhex文字列であることを確認

### `Tests/FloatingMacroCoreTests/AuthMiddlewareTests.swift`

`wrapWithAuth` を単体テスト（`TokenStore` は不要、文字列を直接渡す）。

テストケース：
1. トークン `nil` のとき全リクエストが通ること
2. `/ping` がトークンなしで通ること
3. 正しいBearerトークンで通ること
4. 間違いトークンで 401 が返ること
5. Authorizationヘッダーなしで 401 が返ること

---

## 7. 実装順序

1. `TokenStore.swift` を新規作成 + ユニットテスト
2. `ControlAPIConfig` に `requireAuth` を追加
3. `wrapWithAuth` 関数を実装 + ユニットテスト
4. ControlHandlers.swift のサーバー起動部分を修正
5. `fmcli token show / reset` を追加
6. スモークスクリプトを更新
7. `swift test` + スモーク実行で全確認

---

## 8. 注意事項

### コード署名なしでのKeychain動作

開発ビルド（`swift run`）はコード署名なし。macOS はデフォルトでは署名なしアプリのKeychainアクセスを許可するが、初回アクセス時にダイアログが出る場合がある。

`kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock` を指定することで、ダイアログを最小限にする。

### testMode との関係

`config.testMode = true` のとき `requireAuth` の値に関わらず認証をスキップする（CI環境でトークンなしで動かせるように）。

```swift
let token: String? = (config.requireAuth && !config.testMode) ? (try? TokenStore.loadOrCreate()) : nil
```

### fmcli でのKeychain使用

`fmcli` は CLI バイナリなので、初回 `fmcli token show` 時に「このアプリケーションがKeychainにアクセスしようとしています」ダイアログが出る可能性がある。これは macOS の仕様。

---

## 9. config.json サンプル

```json
{
  "version": 1,
  "controlAPI": {
    "enabled": true,
    "port": 17430,
    "testMode": false,
    "requireAuth": true
  }
}
```

`requireAuth` を省略した場合、既存設定との互換のため `true` がデフォルト。
明示的に `false` にすれば認証なし（現状維持）で動かせる。
