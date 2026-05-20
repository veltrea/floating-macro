import Foundation
import Network

/// HTTP server that exposes a tiny JSON API over a single
/// connection-per-request model.
///
/// Why not `swift-nio`: SPEC §14 + CLAUDE.md mandate no extra dependencies.
/// Network.framework gives us `NWListener` / `NWConnection` directly from
/// the OS, which is enough for a control surface.
///
/// Why no Keep-Alive: the control surface is not high-frequency and each
/// call is idempotent; closing after the response removes a whole class of
/// half-closed / leak bugs we'd otherwise need to handle.
///
/// **Bind scope**: defaults to `.loopback` so that only processes on the
/// same machine can reach the API. Phase 5 (`bindScope: .anyInterface`)
/// opens it to the LAN as well, gated by `ControlAPIConfig.lanExposureEnabled`
/// + ephemeral token + a visible menu-bar warning.
///
/// **Threading contract**: the server runs entirely on its private
/// `DispatchQueue`. Handlers MUST NOT touch AppKit directly — they should
/// hop to `MainActor` / `DispatchQueue.main` as needed. This is what lets
/// us start the server in 1–2 seconds without blocking the main thread
/// (see memory note on MCP server threading).
public final class ControlServer {

    public typealias Handler = (HTTPRequest) -> HTTPResponse

    /// Which network interfaces the listener binds to.
    public enum BindScope: Equatable {
        /// 127.0.0.1 のみ。同一マシン内のプロセスだけが到達可能 (デフォルト)。
        case loopback
        /// 全インターフェース (0.0.0.0) にバインド。LAN 内の他端末からも到達可能。
        /// Phase 5 のマルチデバイスモード用。
        case anyInterface
    }

    private let preferredPort: UInt16
    private let maxPortProbes: Int
    private let bindScope: BindScope
    private let handler: Handler
    private let category = "ControlServer"

    private var listener: NWListener?
    /// listener の accept 用キュー。connection ごとには別 queue を割り当てる
    /// (Phase 5)。
    private let listenerQueue = DispatchQueue(label: "fm.controlserver.listener",
                                              qos: .userInitiated)
    /// 各接続が独立して並列に処理されるように、connection ごとに新しい
    /// serial queue を作る。これで iPhone から並列に飛んでくる画像
    /// リクエストが本当に並列に捌かれる (= 体感の遅さの主因)。
    private let perConnectionQueueLabel = "fm.controlserver.conn"
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let connLock = NSLock()

    /// Resolved port once the listener is ready. 0 if not yet started.
    public private(set) var boundPort: UInt16 = 0
    public private(set) var isRunning = false
    /// 起動時に決まったバインドスコープ。ログ・診断用。
    public var currentBindScope: BindScope { bindScope }

    public init(preferredPort: UInt16 = 17430,
                maxPortProbes: Int = 10,
                bindScope: BindScope = .loopback,
                handler: @escaping Handler) {
        self.preferredPort = preferredPort
        self.maxPortProbes = max(1, maxPortProbes)
        self.bindScope     = bindScope
        self.handler       = handler
    }

    /// Start the server on its own queue. Returns once the listener has bound
    /// (or failed) — bounded by `timeout` seconds so callers can guarantee
    /// the fast-boot budget required by external tool integrations.
    @discardableResult
    public func start(timeout: TimeInterval = 2.0) -> Result<UInt16, Error> {
        let sem = DispatchSemaphore(value: 0)
        var outcome: Result<UInt16, Error> = .failure(ControlServerError.timeout)

        listenerQueue.async { [weak self] in
            guard let self else { sem.signal(); return }
            self.tryBindSequentially(startingAt: self.preferredPort) { result in
                outcome = result
                sem.signal()
            }
        }

        let waited = sem.wait(timeout: .now() + timeout)
        if waited == .timedOut {
            return .failure(ControlServerError.timeout)
        }
        return outcome
    }

    public func stop() {
        listenerQueue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.connLock.lock()
            let connsCopy = self?.connections ?? [:]
            self?.connections.removeAll()
            self?.connLock.unlock()
            for (_, conn) in connsCopy {
                conn.cancel()
            }
            self?.isRunning = false
        }
    }

    // MARK: - Bind loop

    private func tryBindSequentially(startingAt port: UInt16,
                                     completion: @escaping (Result<UInt16, Error>) -> Void) {
        var candidates: [UInt16] = []
        for i in 0..<maxPortProbes {
            candidates.append(port &+ UInt16(i))
        }
        tryNext(ports: candidates, completion: completion)
    }

    private func tryNext(ports: [UInt16],
                         completion: @escaping (Result<UInt16, Error>) -> Void) {
        var remaining = ports
        guard !remaining.isEmpty else {
            completion(.failure(ControlServerError.noPortAvailable))
            return
        }
        let port = remaining.removeFirst()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(ControlServerError.badPort(port)))
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // .loopback: 127.0.0.1 のみ受信。外部ホストから到達不可。
        // .anyInterface: requiredInterfaceType を指定しない = 全 IF (0.0.0.0)。
        // Phase 5 LAN 公開モードで使う。視覚警告と短期トークンと併せて防御する。
        switch bindScope {
        case .loopback:
            params.requiredInterfaceType = .loopback
        case .anyInterface:
            break
        }

        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.boundPort = port
                    self.isRunning = true
                    LoggerContext.shared.info(self.category, "Server listening", [
                        "port":  String(port),
                        "scope": self.bindScope == .loopback ? "loopback" : "any",
                    ])
                    completion(.success(port))
                case .failed(let err):
                    listener.cancel()
                    LoggerContext.shared.warn(self.category, "Bind failed, trying next port", [
                        "port":  String(port),
                        "error": String(describing: err),
                    ])
                    self.tryNext(ports: remaining, completion: completion)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch {
            tryNext(ports: remaining, completion: completion)
        }
    }

    // MARK: - Connection processing

    private func handleConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connLock.lock()
        connections[id] = connection
        connLock.unlock()

        // 接続ごとに専用 serial queue を割り当てる。これで複数接続が
        // 並列に進行できる (= iPhone からの並列画像リクエストが本当に並列に
        // さばかれる)。
        let connQueue = DispatchQueue(label: perConnectionQueueLabel,
                                      qos: .userInitiated)
        connection.start(queue: connQueue)
        readRequest(connection: connection, buffer: Data())
    }

    private func finish(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connLock.lock()
        connections.removeValue(forKey: id)
        connLock.unlock()
        connection.cancel()
    }

    private func readRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                LoggerContext.shared.warn(self.category, "receive error", ["error": String(describing: error)])
                self.finish(connection)
                return
            }

            var buf = buffer
            if let chunk = chunk { buf.append(chunk) }

            // Try to parse. If incomplete, read more.
            let parsed = HTTPParser.parse(buf)
            switch parsed {
            case .success(let (req, _)):
                let response = self.handler(req)
                self.send(response, on: connection) { [weak self] in
                    self?.finish(connection)
                }
            case .failure(.incompleteBody), .failure(.empty):
                if isComplete {
                    self.finish(connection)
                } else {
                    self.readRequest(connection: connection, buffer: buf)
                }
            case .failure(let err):
                let res = HTTPResponse.badRequest("parse error: \(err)")
                self.send(res, on: connection) { [weak self] in
                    self?.finish(connection)
                }
            }
        }
    }

    private func send(_ response: HTTPResponse,
                      on connection: NWConnection,
                      completion: @escaping () -> Void) {
        connection.send(content: response.serialize(),
                        completion: .contentProcessed { _ in completion() })
    }
}

public enum ControlServerError: Error, Equatable {
    case timeout
    case noPortAvailable
    case badPort(UInt16)
}
