import XCTest
@testable import FloatingMacroCore

// wrapWithAuth is in the FloatingMacroApp target, so here we have an equivalent logic.
// Directly testing is not used; instead, it is used as a combination test using the types of HTTPRequest and HTTPResponse.
// Verify the behavior of authentication middleware.
//
// To call wrapWithAuth in ControlHandlers.swift (FloatingMacroApp), you need to: 
1. Import the necessary modules.
2. Ensure that the function is accessible within your scope.
3. Call the function with appropriate parameters as required by its definition.
// Because dependency on FloatingMacroApp is required, the same logic needs to be implemented on the FloatingMacroCore side.
// Define and test helper functions.
//
// This contract to be confirmed in the test:
// When `token` is `nil`, all requests succeed.
// /ping passes without a token
// Passes with correct Bearer token
// Error token for 401
// Unauthorized without authorization header

private func makeAuthMiddleware(
    token: String?,
    handler: @escaping (HTTPRequest) -> HTTPResponse
) -> (HTTPRequest) -> HTTPResponse {
    return { req in
        guard let expected = token else { return handler(req) }
        let publicPaths: Set<String> = ["/ping", "/health"]
        if publicPaths.contains(req.path) { return handler(req) }
        guard let header = req.header("Authorization"),
              header.hasPrefix("Bearer "),
              header.dropFirst("Bearer ".count) == expected else {
            return HTTPResponse(
                status: 401, reason: "Unauthorized",
                headers: [("Content-Type", "application/json")],
                body: Data()
            )
        }
        return handler(req)
    }
}

private func makeReq(path: String, authHeader: String? = nil) -> HTTPRequest {
    var headers: [String: String] = [:]
    if let h = authHeader { headers["Authorization"] = h }
    return HTTPRequest(method: .GET, rawTarget: path, path: path,
                       query: [:], headers: headers, body: Data())
}

final class AuthMiddlewareTests: XCTestCase {

    private let okHandler: (HTTPRequest) -> HTTPResponse = { _ in
        HTTPResponse(status: 200, reason: "OK", headers: [], body: Data())
    }

    func test_nilToken_allowsAllRequests() {
        let mw = makeAuthMiddleware(token: nil, handler: okHandler)
        XCTAssertEqual(mw(makeReq(path: "/state")).status, 200)
        XCTAssertEqual(mw(makeReq(path: "/ping")).status, 200)
        XCTAssertEqual(mw(makeReq(path: "/mcp")).status, 200)
    }

    func test_pingPassesWithoutToken() {
        let mw = makeAuthMiddleware(token: "secret", handler: okHandler)
        XCTAssertEqual(mw(makeReq(path: "/ping")).status, 200)
        XCTAssertEqual(mw(makeReq(path: "/health")).status, 200)
    }

    func test_correctBearerTokenPasses() {
        let mw = makeAuthMiddleware(token: "mytoken", handler: okHandler)
        let req = makeReq(path: "/state", authHeader: "Bearer mytoken")
        XCTAssertEqual(mw(req).status, 200)
    }

    func test_wrongTokenReturns401() {
        let mw = makeAuthMiddleware(token: "correct", handler: okHandler)
        let req = makeReq(path: "/state", authHeader: "Bearer wrong")
        XCTAssertEqual(mw(req).status, 401)
    }

    func test_missingAuthHeaderReturns401() {
        let mw = makeAuthMiddleware(token: "secret", handler: okHandler)
        XCTAssertEqual(mw(makeReq(path: "/state")).status, 401)
    }

    func test_malformedAuthHeaderReturns401() {
        let mw = makeAuthMiddleware(token: "secret", handler: okHandler)
        let req = makeReq(path: "/state", authHeader: "Token secret")
        XCTAssertEqual(mw(req).status, 401)
    }
}
