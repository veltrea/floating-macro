import XCTest
@testable import FloatingMacroCore

// wrapWithAuth は FloatingMacroApp ターゲットにあるため、ここでは同等のロジックを
// 直接テストするのではなく、HTTPRequest / HTTPResponse の型を使った結合テストとして
// 認証ミドルウェアの挙動を検証する。
//
// ControlHandlers.swift（FloatingMacroApp）の wrapWithAuth を呼ぶには
// FloatingMacroApp への依存が必要になるため、FloatingMacroCore 側で同じロジックを
// 持つヘルパーを定義してテストする。
//
// このテストで確認する契約:
//   - token == nil のとき全リクエストが通る
//   - /ping はトークンなしで通る
//   - 正しい Bearer トークンで通る
//   - 間違いトークンで 401
//   - Authorization ヘッダーなしで 401

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
