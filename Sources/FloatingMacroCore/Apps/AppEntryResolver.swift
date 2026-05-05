import Foundation

/// Resolves a single `.app` URL into an `AppEntry` by reading its
/// Info.plist with Foundation's `PropertyListSerialization`.
///
/// Why a free `enum` namespace instead of `Bundle(url:)`? `Bundle(url:)`
/// is fine but pulls additional Foundation initialisation behind the
/// scenes (loaded principal class lookup, executable arch checks, etc.)
/// that occasionally cause surprising slowness on bundles that aren't
/// fully populated. Reading the plist directly is a few lines and is
/// cheaper, more predictable, and trivially testable with hand-built
/// stub `.app` directories.
public enum AppEntryResolver {

    /// Build an `AppEntry` for the given `.app` URL. Returns `nil` only
    /// for input URLs that obviously aren't an app bundle (wrong path
    /// extension, file doesn't exist).
    ///
    /// A bundle without an Info.plist still resolves successfully — the
    /// `displayName` falls back to the filename and `bundleIdentifier`
    /// is `nil`. Callers can decide how to handle missing identifiers.
    public static func resolve(at appURL: URL) -> AppEntry? {
        guard appURL.pathExtension.lowercased() == "app" else { return nil }
        guard FileManager.default.fileExists(atPath: appURL.path) else { return nil }

        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        var bundleId: String? = nil
        var displayName: String? = nil

        if let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(
               from: data, format: nil) as? [String: Any] {
            bundleId = (plist["CFBundleIdentifier"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
            displayName = (plist["CFBundleDisplayName"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? (plist["CFBundleName"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        let fallbackName = appURL.deletingPathExtension().lastPathComponent

        return AppEntry(
            url: appURL,
            displayName: displayName ?? fallbackName,
            bundleIdentifier: bundleId
        )
    }
}
