import Foundation
import Security

/// Phase 5: LAN public mode token for restart invalidation.
///
/// Bearer token (`TokenStore`) is persisted to file, allowing AI / CLI access.
/// Designed for use from the same machine (loopback), intended to be exposed on LAN.
/// In case, the persistent token is leaked even if it's for distributing via QR.
/// Handle the secondary tokens as "memory-resident / restart-impairment".
///
/// Design Judgment
/// - **Not persistent**: The token disappears when the app ends, which is better for security.
/// Trapped in a shell.
/// - **Manually Reissuable**: If you press "Reissue" from the menu bar, it will reissue the past QR
/// Will be immediately disabled.
/// Thread-safe: Both menu bar UI and control API handlers
/// from being touched. Synchronize with `NSLock` (the actor is the HTTP handler side that blocks)
/// If not adopted because it causes bottlenecks).
public final class EphemeralLANTokenStore: @unchecked Sendable {

    public static let shared = EphemeralLANTokenStore()

    private let lock = NSLock()
    private var token: String?
    private var rotatedAt: Date?

    public init() {}

    /// Returns the current token, nil if not issued.
    public var current: String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    /// Returns the timestamp of the last published item. Returns nil if none have been published.
    public var lastRotatedAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return rotatedAt
    }

    /// Return a new token if not issued yet, otherwise return as is.
    /// Assuming it is called at the timing when LAN public mode is turned on.
    @discardableResult
    public func ensureIssued() -> String {
        lock.lock(); defer { lock.unlock() }
        if let existing = token { return existing }
        let new = Self.generate()
        token = new
        rotatedAt = Date()
        return new
    }

    /// Discard existing tokens and issue new ones. For manual reissue.
    @discardableResult
    public func rotate() -> String {
        lock.lock(); defer { lock.unlock() }
        let new = Self.generate()
        token = new
        rotatedAt = Date()
        return new
    }

    /// Discard the token. Call when switching to LAN public mode off.
    public func revoke() {
        lock.lock(); defer { lock.unlock() }
        token = nil
        rotatedAt = nil
    }

    /// Determines in constant time whether the given candidate matches the current token.
    /// Since it's open on LAN, take at least minimal measures against timing attacks.
    public func matches(_ candidate: String) -> Bool {
        lock.lock()
        let current = token
        lock.unlock()
        guard let expected = current else { return false }
        return Self.constantTimeEquals(expected, candidate)
    }

    // MARK: - Internal

    /// 16-byte random hexadecimal string. Shorter than persistent token (32 bytes).
    /// The compromise is to consider the possibility of being entered via QR code, but...
    /// 16 bytes = 128 bits, so brute force is realistically impossible).
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Early returns to ensure no missing branch timing checks length
    /// Purge in the comparison loop. Even if they are not of the same length, run to the end.
    /// Returns false if from is false.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        var diff: UInt8 = aBytes.count == bBytes.count ? 0 : 1
        let maxLen = max(aBytes.count, bBytes.count)
        for i in 0..<maxLen {
            let x = i < aBytes.count ? aBytes[i] : 0
            let y = i < bBytes.count ? bBytes[i] : 0
            diff |= (x ^ y)
        }
        return diff == 0
    }
}
