import Foundation
import Security

/// Control API トークンの永続化。
///
/// 保存先は **ファイル**（`~/Library/Application Support/FloatingMacro/control_api_token`,
/// mode 0600）が一次ソース。Keychain は `security find-generic-password ...` CLI
/// 経由でトークン取得する documented API を維持するためのミラーで、初回作成時のみ
/// 書き込みを試みる（best-effort）。
///
/// なぜファイル一次か:
///   ad-hoc 署名のリビルド/リリース毎にバイナリハッシュが変わると、Keychain ACL は
///   「別アプリ」と判定して読み出し時にパスワード入力ダイアログを毎回出す。これは
///   開発体験/更新体験を著しく悪化させる。Control API のトークンは loopback でしか
///   通用せず、同一ユーザーで動く他プロセスからは ~/Library/Application Support/
///   が読めるので、Keychain ACL で守る付加価値はほぼ無い (mode 0600 ファイルと
///   同等)。よってファイルを authoritative にする。
public enum TokenStore {

    private static let service = "FloatingMacro"
    private static let account = "ControlAPIToken"

    /// ファイル保存先。ConfigLoader.defaultBaseURL に依存。
    private static var fileURL: URL {
        ConfigLoader.defaultBaseURL.appendingPathComponent("control_api_token")
    }

    /// トークンを返す。なければ生成して保存する。
    /// - Returns: トークン文字列（32バイトのランダム hex）
    /// - Throws: 保存に失敗した場合
    public static func loadOrCreate() throws -> String {
        // 1) ファイル一次ソース。リビルド後もこちらは prompt を出さない。
        if let token = try loadFromFile() { return token }

        // 2) Migration: 旧バージョンで Keychain にだけ保存していたユーザー向け。
        //    この経路は新バイナリの初回起動 1 回だけ Keychain prompt を踏むが、
        //    以降はファイルに移してくるので二度と踏まない。
        if let token = try? loadFromKeychain() {
            try writeToFile(token)
            return token
        }

        // 3) どちらにも無ければ新規生成。ファイルが authoritative。
        let token = generate()
        try writeToFile(token)
        // `security` CLI 互換のため Keychain にも best-effort で書く。
        // 失敗 (prompt 拒否等) してもファイル側が真実なので無視。
        try? saveToKeychain(token)
        return token
    }

    /// トークンを削除する（リセット用）。ファイルと Keychain の両方を消す。
    public static func delete() throws {
        // ファイル側
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        // Keychain 側
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainError(status)
        }
    }

    // MARK: - File backend

    private static func loadFromFile() throws -> String? {
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw TokenStoreError.invalidData
        }
        return token
    }

    private static func writeToFile(_ token: String) throws {
        // 親ディレクトリは ConfigLoader が掃除してくれることが多いが念のため。
        try FileManager.default.createDirectory(
            at: ConfigLoader.defaultBaseURL,
            withIntermediateDirectories: true
        )
        guard let data = token.data(using: .utf8) else {
            throw TokenStoreError.invalidData
        }
        // mode 0600 で書く。loopback Control API トークンなので、
        // 同一ユーザー以外は到達できない時点で十分強い保護。
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    // MARK: - Keychain backend (legacy / CLI 互換)

    private static func loadFromKeychain() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
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

    private static func saveToKeychain(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw TokenStoreError.invalidData
        }
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock,
        ]
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
    internal static func generate() -> String {
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
