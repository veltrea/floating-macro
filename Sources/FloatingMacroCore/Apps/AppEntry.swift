import Foundation

/// Pure data describing a discoverable macOS application.
///
/// This is the lingua franca between `FileSystemAppListProvider` (which
/// scans the filesystem), the picker UI in the App layer, and the icon
/// extraction pipeline. It carries only Foundation types so it lives
/// happily in `FloatingMacroCore`.
public struct AppEntry: Equatable, Hashable {
    /// File URL pointing at the `.app` bundle.
    public let url: URL

    /// User-facing name. Sourced from the bundle's `CFBundleDisplayName`,
    /// then `CFBundleName`, then the filename without `.app` as a last
    /// resort.
    public let displayName: String

    /// Reverse-DNS bundle identifier (e.g. `com.apple.calculator`).
    /// `nil` when the bundle has no Info.plist or omits the key.
    public let bundleIdentifier: String?

    public init(url: URL, displayName: String, bundleIdentifier: String?) {
        self.url = url
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
    }
}
