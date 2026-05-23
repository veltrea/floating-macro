import Foundation
import Security

/// Persistence of Control API tokens.
///
/// The save location is **File** (`~/Library/Application Support/FloatingMacro/control_api_token`,
/// Mode 0600 is the primary source. Keychain uses the `security find-generic-password ...` CLI.
/// Mirror for maintaining the documented API to obtain tokens via the specified method, only on initial creation.
/// Attempt to write (best-effort).
///
/// Why file one-time?
/// Ad-hoc signature rebuild/release for each binary hash change, Keychain ACL is
/// Determines the app as a separate application and prompts for password input dialog every time it is read. This is
/// Development experience / update experience significantly deteriorates. The Control API token is only via loopback.
/// Not universal, from another process running under the same user: ~/Library/Application Support/
/// Since it can be read, there is almost no added value to protect with Keychain ACLs (similar to mode 0600 files and)
/// Equal). Therefore, make the file authoritative.
public enum TokenStore {

    private static let service = "FloatingMacro"
    private static let account = "ControlAPIToken"

    /// Save location. Depends on ConfigLoader.defaultBaseURL.
    private static var fileURL: URL {
        ConfigLoader.defaultBaseURL.appendingPathComponent("control_api_token")
    }

    /// Returns a token. If none exists, generate and save one.
    /// Returns: Token string (32-byte random hex)
    /// Throws: Save failed
    public static func loadOrCreate() throws -> String {
        // File source code. After rebuilding, this will not display the prompt.
        if let token = try loadFromFile() { return token }

        // 2) Migration: For users who previously saved in Keychain only for older versions.
        // This route only prompts the Keychain once for a new binary launch,
        // From now on, I will not step on it again in a file.
        if let token = try? loadFromKeychain() {
            try writeToFile(token)
            return token
        }

        // Create new if neither exists in either. File is authoritative.
        let token = generate()
        try writeToFile(token)
        // Write to Keychain for best-effort compatibility with `security` CLI.
        // Ignore even if the file side fails (prompt refusal, etc.).
        try? saveToKeychain(token)
        return token
    }

    /// Delete tokens (reset). Remove both file and Keychain.
    public static func delete() throws {
        // file side
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        // Keychain side
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
        // The parent directory is often cleaned up by ConfigLoader, just in case.
        try FileManager.default.createDirectory(
            at: ConfigLoader.defaultBaseURL,
            withIntermediateDirectories: true
        )
        guard let data = token.data(using: .utf8) else {
            throw TokenStoreError.invalidData
        }
        // Write in mode 0600. The loopback Control API token, so that...
        // Sufficiently strong protection when unreachable by users other than the same user.
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    // MARK: - Keychain backend (legacy / CLI compatible)

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

    /// Generate a random 32-byte hexadecimal string.
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
