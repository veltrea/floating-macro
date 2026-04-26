import XCTest
@testable import FloatingMacroCore

final class HTTPParserTests: XCTestCase {

    // MARK: - Request line & path

    func testSimpleGETNoBody() throws {
        let raw = "GET /state HTTP/1.1\r\nHost: 127.0.0.1:17430\r\n\r\n"
        let result = HTTPParser.parse(raw.data(using: .utf8)!)
        guard case .success(let (req, consumed)) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(req.method, .GET)
        XCTAssertEqual(req.path, "/state")
        XCTAssertTrue(req.query.isEmpty)
        XCTAssertEqual(req.header("Host"), "127.0.0.1:17430")
        XCTAssertEqual(req.header("host"), "127.0.0.1:17430") // case insensitive
        XCTAssertEqual(consumed, raw.utf8.count)
        XCTAssertEqual(req.body.count, 0)
    }

    func testQueryStringParsed() throws {
        let raw = "GET /log/tail?level=warn&since=5m&limit=50 HTTP/1.1\r\n\r\n"
        let result = HTTPParser.parse(raw.data(using: .utf8)!)
        guard case .success(let (req, _)) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(req.path, "/log/tail")
        XCTAssertEqual(req.query["level"], "warn")
        XCTAssertEqual(req.query["since"], "5m")
        XCTAssertEqual(req.query["limit"], "50")
    }

    func testURLDecodingInQuery() throws {
        let raw = "GET /x?msg=hello%20world&plus=a+b HTTP/1.1\r\n\r\n"
        let result = HTTPParser.parse(raw.data(using: .utf8)!)
        guard case .success(let (req, _)) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(req.query["msg"], "hello world")
        XCTAssertEqual(req.query["plus"], "a b")
    }

    // MARK: - Body

    func testPOSTWithJSONBody() throws {
        let body = #"{"value":0.5}"#
        let raw = """
        POST /window/opacity HTTP/1.1\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        let result = HTTPParser.parse(raw.data(using: .utf8)!)
        guard case .success(let (req, consumed)) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(req.method, .POST)
        XCTAssertEqual(req.path, "/window/opacity")
        XCTAssertEqual(req.body.count, body.utf8.count)
        XCTAssertEqual(consumed, raw.utf8.count)
        let dict = req.jsonDictionary()
        XCTAssertEqual(dict?["value"] as? Double, 0.5)
    }

    // MARK: - Incomplete body handling

    func testIncompleteBodyReported() throws {
        let raw = "POST /x HTTP/1.1\r\nContent-Length: 20\r\n\r\nonly10byte"
        let result = HTTPParser.parse(raw.data(using: .utf8)!)
        switch result {
        case .failure(.incompleteBody(expected: 20, got: 10)):
            break // expected
        default:
            XCTFail("expected incompleteBody, got \(result)")
        }
    }

    func testEmptyBufferIsEmptyError() {
        switch HTTPParser.parse(Data()) {
        case .failure(.empty): break
        default: XCTFail("expected .empty error")
        }
    }

    // MARK: - Malformed inputs

    func testMalformedRequestLine() {
        let raw = "not-a-valid-line\r\n\r\n"
        switch HTTPParser.parse(raw.data(using: .utf8)!) {
        case .failure(.malformedRequestLine): break
        default: XCTFail("expected malformedRequestLine")
        }
    }

    func testUnsupportedMethod() {
        let raw = "PATCH /x HTTP/1.1\r\n\r\n"
        switch HTTPParser.parse(raw.data(using: .utf8)!) {
        case .failure(.unsupportedMethod("PATCH")): break
        default: XCTFail("expected unsupportedMethod(PATCH)")
        }
    }

    // MARK: - Response serialization

    func testResponseSerializationIncludesDefaults() {
        let res = HTTPResponse.jsonText(#"{"ok":true}"#)
        let data = res.serialize()
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(str.contains("Content-Type: application/json"))
        XCTAssertTrue(str.contains("Content-Length: 11"))
        XCTAssertTrue(str.contains("Connection: close"))
        XCTAssertTrue(str.hasSuffix(#"{"ok":true}"#))
    }

    func testJSONConvenienceBuilder() {
        let res = HTTPResponse.json(["a": 1, "b": "x"])
        XCTAssertEqual(res.status, 200)
        let obj = try? JSONSerialization.jsonObject(with: res.body) as? [String: Any]
        XCTAssertEqual(obj?["a"] as? Int, 1)
        XCTAssertEqual(obj?["b"] as? String, "x")
    }

    func testErrorBuilders() {
        XCTAssertEqual(HTTPResponse.badRequest("bad").status, 400)
        XCTAssertEqual(HTTPResponse.notFound("/x").status, 404)
        XCTAssertEqual(HTTPResponse.methodNotAllowed("/x", method: "POST").status, 405)
        XCTAssertEqual(HTTPResponse.internalError("oops").status, 500)
    }
}
