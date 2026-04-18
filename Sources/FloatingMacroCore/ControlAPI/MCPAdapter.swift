import Foundation

/// Minimal MCP (Model Context Protocol) adapter over HTTP.
///
/// MCP is Anthropic's standardized agent-tool protocol. The canonical
/// transports are stdio and SSE, but the latest spec adds an HTTP transport
/// that sends JSON-RPC 2.0 envelopes over plain POST. That's the variant we
/// implement here: a **single `POST /mcp` endpoint** that accepts JSON-RPC
/// requests and dispatches them to the same tool catalog used by the REST
/// surface. This lets Claude Desktop / Claude Code register this server
/// directly without running a separate process.
///
/// Supported methods:
///   - `initialize`     : hand back server identity + capabilities
///   - `tools/list`     : return the ToolCatalog in MCP format
///   - `tools/call`     : dispatch a tool by name
///   - `ping`           : liveness probe (JSON-RPC flavor)
///
/// All other method names return a JSON-RPC error `-32601 Method not found`.
public enum MCPAdapter {

    /// Protocol version we advertise. Kept constant; MCP negotiates this.
    public static let protocolVersion = "2024-11-05"

    public struct Request {
        public let id: Any?
        public let method: String
        public let params: [String: Any]
    }

    public struct Response {
        public let id: Any?
        public let result: [String: Any]?
        public let error: JSONRPCError?

        public func serialize() -> [String: Any] {
            var obj: [String: Any] = ["jsonrpc": "2.0"]
            if let id = id { obj["id"] = id } else { obj["id"] = NSNull() }
            if let result = result { obj["result"] = result }
            if let error = error {
                var e: [String: Any] = [
                    "code":    error.code,
                    "message": error.message,
                ]
                if let data = error.data { e["data"] = data }
                obj["error"] = e
            }
            return obj
        }
    }

    public struct JSONRPCError: Error {
        public let code: Int
        public let message: String
        public let data: Any?

        public init(code: Int, message: String, data: Any? = nil) {
            self.code = code
            self.message = message
            self.data = data
        }

        public static let parseError     = JSONRPCError(code: -32700, message: "Parse error")
        public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
        public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
        public static let invalidParams  = JSONRPCError(code: -32602, message: "Invalid params")
        public static let internalError  = JSONRPCError(code: -32603, message: "Internal error")
    }

    // MARK: - Request parsing

    public enum ParseOutcome {
        case success(Request)
        case failure(Response)
    }

    /// Parse a raw JSON-RPC body. Returns the request on success, or an error
    /// response to return as-is when the envelope itself is malformed.
    public static func parseRequest(_ data: Data) -> ParseOutcome {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(Response(id: nil, result: nil, error: .parseError))
        }
        guard (obj["jsonrpc"] as? String) == "2.0" else {
            return .failure(Response(id: obj["id"], result: nil, error: .invalidRequest))
        }
        guard let method = obj["method"] as? String else {
            return .failure(Response(id: obj["id"], result: nil, error: .invalidRequest))
        }
        let params = (obj["params"] as? [String: Any]) ?? [:]
        return .success(Request(id: obj["id"], method: method, params: params))
    }

    // MARK: - Dispatch

    /// Handle a parsed request by name. The `callTool` closure is the hook
    /// that bridges into the existing REST handler layer — it receives a
    /// tool name + arguments and returns a JSON-serializable result.
    public static func handle(
        _ request: Request,
        callTool: (_ name: String, _ arguments: [String: Any]) -> Result<Any, JSONRPCError>
    ) -> Response {
        switch request.method {
        case "initialize":
            return initialize(request: request)

        case "ping":
            return Response(id: request.id, result: [:], error: nil)

        case "tools/list":
            let tools = ToolCatalog.tools.map { t -> [String: Any] in
                [
                    "name":        t.name,
                    "description": t.description,
                    "inputSchema": t.inputSchema,
                ]
            }
            return Response(id: request.id, result: ["tools": tools], error: nil)

        case "tools/call":
            guard let name = request.params["name"] as? String else {
                return Response(id: request.id, result: nil, error: .invalidParams)
            }
            let args = (request.params["arguments"] as? [String: Any]) ?? [:]
            let res = callTool(name, args)
            switch res {
            case .success(let value):
                // MCP wraps tool results in content blocks.
                let text: String
                if let obj = value as? [String: Any],
                   let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                   let str  = String(data: data, encoding: .utf8) {
                    text = str
                } else {
                    text = "\(value)"
                }
                let content: [[String: Any]] = [
                    ["type": "text", "text": text]
                ]
                return Response(id: request.id,
                                result: ["content": content, "isError": false],
                                error: nil)
            case .failure(let error):
                return Response(id: request.id, result: nil, error: error)
            }

        default:
            return Response(id: request.id, result: nil, error: .methodNotFound)
        }
    }

    // MARK: - initialize

    private static func initialize(request: Request) -> Response {
        // Client-offered protocolVersion is in params; we echo our own.
        let result: [String: Any] = [
            "protocolVersion": protocolVersion,
            "serverInfo": [
                "name":    SystemPrompt.product,
                "version": SystemPrompt.version,
            ] as [String: Any],
            "capabilities": [
                // Minimal capability set: we expose tools. No prompts/resources yet.
                "tools": [:] as [String: Any],
            ] as [String: Any],
            // Custom extension so MCP-aware clients can still find our
            // manifest / REST endpoints in one probe.
            "instructions": SystemPrompt.greeting,
            "x-extensions": [
                "rest-manifest": "/manifest",
                "openapi":       "/openapi.json",
                "agent-card":    "/.well-known/agent.json",
            ] as [String: Any],
        ]
        return Response(id: request.id, result: result, error: nil)
    }
}
