import Foundation

/// Auto-generates an OpenAPI 3.1 document from the ToolCatalog.
///
/// This is what makes the control API discoverable by **ACP-style** tooling,
/// Postman, curl-based explorers, and anything else that speaks OpenAPI.
/// Every time a tool is added to `ToolCatalog`, the resulting `/openapi.json`
/// updates automatically.
public enum OpenAPIGenerator {

    public static func document(baseURL: String = "http://127.0.0.1:17430") -> [String: Any] {
        var paths: [String: Any] = [:]

        // Aggregate tools by path; multiple methods on the same path share an entry.
        for tool in ToolCatalog.tools {
            let op: [String: Any] = buildOperation(tool)
            let methodKey = tool.method.lowercased()

            if var existing = paths[tool.path] as? [String: Any] {
                existing[methodKey] = op
                paths[tool.path] = existing
            } else {
                paths[tool.path] = [methodKey: op]
            }
        }

        // Add the discovery endpoints that aren't tools themselves.
        let manifestOp: [String: Any] = [
            "operationId": "manifest",
            "summary": "Self-introduction envelope for AI agents.",
            "tags": ["discovery"],
            "responses": [
                "200": [
                    "description": "Manifest JSON with systemPrompt + tools",
                    "content": ["application/json": [:]],
                ] as [String: Any]
            ],
        ]
        if paths["/manifest"] == nil {
            paths["/manifest"] = ["get": manifestOp]
        }

        return [
            "openapi": "3.1.0",
            "info": [
                "title":       "FloatingMacro Control API",
                "version":     SystemPrompt.version,
                "description": "Local HTTP control surface for FloatingMacro. Bound to 127.0.0.1 only. Designed for AI agents.",
            ] as [String: Any],
            "servers": [
                ["url": baseURL],
            ],
            "paths": paths,
        ]
    }

    // MARK: - Operation builder

    private static func buildOperation(_ tool: ToolDefinition) -> [String: Any] {
        var op: [String: Any] = [
            "operationId": tool.name,
            "summary":     tool.description,
            "tags":        [tagFor(tool)],
            "responses": [
                "200": [
                    "description": "Success",
                    "content": ["application/json": [:]],
                ] as [String: Any],
                "400": ["description": "Bad request"],
                "404": ["description": "Not found"],
                "500": ["description": "Internal error"],
            ] as [String: Any],
        ]

        // For POST / PUT / PATCH, attach the inputSchema as requestBody.
        if tool.method != "GET", let properties = tool.inputSchema["properties"] as? [String: Any],
           !properties.isEmpty {
            op["requestBody"] = [
                "required": true,
                "content": [
                    "application/json": [
                        "schema": tool.inputSchema
                    ]
                ]
            ] as [String: Any]
        }

        // For GET with parameters, emit query-string params.
        if tool.method == "GET", let properties = tool.inputSchema["properties"] as? [String: Any],
           !properties.isEmpty {
            let required = (tool.inputSchema["required"] as? [String]) ?? []
            let params: [[String: Any]] = properties.keys.sorted().map { key in
                let schema = (properties[key] as? [String: Any]) ?? [:]
                return [
                    "name":        key,
                    "in":          "query",
                    "required":    required.contains(key),
                    "schema":      schema,
                    "description": (schema["description"] as? String) ?? "",
                ] as [String: Any]
            }
            op["parameters"] = params
        }

        return op
    }

    private static func tagFor(_ tool: ToolDefinition) -> String {
        if tool.path.hasPrefix("/window") { return "window" }
        if tool.path.hasPrefix("/preset") { return "preset" }
        if tool.path.hasPrefix("/group")  { return "group" }
        if tool.path.hasPrefix("/button") { return "button" }
        if tool.path.hasPrefix("/log")    { return "observability" }
        if tool.path.hasPrefix("/icon")   { return "icon" }
        if tool.path.hasPrefix("/tools")  { return "discovery" }
        if tool.path == "/action"         { return "action" }
        return "misc"
    }
}
