import Foundation

/// Read-only client for the public preset catalog hosted at
/// `https://github.com/veltrea/floating-macro-preset`. Fetches `index.json`
/// (the catalog manifest) and individual `presets/<id>.json` files via the
/// raw.githubusercontent.com CDN.
///
/// Used during first-launch seed installation so the seven default presets
/// can be sourced from the live catalog instead of the in-app copy. All
/// network calls have a short timeout and any failure falls back silently
/// to the bundled seeds — the app must remain functional offline.
public final class PresetCatalogClient {
    /// Manifest schema returned by `index.json`. Forward-compatible: unknown
    /// fields in newer schemas are ignored.
    public struct Index: Codable, Equatable {
        public let schemaVersion: Int
        public let defaults: [String]
        public let presets:  [Entry]
    }

    public struct Entry: Codable, Equatable {
        public let id: String
        public let displayName: String
        public let summary: String?
        public let tags: [String]?
        public let file: String
    }

    /// Default base URL for the public preset catalog. Override via the
    /// `FLOATINGMACRO_PRESET_CATALOG_URL` environment variable for tests or
    /// for users who maintain their own mirror.
    public static let defaultBaseURL = URL(
        string: "https://raw.githubusercontent.com/veltrea/floating-macro-preset/main/"
    )!

    public static let baseURLEnvVar = "FLOATINGMACRO_PRESET_CATALOG_URL"

    private let baseURL: URL
    private let timeout: TimeInterval
    private let session: URLSession

    public init(baseURL: URL? = nil,
                timeout: TimeInterval = 5.0,
                session: URLSession = .shared) {
        if let baseURL {
            self.baseURL = baseURL
        } else if let env = ProcessInfo.processInfo.environment[Self.baseURLEnvVar],
                  !env.isEmpty,
                  let url = URL(string: env) {
            self.baseURL = url
        } else {
            self.baseURL = Self.defaultBaseURL
        }
        self.timeout = timeout
        self.session = session
    }

    /// Fetch and decode `index.json`. Returns nil on any failure (timeout,
    /// non-2xx response, decode error). Errors are logged but never thrown
    /// so the caller can simply branch on Optional.
    public func fetchIndex() -> Index? {
        let url = baseURL.appendingPathComponent("index.json")
        guard let data = fetchData(url: url) else { return nil }
        do {
            return try JSONDecoder().decode(Index.self, from: data)
        } catch {
            LoggerContext.shared.warn("PresetCatalog", "Failed to decode index.json", [
                "error": String(describing: error),
            ])
            return nil
        }
    }

    /// Fetch and decode a single preset by relative file path (as listed in
    /// `Index.Entry.file`). Returns nil on any failure.
    public func fetchPreset(filePath: String) -> Preset? {
        let url = baseURL.appendingPathComponent(filePath)
        guard let data = fetchData(url: url) else { return nil }
        do {
            return try JSONDecoder().decode(Preset.self, from: data)
        } catch {
            LoggerContext.shared.warn("PresetCatalog", "Failed to decode preset", [
                "path":  filePath,
                "error": String(describing: error),
            ])
            return nil
        }
    }

    /// Synchronous data fetch on the calling thread. Designed to be invoked
    /// from a background dispatch queue — calling on the main thread will
    /// block the UI for up to `timeout` seconds.
    ///
    /// `file://` URLs are read directly with `Data(contentsOf:)` because
    /// URLSession's `dataTask` is HTTP-only. The fast-path is intended for
    /// tests that point the catalog at a local fixture directory.
    private func fetchData(url: URL) -> Data? {
        if url.isFileURL {
            do {
                return try Data(contentsOf: url)
            } catch {
                LoggerContext.shared.warn("PresetCatalog", "File fetch failed", [
                    "url":   url.absoluteString,
                    "error": String(describing: error),
                ])
                return nil
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultErr:  Error?

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                resultErr = error
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                resultErr = URLError(.badServerResponse)
                return
            }
            resultData = data
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 1.0)

        if let resultErr {
            LoggerContext.shared.warn("PresetCatalog", "Fetch failed", [
                "url":   url.absoluteString,
                "error": String(describing: resultErr),
            ])
        }
        return resultData
    }
}
