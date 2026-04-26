import AppKit
import FloatingMacroCore

/// Turns an icon reference (file path or bundle identifier) from a button
/// definition into an `NSImage` suitable for display / export. Results are
/// cached per process to avoid repeated disk reads.
enum IconLoader {

    /// In-memory cache keyed by the raw reference string.
    private static var cache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    /// Load the NSImage for a button's `icon` field, or return nil if the
    /// reference is missing / invalid / unresolvable.
    static func image(for reference: String?) -> NSImage? {
        guard let reference = reference, !reference.isEmpty else { return nil }

        cacheLock.lock()
        if let cached = cache[reference] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let image: NSImage?
        switch IconResolver.resolve(reference) {
        case .success(.imageFile(let url)):
            image = NSImage(contentsOf: url)
        case .success(.appBundle(let url)):
            image = NSWorkspace.shared.icon(forFile: url.path)
        case .success(.bundleIdentifier(let bid)):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                image = nil
            }
        case .success(.systemSymbol(let name)):
            // SF Symbol (Apple system icon). No bundle lookup needed.
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .success(.bundledIcon(let pack, let name)):
            // Resource icon shipped inside the app. Bundle.module is the
            // SwiftPM-generated bundle that owns our Resources directory.
            if let url = Bundle.module.url(forResource: name,
                                           withExtension: "svg",
                                           subdirectory: pack) {
                image = NSImage(contentsOf: url)
            } else {
                image = nil
            }
        case .failure:
            image = nil
        }

        if let image = image {
            cacheLock.lock()
            cache[reference] = image
            cacheLock.unlock()
        }
        return image
    }

    /// Export an NSImage as PNG data. Used by the /icon/for-app HTTP endpoint.
    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Fetch an app's icon (PNG) by bundle id OR absolute path.
    static func pngForApp(bundleIdentifier: String? = nil,
                          path: String? = nil) -> Data? {
        var image: NSImage?
        if let bid = bundleIdentifier, !bid.isEmpty {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
        } else if let p = path, !p.isEmpty {
            let expanded = (p as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                image = NSWorkspace.shared.icon(forFile: expanded)
            }
        }
        guard let image = image else { return nil }
        return pngData(image)
    }

    /// Clear the entire cache. Called after a preset edit that could change
    /// what an icon resolves to.
    static func invalidate() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}
