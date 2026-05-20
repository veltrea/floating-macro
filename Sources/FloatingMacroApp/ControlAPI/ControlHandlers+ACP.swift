import Foundation
import FloatingMacroCore

// MARK: - Tool discovery, dispatch, Manifest, MCP, ACP

extension ControlHandlers {

    // MARK: - Tool discovery & dispatch

    @MainActor
    func handleToolsList(_ req: HTTPRequest) -> HTTPResponse {
        let dialect: ToolCatalog.Dialect
        switch (req.query["format"] ?? "mcp").lowercased() {
        case "openai":    dialect = .openai
        case "anthropic": dialect = .anthropic
        default:          dialect = .mcp
        }
        return HTTPResponse.json(ToolCatalog.render(dialect: dialect))
    }

    @MainActor
    func handleToolsCall(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must be {name: String, arguments?: object}")
        }
        guard let tool = ToolCatalog.find(name) else {
            return HTTPResponse.json(
                ["error": "unknown tool", "name": name],
                status: 404
            )
        }
        let args = (dict["arguments"] as? [String: Any]) ?? [:]
        let inner = invokeToolByDispatch(tool: tool, arguments: args, headers: req.headers)

        var envelope: [String: Any] = [
            "name": name,
            "status": inner.status,
        ]
        if let innerObj = try? JSONSerialization.jsonObject(with: inner.body) {
            envelope["result"] = innerObj
        } else if let str = String(data: inner.body, encoding: .utf8) {
            envelope["result"] = str
        }
        return HTTPResponse.json(envelope, status: inner.status < 400 ? 200 : inner.status)
    }


    // MARK: - Endpoints

    @MainActor
    func handleManifest() -> HTTPResponse {
        let agentMode = presetManager.appConfig?.controlAPI.agentMode ?? .normal
        return HTTPResponse.json(SystemPrompt.manifest(agentMode: agentMode))
    }

    @MainActor
    func handleOpenAPI() -> HTTPResponse {
        HTTPResponse.json(OpenAPIGenerator.document())
    }

    @MainActor
    func handleAgentCard() -> HTTPResponse {
        HTTPResponse.json(AgentCard.card())
    }

    /// JSON-RPC 2.0 / MCP endpoint. Bridges into the same REST handlers
    /// used by /tools/call so behavior is identical regardless of transport.
    @MainActor
    func handleMCP(_ req: HTTPRequest) -> HTTPResponse {
        switch MCPAdapter.parseRequest(req.body) {
        case .failure(let errorResponse):
            let body = try? JSONSerialization.data(withJSONObject: errorResponse.serialize())
            return HTTPResponse(
                status: 200, reason: "OK",
                headers: [("Content-Type", "application/json")],
                body: body ?? Data()
            )
        case .success(let rpcRequest):
            let response = MCPAdapter.handle(rpcRequest) { [self] toolName, arguments in
                return callToolByName(toolName, arguments: arguments)
            }
            let body = try? JSONSerialization.data(withJSONObject: response.serialize())
            return HTTPResponse(
                status: 200, reason: "OK",
                headers: [("Content-Type", "application/json")],
                body: body ?? Data()
            )
        }
    }

    /// Internal helper: run a tool by name against its real endpoint and
    /// return the parsed JSON result (or a JSON-RPC error).
    @MainActor
    func callToolByName(_ name: String,
                                arguments: [String: Any]) -> Result<Any, MCPAdapter.JSONRPCError> {
        guard let tool = ToolCatalog.find(name) else {
            return .failure(.methodNotFound)
        }
        let innerResponse = invokeToolByDispatch(tool: tool, arguments: arguments)
        guard innerResponse.status < 400 else {
            let msg = String(data: innerResponse.body, encoding: .utf8) ?? "error"
            return .failure(MCPAdapter.JSONRPCError(
                code: -32000,
                message: "Tool \(name) failed with status \(innerResponse.status)",
                data: msg
            ))
        }
        if let parsed = try? JSONSerialization.jsonObject(with: innerResponse.body) {
            return .success(parsed)
        }
        return .success(["ok": true])
    }

    // MARK: - ACP (stateless, sync-only subset)

    @MainActor
    func handleACPAgentsList() -> HTTPResponse {
        HTTPResponse.json(ACPManifest.agentsList())
    }

    @MainActor
    func handleACPAgentManifest() -> HTTPResponse {
        HTTPResponse.json(ACPManifest.agentManifest())
    }

    @MainActor
    func handleACPRunsCreate(_ req: HTTPRequest) -> HTTPResponse {
        let createdAt = Date()
        let runId = ACPManifest.newRunId()

        let runReq: ACPManifest.RunRequest
        switch ACPManifest.parseRunRequest(req.body) {
        case .success(let r):
            runReq = r
        case .failure(let err):
            switch err {
            case .badRequest(let msg):
                return HTTPResponse.badRequest(msg)
            case .agentNotFound(let name):
                return HTTPResponse.json(
                    ["error": "agent not found", "agent_name": name,
                     "detail": "this server hosts a single agent: '\(ACPManifest.agentName)'"],
                    status: 404
                )
            case .unsupportedMode(let mode):
                return HTTPResponse.json(
                    ["error": "unsupported mode", "mode": mode,
                     "detail": "this agent only supports mode='sync'"],
                    status: 501
                )
            }
        }

        guard let tool = ToolCatalog.find(runReq.toolName) else {
            return HTTPResponse.json(
                ACPManifest.runFailed(
                    runId: runId, status: 404,
                    message: "unknown tool '\(runReq.toolName)'",
                    sessionId: runReq.sessionId,
                    createdAt: createdAt, finishedAt: Date()
                ),
                status: 200
            )
        }

        let inner = invokeToolByDispatch(tool: tool, arguments: runReq.arguments, headers: req.headers)
        let finishedAt = Date()

        if inner.status >= 400 {
            let detail = String(data: inner.body, encoding: .utf8) ?? "error"
            return HTTPResponse.json(
                ACPManifest.runFailed(
                    runId: runId, status: inner.status,
                    message: detail,
                    sessionId: runReq.sessionId,
                    createdAt: createdAt, finishedAt: finishedAt
                ),
                status: 200
            )
        }

        let resultObj: Any = (try? JSONSerialization.jsonObject(with: inner.body))
            ?? ["ok": true]
        return HTTPResponse.json(
            ACPManifest.runSuccess(
                runId: runId,
                toolResult: resultObj,
                sessionId: runReq.sessionId,
                createdAt: createdAt,
                finishedAt: finishedAt
            ),
            status: 200
        )
    }


}
