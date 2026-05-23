import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Phase 5: When publicly releasing, decide which IPv4 address to include in the QR code and URL.
///
/// Physical LAN (en0/Ethernet) and Wi-Fi (en1) and virtual (utun*, awdl0, vmnet*) types
/// There are many interfaces, but the smartphone coming via Bonjour expects the usual
/// LAN segment. Loopback and AppleTalk over WiFi (awdl0) and utun*.
/// Exclude link-local IPv6.
public enum LANInterfaceFinder {

    /// Return the candidate IPv4 addresses in priority order, with the most valid address first.
    public static func ipv4Addresses() -> [String] {
        var ipv4: [(name: String, addr: String)] = []
        #if canImport(Darwin)
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            // Up and Running - Non-Loopback.
            let up      = (flags & IFF_UP) != 0
            let running = (flags & IFF_RUNNING) != 0
            let loop    = (flags & IFF_LOOPBACK) != 0
            if let sa = cur.pointee.ifa_addr,
               sa.pointee.sa_family == sa_family_t(AF_INET),
               up, running, !loop,
               let cname = cur.pointee.ifa_name {
                let name = String(cString: cname)
                // Exclude virtual/AWDL/VPN tunnels.
                if !shouldExclude(name) {
                    var addrBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                        var addr = sin.pointee.sin_addr
                        _ = inet_ntop(AF_INET, &addr, &addrBuf, socklen_t(INET_ADDRSTRLEN))
                    }
                    let s = String(cString: addrBuf)
                    if !s.isEmpty, s != "0.0.0.0" {
                        ipv4.append((name: name, addr: s))
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        #endif
        return rank(ipv4)
    }

    /// Returns the optimal one from LAN URLs, nil if none.
    public static func bestIPv4Address() -> String? {
        return ipv4Addresses().first
    }

    /// Exclude interface names (prefix match).
    static func shouldExclude(_ name: String) -> Bool {
        let excludePrefixes = [
            "lo",     // loopback
            "awdl",   // Apple Wireless Direct Link
            "llw",    // low-latency WLAN
            "utun",   // VPN tunnel
            "ipsec",  // IPSec tunnel
            "ppp",    // PPP
            "bridge", // Virtual bridge (internal use)
            "vmnet",  // VMware
            "vboxnet",// VirtualBox
            "tun",    // General VPN
            "tap",    // General VPN
        ]
        return excludePrefixes.contains { name.hasPrefix($0) }
    }

    /// Ordering rules:
    /// private LAN (192.168.*, 10.*, 172.16-31.*) priority (= usual home/offices LAN)
    /// Among them, from en0 to en1 to en2... (= physical Ethernet to Wi-Fi)
    /// The remaining ones maintain the original order
    static func rank(_ list: [(name: String, addr: String)]) -> [String] {
        let scored = list.enumerated().map { idx, item -> (Int, Int, String) in
            let priv = isPrivate(item.addr) ? 0 : 1
            let nameRank: Int
            if item.name.hasPrefix("en"),
               let n = Int(item.name.dropFirst(2)) {
                nameRank = n
            } else {
                nameRank = 100 + idx
            }
            return (priv, nameRank, item.addr)
        }
        return scored.sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 < rhs.1
        }.map { $0.2 }
    }

    static func isPrivate(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }
}
