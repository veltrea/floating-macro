import Foundation

/// Phase 5: Web Panel の接続 URL を組み立てる純粋関数。
///
/// 用途は 2 つ:
/// - QR コードに埋め込む URL を作る
/// - Settings / Device Send 画面に「コピーできるテキスト」として表示する
///
/// 「QR の URL を作る」だけなら 1 行で済むが、ホスト名の選定 (LAN IP / .local /
/// 127.0.0.1) とポートとトークンを 1 箇所にまとめ、テストで境界条件を固定して
/// おきたいので関数化する。
public enum WebPanelURLBuilder {

    /// 与えられた host + port + token から `http://host:port/webpanel?token=...`
    /// 形式の URL 文字列を作る。
    /// - Parameters:
    ///   - host: 接続先ホスト。LAN IP (`192.168.x.x`) / mDNS (`floatingmacro.local`) / 127.0.0.1 のどれでも。
    ///   - port: バインド済みポート。
    ///   - token: ephemeral LAN token (hex)。空でない前提。
    ///   - preset: パネル単位で QR を発行するときの対象 preset 名。`nil` のときは
    ///             Web Panel が active preset を表示する。Phase 5 でフローティング
    ///             ウィンドウ右上の QR ボタンから渡される。
    public static func make(host: String, port: Int, token: String, preset: String? = nil) -> String {
        // host にコロンが含まれている場合 (IPv6 リテラル) は [] で括る。
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let q = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        var url = "http://\(h):\(port)/webpanel?token=\(q)"
        if let preset = preset, !preset.isEmpty {
            let p = preset.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? preset
            url += "&preset=\(p)"
        }
        return url
    }

    /// LAN 公開時に使う「最も妥当そうなホスト」を選ぶ。優先順位:
    /// 1. mDNS の `*.local` (Bonjour 広報している場合)
    /// 2. 渡された LAN IPv4
    /// 3. 何もなければ 127.0.0.1 (動かないが落ちない)
    public static func preferredHost(localName: String? = nil,
                                     lanIPv4: String? = nil) -> String {
        if let name = localName, !name.isEmpty {
            return name.hasSuffix(".local") ? name : "\(name).local"
        }
        if let ip = lanIPv4, !ip.isEmpty { return ip }
        return "127.0.0.1"
    }
}
