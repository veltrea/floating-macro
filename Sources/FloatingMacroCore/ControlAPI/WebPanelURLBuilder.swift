import Foundation

/// Pure function to assemble the connection URL for Web Panel Phase 5.
///
/// The purpose is two-fold:
/// Create a URL to embed in the QR code
/// Settings / Device Send Display as "copyable text" on the screen
///
/// Creating a QR code for just the URL can be done in one line, but selecting a host name (LAN IP/.local/) requires more consideration.
/// (127.0.0.1) and port and token combined into one place, fixed boundary conditions for testing
/// I will convert this into a function.
public enum WebPanelURLBuilder {

    /// Given the provided host, port, and token, construct an HTTP URL in the format `http://host:port/webpanel?token=...`.
    /// Create a URL string of the specified format.
    /// - Parameters:
    /// host: Connection target host. LAN IP (192.168.x.x) / mDNS (floatingmacro.local) / 127.0.0.1 of any kind.
    /// Binded port.
    /// Ephemeral LAN token (hex). Assumed to be non-empty.
    /// - preset: When issuing a QR code panel-wise, the target preset name. If `nil`, then
    /// The Web Panel displays the active preset. Floating in Phase 5.
    /// Passed from the QR button in the upper right corner of the window.
    public static func make(host: String, port: Int, token: String, preset: String? = nil) -> String {
        // Enclose in [] if host contains a colon (IPv6 literal).
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let q = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        var url = "http://\(h):\(port)/webpanel?token=\(q)"
        if let preset = preset, !preset.isEmpty {
            let p = preset.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? preset
            url += "&preset=\(p)"
        }
        return url
    }

    /// Select the most plausible host to use when launching LAN. Priority:
    /// 1. mDNS's `*.local` (if Bonjour is advertising)
    /// LAN IPv4 passed
    /// If nothing is there, 127.0.0.1 (does not move but does not crash)
    public static func preferredHost(localName: String? = nil,
                                     lanIPv4: String? = nil) -> String {
        if let name = localName, !name.isEmpty {
            return name.hasSuffix(".local") ? name : "\(name).local"
        }
        if let ip = lanIPv4, !ip.isEmpty { return ip }
        return "127.0.0.1"
    }
}
