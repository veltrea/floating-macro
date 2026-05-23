import Foundation

/// Phase 5 (P5-11): Broadcasting `_floatingmacro._tcp.` via mDNS/Bonjour.
///
/// Purpose: LAN-based smartphone Safari accessing `floatingmacro.local:17430/webpanel?...`
/// Accessing it so that you can. Bonjour reporting allows the local hostname of Mac.
/// (Example: `MacBook-Pro.local`) can be resolved by the mDNS responder on the same LAN segment,
/// Can be done without typing the IP address directly.
///
/// Implementation is a thin wrapper using `NetService.publish` without `.includesPeerToPeer`.
/// Provide launch/stop/status retrieval.
///
/// **Threading:** The NetService depends on the main thread's run loop.
/// Design but without using `publish(options: [.listenForConnections])`.
/// Only call `publish()`, then run on a dedicated DispatchQueue.
/// Schedule moving it around is fine. That said, in the scope of Phase 5, initialization
/// Since the frequency is low, it's most straightforward to run it in main. Call from the caller side in main.
/// Please start.
public final class BonjourAdvertiser: NSObject, NetServiceDelegate {

    /// service type to broadcast. The trailing dot in `_floatingmacro._tcp.`
    /// The NetService internally assigned way to pass is "_floatingmacro._tcp.".
    /// Do not follow the Apple-recommended _appname._tcp. format since it is not a standard service.
    public static let serviceType = "_floatingmacro._tcp."

    /// Default name for broadcast. NetService actually uses host names, but...
    /// The user recognizes easily that they are publishing under this host name.
    /// Explicitly passing names is allowed.
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

    /// State change callback. Called in main for each state change (for UI update).
    public var onStateChange: ((State) -> Void)?

    /// Start the announcement. If already in an announcement, do nothing.
    /// - Parameters:
    /// port: Port to announce on (= ControlServer.boundPort). 0 is not allowed.
    /// name: Publicize. If there is a collision on the same LAN segment, NetService will automatically
    /// Append "(2)" and similar to the end for retries.
    public func start(port: Int, name: String = BonjourAdvertiser.defaultName) {
        guard service == nil else { return }
        guard port > 0, port <= 65535 else { return }
        let svc = NetService(domain: "local.",
                             type: Self.serviceType,
                             name: name,
                             port: Int32(port))
        svc.delegate = self
        // The RunLoop uses the main loop. NetService is a legacy API based on RunLoop.
        // Running the RunLoop in the background requires CFRunLoopRun, which is cumbersome.
        // Therefore, schedule in a common mode for the main RunLoop.
        svc.schedule(in: .main, forMode: .common)
        service = svc
        updateState(.publishing)
        svc.publish()
    }

    /// Stop broadcasting.
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
        // The UI side callback must always be called in the main thread.
        if Thread.isMainThread {
            onStateChange?(new)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(new)
            }
        }
    }
}
