import AppKit
import Foundation

/// Fallback icon retrieval using AppKit.
///
/// The main route is `FloatingMacroCore.ImageIOIconExtractor` (.icns pronounced directly).
/// Modern app written in SwiftUI (e.g., UTM), placed in `Contents/Resources/`.
/// There are cases where an app is distributed only with `Assets.car` and does not have `.icns`.
/// In this case, since ImageIO fails, obtain it using `NSWorkspace.icon(forFile:)`.
///
/// `NSWorkspace` is dependent on AppKit, but it's an official long-lived API since macOS 10.0.
/// No external process dependencies like Quick Look daemon.
/// Output speed is in the order of milliseconds, and the AppIcon in Assets.car is resolved and returned by the system.
/// This fallback is closed within the UI layer (FloatingMacroApp).
/// `FloatingMacroCore` is only based on Foundation and ImageIO.
enum NSWorkspaceIconFallback {

    /// Get the icon of `appURL` as a square PNG.
    /// Return nil only if NSWorkspace itself fails (almost never happens).
    static func extractPNG(appURL: URL, size: Int) -> Data? {
        let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
        nsImage.size = NSSize(width: size, height: size)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return png
    }
}
