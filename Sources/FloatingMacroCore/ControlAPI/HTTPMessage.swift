import Foundation

/// A minimal HTTP/1.1 request / response representation used by the local
/// control API. Only the parts we actually exercise are modeled:
/// - Single-line request line (method + path + version)
/// - Headers are case-insensitive on lookup but preserve the original
///   casing for outgoing responses.
/// - Body is raw `Data` (no chunked transfer encoding, no compression).
///
/// Keep-alive is NOT supported — every connection handles one request then
/// closes.

public enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case OPTIONS
    case HEAD
}

public struct HTTPRequest: Equatable {
    public let method: HTTPMethod
    public let rawTarget: String       // "/state?x=1"
    public let path: String            // "/state"
    public let query: [String: String] // ["x": "1"]
    public let headers: [String: String]
    public let body: Data

    public init(method: HTTPMethod,
                rawTarget: String,
                path: String,
                query: [String: String] = [:],
                headers: [String: String] = [:],
                body: Data = Data()) {
        self.method = method
        self.rawTarget = rawTarget
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// Case-insensitive header lookup.
    public func header(_ name: String) -> String? {
        let lower = name.lowercased()
        for (k, v) in headers where k.lowercased() == lower {
            return v
        }
        return nil
    }

    /// Decode the body as JSON into `T`. Returns nil on any failure.
    public func jsonBody<T: Decodable>(as type: T.Type) -> T? {
        guard !body.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: body)
    }

    /// Decode the body as a `[String: Any]` dictionary for dynamic access.
    public func jsonDictionary() -> [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

public struct HTTPResponse {
    public let status: Int
    public let reason: String
    public let headers: [(String, String)]
    public let body: Data

    public init(status: Int, reason: String,
                headers: [(String, String)] = [],
                body: Data = Data()) {
        self.status = status
        self.reason = reason
        self.headers = headers
        self.body = body
    }

    /// Serialize to wire bytes.
    public func serialize() -> Data {
        var out = "HTTP/1.1 \(status) \(reason)\r\n"
        var seen = Set<String>()
        for (k, v) in headers {
            seen.insert(k.lowercased())
            out += "\(k): \(v)\r\n"
        }
        if !seen.contains("content-length") {
            out += "Content-Length: \(body.count)\r\n"
        }
        if !seen.contains("connection") {
            out += "Connection: close\r\n"
        }
        out += "\r\n"
        var data = out.data(using: .utf8) ?? Data()
        data.append(body)
        return data
    }

    // MARK: - Convenience constructors

    public static func ok(_ body: Data = Data(),
                          contentType: String = "application/json") -> HTTPResponse {
        HTTPResponse(status: 200, reason: "OK",
                     headers: [("Content-Type", contentType)],
                     body: body)
    }

    public static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, reason: status == 200 ? "OK" : "Error",
                            headers: [("Content-Type", "application/json")],
                            body: data)
    }

    public static func jsonText(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, reason: status == 200 ? "OK" : "Error",
                     headers: [("Content-Type", "application/json")],
                     body: body.data(using: .utf8) ?? Data())
    }

    public static func badRequest(_ message: String) -> HTTPResponse {
        .json(["error": message], status: 400)
    }

    public static func notFound(_ path: String) -> HTTPResponse {
        .json(["error": "not found", "path": path], status: 404)
    }

    public static func methodNotAllowed(_ path: String, method: String) -> HTTPResponse {
        .json(["error": "method not allowed", "path": path, "method": method], status: 405)
    }

    public static func internalError(_ message: String) -> HTTPResponse {
        .json(["error": message], status: 500)
    }
}
