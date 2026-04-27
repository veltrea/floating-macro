import Foundation

/// Minimal HTTP/1.1 request parser. Handles only the subset we actually use
/// for the local control API: single request per connection, text headers,
/// optional body of known Content-Length.
public enum HTTPParseError: Error, Equatable {
    case empty
    case malformedRequestLine(String)
    case unsupportedMethod(String)
    case malformedHeader(String)
    case incompleteBody(expected: Int, got: Int)
}

public enum HTTPParser {

    /// Attempt to parse a complete request out of `data`. Returns:
    /// - `.success(request, consumed)` where `consumed` is the number of
    ///    bytes consumed from the buffer (allowing pipelining / buffer reuse)
    /// - `.failure(.incompleteBody)` if headers are OK but body is still short
    /// - `.failure(...)` for malformed input
    public static func parse(_ data: Data) -> Result<(HTTPRequest, Int), HTTPParseError> {
        // Locate end-of-headers marker.
        let crlfcrlf: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        guard let headerEnd = findRange(of: crlfcrlf, in: data) else {
            return .failure(.empty)
        }
        let headerBlock = data.prefix(headerEnd)
        guard let headerString = String(data: headerBlock, encoding: .utf8) else {
            return .failure(.malformedRequestLine("non-UTF-8 headers"))
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .failure(.malformedRequestLine(headerString))
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count == 3 else {
            return .failure(.malformedRequestLine(requestLine))
        }

        guard let method = HTTPMethod(rawValue: String(parts[0])) else {
            return .failure(.unsupportedMethod(String(parts[0])))
        }

        let rawTarget = String(parts[1])
        let (path, query) = splitPathAndQuery(rawTarget)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.malformedHeader(line))
            }
            let name = String(line[line.startIndex..<colon])
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)..<line.endIndex])
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        // Body length
        let contentLength = Int(headers.first { $0.key.lowercased() == "content-length" }?.value ?? "") ?? 0
        let bodyStart = headerEnd + crlfcrlf.count
        let available = data.count - bodyStart
        if available < contentLength {
            return .failure(.incompleteBody(expected: contentLength, got: available))
        }
        let body: Data
        if contentLength > 0 {
            body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        } else {
            body = Data()
        }

        let consumed = bodyStart + contentLength
        let req = HTTPRequest(method: method,
                              rawTarget: rawTarget,
                              path: path,
                              query: query,
                              headers: headers,
                              body: body)
        return .success((req, consumed))
    }

    // MARK: - Helpers

    /// URL-decode each segment, split by '&' / '=' — no reliance on
    /// URLComponents because paths like "/state" without a scheme trip it up.
    public static func splitPathAndQuery(_ target: String) -> (path: String, query: [String: String]) {
        guard let qmark = target.firstIndex(of: "?") else {
            return (target, [:])
        }
        let path = String(target[..<qmark])
        let qs = String(target[target.index(after: qmark)...])
        var map: [String: String] = [:]
        for pair in qs.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = urlDecode(String(kv[0]))
            let value = kv.count > 1 ? urlDecode(String(kv[1])) : ""
            map[key] = value
        }
        return (path, map)
    }

    private static func urlDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? s
    }

    private static func findRange(of needle: [UInt8], in haystack: Data) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for i in 0...(haystack.count - needle.count) {
            var match = true
            for j in 0..<needle.count {
                if haystack[haystack.startIndex + i + j] != needle[j] {
                    match = false; break
                }
            }
            if match { return i }
        }
        return nil
    }
}
