import Foundation

/// Agent Communication Protocol (ACP) compliance layer.
///
/// Implements the **stateless / sync-only** subset of
/// https://agentcommunicationprotocol.dev — the minimum that lets external
/// ACP clients discover and invoke FloatingMacro as a single agent.
///
/// What is implemented:
///   - GET  /agents              → list with one entry: "floatingmacro"
///   - GET  /agents/floatingmacro → AgentManifest
///   - POST /runs                → create a run, mode="sync" only
///
/// What is NOT implemented (returns 501):
///   - mode="async" / mode="stream"
///   - GET  /runs/{id}, /runs/{id}/events, resume, cancel
///   - sessions
///
/// Rationale: FloatingMacro is a configuration + action dispatch agent. Its
/// operations are short, synchronous, and stateless. The async / stream / run
/// lifecycle parts of ACP are explicitly opt-in per the spec; we declare in
/// the manifest that this agent only supports sync, which is a valid posture.
public enum ACPManifest {

    public static let agentName = "floatingmacro"

    /// Body for `GET /agents`.
    public static func agentsList() -> [String: Any] {
        [
            "agents": [agentSummary()],
        ]
    }

    /// Body for `GET /agents/floatingmacro` — full manifest.
    public static func agentManifest() -> [String: Any] {
        [
            "name": agentName,
            "description":
                "FloatingMacro — a macOS floating macro launcher. Operate the panel, " +
                "manage groups / buttons / presets, and trigger key / text / launch / " +
                "terminal / composite-macro actions. Each tool call is a sync run.",
            "metadata": [
                "documentation": "http://127.0.0.1:17430/manifest",
                "tool_catalog":  "http://127.0.0.1:17430/tools",
                "tool_invocation_format":
                    "Encode the tool call as a single Message part with " +
                    "content_type=application/json and content " +
                    "{\"tool\":\"<name>\",\"arguments\":{...}}",
            ],
            "input_content_types":  ["application/json"],
            "output_content_types": ["application/json"],
            "capabilities": [
                "supports_sync":      true,
                "supports_async":     false,
                "supports_streaming": false,
                "supports_sessions":  false,
                "supports_resume":    false,
                "supports_cancel":    false,
            ],
            // Non-spec extension: enumerate the underlying tool catalog so
            // ACP clients can discover the operation surface in one shot
            // without having to fetch /manifest separately.
            "skills": ToolCatalog.tools.map { t in
                [
                    "name":         t.name,
                    "description":  t.description,
                    "input_schema": t.inputSchema,
                ]
            },
        ]
    }

    private static func agentSummary() -> [String: Any] {
        [
            "name": agentName,
            "description": "FloatingMacro control agent (sync, stateless).",
        ]
    }

    // MARK: - Run input/output

    /// Parsed view of a `POST /runs` request body.
    public struct RunRequest {
        public let agentName: String
        public let mode: String           // "sync" | "async" | "stream" (spec default = sync)
        public let sessionId: String?
        public let toolName: String
        public let arguments: [String: Any]
    }

    /// Parse and validate a Run-create request body.
    ///
    /// Errors are returned as a `(status, message)` tuple rather than thrown,
    /// because each maps to a specific HTTP status (400 / 404 / 501).
    public enum RunParseError: Error {
        case badRequest(String)
        case agentNotFound(String)
        case unsupportedMode(String)
    }

    public static func parseRunRequest(_ body: Data) -> Result<RunRequest, RunParseError> {
        guard !body.isEmpty,
              let dict = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .failure(.badRequest("body must be JSON object"))
        }

        let agent = (dict["agent_name"] as? String) ?? agentName
        guard agent == agentName else {
            return .failure(.agentNotFound(agent))
        }

        let mode = (dict["mode"] as? String) ?? "sync"
        guard mode == "sync" else {
            return .failure(.unsupportedMode(mode))
        }

        guard let input = dict["input"] as? [Any] else {
            return .failure(.badRequest("input must be an array of Message"))
        }
        guard let firstPart = firstJSONPart(in: input) else {
            return .failure(.badRequest(
                "input must contain at least one Message with a part of " +
                "content_type=application/json"))
        }
        guard let toolName = firstPart["tool"] as? String else {
            return .failure(.badRequest(
                "Message part JSON must contain a string field 'tool'"))
        }
        let args = (firstPart["arguments"] as? [String: Any]) ?? [:]

        return .success(RunRequest(
            agentName: agent,
            mode: mode,
            sessionId: dict["session_id"] as? String,
            toolName: toolName,
            arguments: args
        ))
    }

    /// Walk the input messages and return the parsed JSON object from the
    /// first part whose content_type indicates JSON.
    private static func firstJSONPart(in messages: [Any]) -> [String: Any]? {
        for m in messages {
            guard let msg = m as? [String: Any],
                  let parts = msg["parts"] as? [Any] else { continue }
            for p in parts {
                guard let part = p as? [String: Any] else { continue }
                let ct = (part["content_type"] as? String)?.lowercased() ?? "application/json"
                guard ct.contains("json") else { continue }
                if let obj = part["content"] as? [String: Any] {
                    return obj
                }
                if let s = part["content"] as? String,
                   let data = s.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    return obj
                }
            }
        }
        return nil
    }

    // MARK: - Run response builders

    /// Build a successful sync-run response envelope.
    public static func runSuccess(runId: String,
                                  toolResult: Any,
                                  sessionId: String?,
                                  createdAt: Date,
                                  finishedAt: Date) -> [String: Any] {
        let resultString = jsonString(toolResult)
        return [
            "run_id":     runId,
            "agent_name": agentName,
            "session_id": sessionId as Any? ?? NSNull(),
            "status":     "completed",
            "output": [[
                "role": "agent",
                "parts": [[
                    "content_type": "application/json",
                    "content":      resultString,
                ]],
            ]],
            "error":       NSNull(),
            "created_at":  iso8601(createdAt),
            "finished_at": iso8601(finishedAt),
        ]
    }

    /// Build a failed sync-run response envelope (HTTP 200 with status=failed,
    /// per ACP semantics — the request was accepted, the work failed).
    public static func runFailed(runId: String,
                                 status: Int,
                                 message: String,
                                 sessionId: String?,
                                 createdAt: Date,
                                 finishedAt: Date) -> [String: Any] {
        [
            "run_id":     runId,
            "agent_name": agentName,
            "session_id": sessionId as Any? ?? NSNull(),
            "status":     "failed",
            "output":     [],
            "error": [
                "code":    status,
                "message": message,
            ],
            "created_at":  iso8601(createdAt),
            "finished_at": iso8601(finishedAt),
        ]
    }

    // MARK: - Helpers

    public static func newRunId() -> String {
        "run_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    private static func jsonString(_ obj: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        // Wrap scalars / strings in a JSON object for consistency.
        if let s = obj as? String { return "{\"value\":\(jsonEscape(s))}" }
        return "{}"
    }

    private static func jsonEscape(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: []))
            ?? Data("[\"\"]".utf8)
        let str = String(data: data, encoding: .utf8) ?? "[\"\"]"
        // Strip the surrounding "[" / "]".
        return String(str.dropFirst().dropLast())
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso8601(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}
