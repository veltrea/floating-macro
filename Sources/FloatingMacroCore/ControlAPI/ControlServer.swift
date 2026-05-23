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
        /// Only 127.0.0.1; only processes on the same machine are reachable by default.
        case loopback
        /// Bind to the full interface (0.0.0.0). Accessible from other terminals within the LAN.
        /// Multi-device mode for Phase 5.
        case anyInterface
    }

    private let preferredPort: UInt16
    private let maxPortProbes: Int
    private let bindScope: BindScope
    private let handler: Handler
    private let category = "ControlServer"

    private var listener: NWListener?
    /// Listener's accept queue. Assign a separate queue for each connection.
    /// (Phase 5)。
    private let listenerQueue = DispatchQueue(label: "fm.controlserver.listener",
                                              qos: .userInitiated)
    /// Each connection is processed in parallel as independent units.
    /// Create a serial queue to handle images coming in parallel from an iPhone.
    /// The request is really processed in parallel (= main cause of perceived slowness).
    private let perConnectionQueueLabel = "fm.controlserver.conn"
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let connLock = NSLock()

    /// Resolved port once the listener is ready. 0 if not yet started.
    public private(set) var boundPort: UInt16 = 0
    public private(set) var isRunning = false
    /// Bind scope determined at launch. For logging and diagnostics.
    public var currentBindScope: BindScope { bindScope }

    // MARK: - Health check

    private var healthTimer: DispatchSourceTimer?
    private var lastListenerState: NWListener.State = .setup
    private var healthRetryCount = 0
    private let maxHealthRetries = 3

    /// Callback called when the listener dies (used for app layer restart decision).
    public var healthFailureHandler: (() -> Void)?

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
        guard !isRunning else {
            return .failure(ControlServerError.alreadyRunning)
        }

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

    public func stop(completion: (() -> Void)? = nil) {
        listenerQueue.async { [weak self] in
            self?.healthTimer?.cancel()
            self?.healthTimer = nil
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
            self?.boundPort = 0
            self?.healthRetryCount = 0
            completion?()
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
        // .listen on 127.0.0.1 only. Accessible from external hosts not possible.
        // Any interface: unspecified required type = all IF (0.0.0.0).
        // Use in public mode of Phase 5 LAN. Defend with visual warning and short token together.
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
                self.lastListenerState = state
                switch state {
                case .ready:
                    self.boundPort = port
                    self.isRunning = true
                    self.healthRetryCount = 0
                    LoggerContext.shared.info(self.category, "Server listening", [
                        "port":  String(port),
                        "scope": self.bindScope == .loopback ? "loopback" : "any",
                    ])
                    self.startHealthTimer()
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

        // Assign a dedicated serial queue for each connection. This allows multiple connections to...
        // Concurrent progress possible (iPhone from parallel image requests are truly concurrent)
        // be deceived).
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

// MARK: - Health timer

extension ControlServer {
    func startHealthTimer() {
        healthTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: listenerQueue)
        timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.checkHealth()
        }
        timer.resume()
        healthTimer = timer
    }

    private func checkHealth() {
        guard isRunning else { return }
        switch lastListenerState {
        case .failed, .cancelled:
            LoggerContext.shared.error(category, "Health check: listener dead", [
                "state":      String(describing: lastListenerState),
                "retryCount": String(healthRetryCount),
            ])
            guard healthRetryCount < maxHealthRetries else {
                LoggerContext.shared.error(category,
                    "Health check: max retries reached, giving up until next config change")
                healthTimer?.cancel()
                healthTimer = nil
                return
            }
            healthRetryCount += 1
            healthFailureHandler?()
        case .ready:
            break
        default:
            LoggerContext.shared.warn(category, "Health check: unexpected state", [
                "state": String(describing: lastListenerState),
            ])
        }
    }
}

public enum ControlServerError: Error, Equatable {
    case timeout
    case noPortAvailable
    case badPort(UInt16)
    case alreadyRunning
}
