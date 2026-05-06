import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Phase 5: LAN 公開時に「どの IPv4 アドレスを QR / URL に載せるか」を決める。
///
/// 物理 LAN (en0/Ethernet) と Wi-Fi (en1) と仮想 (utun*, awdl0, vmnet*) など
/// 多数のインターフェースがあるが、Bonjour で来るスマホが期待するのは普段の
/// LAN セグメント。ループバックと AppleTalk over WiFi (awdl0) と utun* と
/// IPv6 リンクローカルは除外する。
public enum LANInterfaceFinder {

    /// 候補の IPv4 アドレスを優先順位順に返す。最初の要素が「もっとも妥当」。
    public static func ipv4Addresses() -> [String] {
        var ipv4: [(name: String, addr: String)] = []
        #if canImport(Darwin)
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            // Up + Running + 非 Loopback。
            let up      = (flags & IFF_UP) != 0
            let running = (flags & IFF_RUNNING) != 0
            let loop    = (flags & IFF_LOOPBACK) != 0
            if let sa = cur.pointee.ifa_addr,
               sa.pointee.sa_family == sa_family_t(AF_INET),
               up, running, !loop,
               let cname = cur.pointee.ifa_name {
                let name = String(cString: cname)
                // 仮想 / AWDL / VPN tun は除外。
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

    /// LAN URL に最適な 1 つを返す。なければ nil。
    public static func bestIPv4Address() -> String? {
        return ipv4Addresses().first
    }

    /// 除外すべきインターフェース名 (プレフィクス一致)。
    static func shouldExclude(_ name: String) -> Bool {
        let excludePrefixes = [
            "lo",     // loopback
            "awdl",   // Apple Wireless Direct Link
            "llw",    // low-latency WLAN
            "utun",   // VPN tunnel
            "ipsec",  // IPSec tunnel
            "ppp",    // PPP
            "bridge", // 仮想ブリッジ (内部用)
            "vmnet",  // VMware
            "vboxnet",// VirtualBox
            "tun",    // 一般 VPN
            "tap",    // 一般 VPN
        ]
        return excludePrefixes.contains { name.hasPrefix($0) }
    }

    /// 並び順のルール:
    /// - private LAN (192.168.*, 10.*, 172.16-31.*) を優先 (= 普段の家庭/オフィス LAN)
    /// - その中でも en0 → en1 → en2 ... の順 (= 物理 Ethernet → Wi-Fi)
    /// - 残りは元の順序を維持
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
