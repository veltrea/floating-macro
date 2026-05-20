import Foundation

/// Phase 5 (P5-11): mDNS / Bonjour で `_floatingmacro._tcp.` を広報する。
///
/// 目的: LAN 内のスマホ Safari が `floatingmacro.local:17430/webpanel?...`
/// にアクセスできるようにすること。Bonjour 広報により Mac のローカルホスト名
/// (例: `MacBook-Pro.local`) が同 LAN セグメントの mDNS responder で解決でき、
/// IP アドレスを直打ちしなくて済む。
///
/// 実装は `NetService.publish` を `.includesPeerToPeer` なしで使う薄いラッパ。
/// 起動・停止・状態取得を提供。
///
/// **スレッディング**: NetService はメインスレッドのランループに依存する API
/// 設計だが、`publish(options: [.listenForConnections])` を使わず
/// `publish()` だけ呼ぶケースなら、専用の DispatchQueue 上のランループに
/// schedule して動かしても問題ない。とはいえ Phase 5 のスコープでは初期化
/// 頻度が低いので、main で動かすのが最も素直。呼び出し側で main から
/// `start` してもらう。
public final class BonjourAdvertiser: NSObject, NetServiceDelegate {

    /// 広報する service type。`_floatingmacro._tcp.` 末尾のドットは
    /// NetService が内部的に付与するので渡し方は `_floatingmacro._tcp.`。
    /// 標準サービスではないので Apple 推奨の `_appname._tcp.` 形式に従う。
    public static let serviceType = "_floatingmacro._tcp."

    /// 広報名のデフォルト。NetService は実際にはホスト名を流用するが、
    /// ユーザーが「このホスト名で公開している」と認識しやすいよう、
    /// 名前を明示的に渡せるようにしている。
    public static let defaultName = "FloatingMacro"

    public enum State: Equatable {
        case idle
        case publishing
        case published
        case failed(Int32)  // NetService.errorCode
    }

    private(set) public var state: State = .idle
    private var service: NetService?
    private let queue = DispatchQueue(label: "fm.bonjour", qos: .utility)

    /// 状態変化のコールバック。state の変化のたびに main で呼ばれる (UI 更新用)。
    public var onStateChange: ((State) -> Void)?

    /// 広報を開始する。すでに広報中なら no-op。
    /// - Parameters:
    ///   - port: 広報するポート (= ControlServer.boundPort)。0 は不可。
    ///   - name: 広報名。同 LAN セグメントで衝突した場合 NetService が自動で
    ///           "(2)" などを末尾に付加してリトライしてくれる。
    public func start(port: Int, name: String = BonjourAdvertiser.defaultName) {
        guard service == nil else { return }
        guard port > 0, port <= 65535 else { return }
        let svc = NetService(domain: "local.",
                             type: Self.serviceType,
                             name: name,
                             port: Int32(port))
        svc.delegate = self
        // RunLoop は main を使う。NetService は RunLoop ベースの古い API。
        // バックグラウンドで RunLoop を回すと CFRunLoopRun が必要になり面倒
        // なので main RunLoop に共通モードで schedule する。
        svc.schedule(in: .main, forMode: .common)
        service = svc
        updateState(.publishing)
        svc.publish()
    }

    /// 広報を停止する。
    public func stop() {
        service?.stop()
        service?.remove(from: .main, forMode: .common)
        service = nil
        updateState(.idle)
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidPublish(_ sender: NetService) {
        updateState(.published)
    }

    public func netService(_ sender: NetService,
                           didNotPublish errorDict: [String: NSNumber]) {
        let code = errorDict[NetService.errorCode]?.int32Value ?? -1
        updateState(.failed(code))
    }

    // MARK: - Private

    private func updateState(_ new: State) {
        state = new
        // UI 側コールバックは必ず main で呼ぶ。
        if Thread.isMainThread {
            onStateChange?(new)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(new)
            }
        }
    }
}
