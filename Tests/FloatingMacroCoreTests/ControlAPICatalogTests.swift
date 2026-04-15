import XCTest
@testable import FloatingMacroCore

// MARK: - ToolCatalog

final class ToolCatalogTests: XCTestCase {

    func testAllToolsHaveNameAndDescription() {
        for tool in ToolCatalog.tools {
            XCTAssertFalse(tool.name.isEmpty, "tool name must not be empty")
            XCTAssertFalse(tool.description.isEmpty, "tool \(tool.name) missing description")
        }
    }

    func testNamesAreUnique() {
        let names = ToolCatalog.tools.map(\.name)
        XCTAssertEqual(Set(names).count, names.count,
                       "tool names must be unique")
    }

    func testHelpAndManifestBothExist() {
        XCTAssertNotNil(ToolCatalog.find("help"))
        XCTAssertNotNil(ToolCatalog.find("manifest"))
        XCTAssertEqual(ToolCatalog.find("help")?.path, "/manifest")
    }

    func testRenderMCPIncludesTransport() {
        let rendered = ToolCatalog.render(dialect: .mcp)
        guard let tools = rendered["tools"] as? [[String: Any]] else {
            return XCTFail("expected tools array")
        }
        XCTAssertGreaterThan(tools.count, 10)
        let first = tools[0]
        XCTAssertNotNil(first["name"])
        XCTAssertNotNil(first["description"])
        XCTAssertNotNil(first["inputSchema"])
        XCTAssertNotNil(first["_transport"])
    }

    func testRenderOpenAISchema() {
        let rendered = ToolCatalog.render(dialect: .openai)
        guard let tools = rendered["tools"] as? [[String: Any]] else {
            return XCTFail("expected tools array")
        }
        let first = tools[0]
        XCTAssertEqual(first["type"] as? String, "function")
        let function = first["function"] as? [String: Any]
        XCTAssertNotNil(function?["name"])
        XCTAssertNotNil(function?["parameters"])
    }

    func testRenderAnthropicSchema() {
        let rendered = ToolCatalog.render(dialect: .anthropic)
        guard let tools = rendered["tools"] as? [[String: Any]] else {
            return XCTFail("expected tools array")
        }
        let first = tools[0]
        XCTAssertNotNil(first["name"])
        XCTAssertNotNil(first["description"])
        XCTAssertNotNil(first["input_schema"])
        XCTAssertNil(first["inputSchema"],
                     "Anthropic uses snake_case input_schema, not camelCase")
    }
}

// MARK: - SystemPrompt

final class SystemPromptTests: XCTestCase {

    func testManifestIncludesAllKeyFields() {
        let m = SystemPrompt.manifest()
        XCTAssertEqual(m["product"] as? String, "FloatingMacro")
        XCTAssertNotNil(m["version"])
        XCTAssertNotNil(m["systemPrompt"])
        XCTAssertNotNil(m["quickStart"])
        XCTAssertNotNil(m["endpoints"])
        XCTAssertNotNil(m["tools"])
    }

    func testGreetingDescribesUser() {
        // The greeting must mention physical-limitation context so AI
        // agents behave accordingly.
        XCTAssertTrue(SystemPrompt.greeting.contains("身体的"))
        XCTAssertTrue(SystemPrompt.greeting.contains("AI"))
    }
}

// MARK: - OpenAPI

final class OpenAPIGeneratorTests: XCTestCase {

    func testOpenAPIBasics() {
        let doc = OpenAPIGenerator.document()
        XCTAssertEqual(doc["openapi"] as? String, "3.1.0")
        XCTAssertNotNil(doc["info"])
        XCTAssertNotNil(doc["paths"])
    }

    func testEveryToolIsExposedAsPath() {
        let doc = OpenAPIGenerator.document()
        let paths = doc["paths"] as? [String: Any] ?? [:]
        for tool in ToolCatalog.tools {
            XCTAssertNotNil(paths[tool.path], "missing path \(tool.path) for tool \(tool.name)")
        }
    }

    func testPOSTOperationsHaveRequestBody() {
        let doc = OpenAPIGenerator.document()
        let paths = doc["paths"] as? [String: Any] ?? [:]
        // /window/move is POST with x/y required.
        let entry = paths["/window/move"] as? [String: Any]
        let post = entry?["post"] as? [String: Any]
        XCTAssertNotNil(post?["requestBody"])
    }

    func testGETOperationsHaveQueryParams() {
        let doc = OpenAPIGenerator.document()
        let paths = doc["paths"] as? [String: Any] ?? [:]
        let entry = paths["/log/tail"] as? [String: Any]
        let get = entry?["get"] as? [String: Any]
        let params = get?["parameters"] as? [[String: Any]] ?? []
        XCTAssertFalse(params.isEmpty)
        let names = params.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("level"))
        XCTAssertTrue(names.contains("limit"))
    }

    func testOpenAPIIsJSONEncodable() throws {
        let doc = OpenAPIGenerator.document()
        let data = try JSONSerialization.data(withJSONObject: doc)
        XCTAssertGreaterThan(data.count, 0)
    }
}

// MARK: - A2A Agent Card

final class AgentCardTests: XCTestCase {

    func testAgentCardBasics() {
        let card = AgentCard.card()
        XCTAssertEqual(card["name"] as? String, "FloatingMacro")
        XCTAssertNotNil(card["description"])
        XCTAssertNotNil(card["url"])
        XCTAssertNotNil(card["version"])
        XCTAssertNotNil(card["capabilities"])
    }

    func testCapabilitiesFlagsPresent() {
        let card = AgentCard.card()
        let caps = card["capabilities"] as? [String: Any] ?? [:]
        XCTAssertEqual(caps["streaming"] as? Bool, false)
        XCTAssertEqual(caps["pushNotifications"] as? Bool, false)
    }

    func testSkillsMirrorToolCatalog() {
        let card = AgentCard.card()
        let skills = card["skills"] as? [[String: Any]] ?? []
        XCTAssertEqual(skills.count, ToolCatalog.tools.count)
        let skillIds = skills.compactMap { $0["id"] as? String }
        let toolNames = ToolCatalog.tools.map(\.name)
        XCTAssertEqual(Set(skillIds), Set(toolNames))
    }

    func testExtensionsReferenceOtherEndpoints() {
        let card = AgentCard.card()
        let ext = card["x-extensions"] as? [String: Any] ?? [:]
        XCTAssertNotNil(ext["openapi"])
        XCTAssertNotNil(ext["mcp-endpoint"])
        XCTAssertNotNil(ext["manifest"])
    }
}

// MARK: - MCP Adapter

final class MCPAdapterTests: XCTestCase {

    private func jsonData(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    func testParseRequestSuccess() {
        let req = jsonData([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
        ])
        switch MCPAdapter.parseRequest(req) {
        case .success(let request):
            XCTAssertEqual(request.id as? Int, 1)
            XCTAssertEqual(request.method, "tools/list")
        case .failure:
            XCTFail("expected success")
        }
    }

    func testParseRequestInvalidVersion() {
        let req = jsonData(["jsonrpc": "1.0", "method": "x"])
        switch MCPAdapter.parseRequest(req) {
        case .failure(let response):
            XCTAssertEqual(response.error?.code, -32600)
        default: XCTFail("expected failure")
        }
    }

    func testParseRequestMalformedJSON() {
        switch MCPAdapter.parseRequest(Data("not json".utf8)) {
        case .failure(let response):
            XCTAssertEqual(response.error?.code, -32700)
        default: XCTFail("expected parse error")
        }
    }

    func testInitializeReturnsServerInfo() {
        let request = MCPAdapter.Request(id: 1, method: "initialize", params: [:])
        let response = MCPAdapter.handle(request) { _, _ in .success([:]) }
        XCTAssertNil(response.error)
        let result = response.result ?? [:]
        let serverInfo = result["serverInfo"] as? [String: Any]
        XCTAssertEqual(serverInfo?["name"] as? String, "FloatingMacro")
        let caps = result["capabilities"] as? [String: Any]
        XCTAssertNotNil(caps?["tools"])
    }

    func testToolsListReturnsAllTools() {
        let request = MCPAdapter.Request(id: 1, method: "tools/list", params: [:])
        let response = MCPAdapter.handle(request) { _, _ in .success([:]) }
        let result = response.result ?? [:]
        let tools = result["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.count, ToolCatalog.tools.count)
    }

    func testToolsCallInvokesCallback() {
        var receivedName: String?
        let request = MCPAdapter.Request(
            id: 2,
            method: "tools/call",
            params: ["name": "ping", "arguments": [:]] as [String: Any]
        )
        let response = MCPAdapter.handle(request) { name, _ in
            receivedName = name
            return .success(["ok": true])
        }
        XCTAssertEqual(receivedName, "ping")
        let result = response.result ?? [:]
        let content = result["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.first?["type"] as? String, "text")
    }

    func testToolsCallReportsError() {
        let request = MCPAdapter.Request(
            id: 3, method: "tools/call",
            params: ["name": "broken", "arguments": [:]] as [String: Any]
        )
        let response = MCPAdapter.handle(request) { _, _ in
            .failure(.methodNotFound)
        }
        XCTAssertEqual(response.error?.code, -32601)
    }

    func testUnknownMethodReturns32601() {
        let request = MCPAdapter.Request(id: 4, method: "bogus", params: [:])
        let response = MCPAdapter.handle(request) { _, _ in .success([:]) }
        XCTAssertEqual(response.error?.code, -32601)
    }

    func testResponseSerializationShape() {
        let req = MCPAdapter.Request(id: 1, method: "ping", params: [:])
        let response = MCPAdapter.handle(req) { _, _ in .success([:]) }
        let obj = response.serialize()
        XCTAssertEqual(obj["jsonrpc"] as? String, "2.0")
        XCTAssertNotNil(obj["result"])
        XCTAssertNil(obj["error"])
    }
}
