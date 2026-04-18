import Foundation
import Security

/// Keychain を使ったトークンの永続化。
/// 初回 `loadOrCreate()` 時にトークンが存在しなければ自動生成して保存する。
public enum TokenStore {

    private static let service = "FloatingMacro"
    private static let account = "ControlAPIToken"

    /// トークンを返す。Keychain にない場合は生成して保存する。
    /// - Returns: トークン文字列（32バイトのランダム hex）
    /// - Throws: Keychain 操作の失敗
    public static func loadOrCreate() throws -> String {
        if let existing = try load() { return existing }
        let token = generate()
        try save(token)
        return token
    }

    /// Keychain のトークンを削除する（リセット用）。
    public static func delete() throws {
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

    // MARK: - Private

    private static func load() throws -> String? {
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

    private static func save(_ token: String) throws {
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
