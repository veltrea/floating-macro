import Foundation

/// Writes one JSON event per line to a file, rotating when the file exceeds
/// `maxBytes`. On rotation the current file is renamed with a `.old` suffix
/// (overwriting any previous `.old`) and a fresh file is opened.
///
/// All writes are serialized through a dedicated queue. Call `flush()` to
/// block until pending writes are drained (used by tests).
public final class FileLogWriter: FMLogger {
    public let minimumLevel: LogLevel
    private let url: URL
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "fm.filelog", qos: .utility)
    private var handle: FileHandle?

    /// - Parameters:
    ///   - url: target log file. Parent directory is created if missing.
    ///   - minimumLevel: events below this are dropped.
    ///   - maxBytes: rotate threshold in bytes. Defaults to 10 MiB per SPEC §10.1.
    public init(url: URL,
                minimumLevel: LogLevel = .info,
                maxBytes: Int = 10 * 1024 * 1024) throws {
        self.url = url
        self.minimumLevel = minimumLevel
        self.maxBytes = maxBytes

        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        self.handle = try FileHandle(forWritingTo: url)
        _ = try self.handle?.seekToEnd()
    }

    deinit {
        try? handle?.close()
    }

    public func log(_ event: LogEvent) {
        guard event.level >= minimumLevel else { return }
        queue.async { [weak self] in
            self?.rotateIfNeeded()
            self?.writeLine(event)
        }
    }

    public func flush() {
        queue.sync { [weak self] in
            try? self?.handle?.synchronize()
        }
    }

    // MARK: - Private

    /// Path that receives the old log when we rotate.
    /// `foo.log` → `foo.log.old`.
    private var rotatedURL: URL {
        url.appendingPathExtension("old")
    }

    private func currentFileSize() -> Int {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        return (attrs[.size] as? Int) ?? 0
    }

    private func rotateIfNeeded() {
        guard currentFileSize() >= maxBytes else { return }

        try? handle?.close()
        handle = nil

        let fm = FileManager.default
        // Overwrite any previous .old.
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: url, to: rotatedURL)

        fm.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    private func writeLine(_ event: LogEvent) {
        guard let handle = handle,
              let data = try? JSONEncoder.fmLogEncoder.encode(event) else { return }
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data([0x0A])) // '\n'
    }
}
