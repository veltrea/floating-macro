import Foundation
import Security

/// Phase 5: LAN 公開モード用の **再起動失効** トークン。
///
/// Bearer トークン (`TokenStore`) はファイル永続化されており、AI / CLI が
/// 同一マシン内 (loopback) から使う想定で設計されている。LAN に公開した
/// 場合、永続トークンが万が一漏れても被害を最小化するため、QR で配る用
/// の二次トークンを「メモリ常駐 / 再起動失効」で扱う。
///
/// ## 設計上の判断
/// - **永続化しない**: アプリ終了でトークンが消える方が、漏洩面を 1 セッ
///   ションに閉じ込められる。
/// - **手動再発行可能**: メニューバーから「再発行」を押せば、過去の QR
///   は即無効化される。
/// - **スレッドセーフ**: メニューバー UI と Control API ハンドラの両方
///   から触られる。`NSLock` で同期する (actor は HTTP ハンドラ側がブロッ
///   クすると詰まるので採用しない)。
public final class EphemeralLANTokenStore: @unchecked Sendable {

    public static let shared = EphemeralLANTokenStore()

    private let lock = NSLock()
    private var token: String?
    private var rotatedAt: Date?

    public init() {}

    /// 現在のトークンを返す。未発行なら nil。
    public var current: String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    /// 最後に発行された時刻を返す。未発行なら nil。
    public var lastRotatedAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return rotatedAt
    }

    /// トークンが未発行なら新規発行して返す。発行済みならそのまま返す。
    /// LAN 公開モードを ON にしたタイミングで呼ぶ想定。
    @discardableResult
    public func ensureIssued() -> String {
        lock.lock(); defer { lock.unlock() }
        if let existing = token { return existing }
        let new = Self.generate()
        token = new
        rotatedAt = Date()
        return new
    }

    /// 既存トークンを破棄して新しいトークンを発行する。手動再発行用。
    @discardableResult
    public func rotate() -> String {
        lock.lock(); defer { lock.unlock() }
        let new = Self.generate()
        token = new
        rotatedAt = Date()
        return new
    }

    /// トークンを破棄する。LAN 公開モード OFF にするタイミングで呼ぶ。
    public func revoke() {
        lock.lock(); defer { lock.unlock() }
        token = nil
        rotatedAt = nil
    }

    /// 与えられた候補が現在のトークンと一致するか定数時間比較で判定する。
    /// LAN に開いている以上、タイミング攻撃の最低限の対策はしておく。
    public func matches(_ candidate: String) -> Bool {
        lock.lock()
        let current = token
        lock.unlock()
        guard let expected = current else { return false }
        return Self.constantTimeEquals(expected, candidate)
    }

    // MARK: - Internal

    /// 16 バイトのランダム hex 文字列。永続トークン (32 バイト) より短く
    /// するのは「QR 経由で打ち込まれる可能性」を考慮した妥協 (ただし
    /// 16 バイト = 128bit あれば総当たりは現実的に不可能)。
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 早期リターンで分岐タイミングが漏れないように長さチェックは
    /// 比較ループの中で潰す。同じ長さでない場合も最後まで走らせて
    /// から false を返す。
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
