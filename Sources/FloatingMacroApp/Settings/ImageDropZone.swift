import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FloatingMacroCore

/// Visual representation for registering icons and thumbnails in the edit window.
/// Drop frame. Drag & drop and click to guide references with reference lines, excluding the text field.
///
/// When there is content (image / emoji), preview it
/// Show guidance text and dashed frame when empty
/// During drag-over, provide feedback with a thicker frame in accent color.
/// Launch onClickFallback via click (for people who can't use keyboard or drop)
struct ImageDropZone<Content: View>: View {
    /// Display scale size. Icon: 96 square, thumbnail: 160x120 etc.
    let width: CGFloat
    let height: CGFloat
    /// Is it empty? Used for determining placeholder display.
    let isEmpty: Bool
    /// Placeholder caption for use (e.g., "Drop image here").
    let placeholderCaption: String
    /// placeholder SF Symbol name (e.g., "photo.on.rectangle.angled").
    let placeholderSystemImage: String
    /// The content. It is drawn when `isEmpty == false`.
    @ViewBuilder let content: () -> Content
    /// Image file URL is called when dropped (main path of DnD).
    let onDropImageURL: (URL) -> Void
    /// Fallback when clicking the frame (e.g., NSOpenPanel launch).
    let onClickFallback: () -> Void

    @State private var isDropTargeted: Bool = false

    var body: some View {
        ZStack {
            backgroundShape
            if isEmpty {
                placeholder
            } else {
                content()
                    .padding(6)
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onClickFallback() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .help(L("Drop image to register, click to select file e7adb4"))
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                isDropTargeted ? Color.accentColor : Color.gray.opacity(0.4),
                style: StrokeStyle(
                    lineWidth: isDropTargeted ? 2.5 : 1.5,
                    dash: isEmpty ? [5, 3] : []
                )
            )
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isDropTargeted
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(0.05)
                    )
            )
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: placeholderSystemImage)
                .font(.system(size: 22))
            Text(placeholderCaption)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(.secondary)
        .padding(8)
    }

    /// Get the first image file URL from an array of `NSItemProvider`.
    /// Pass to `onDropImageURL`. If accepted, return true to SwiftUI.
    /// Notify success by changing to a green checkmark and normal cursor.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                          options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            } else {
                url = nil
            }
            guard let resolvedURL = url else { return }
            DispatchQueue.main.async {
                onDropImageURL(resolvedURL)
            }
        }
        return true
    }
}

/// Icon drop zone (96pt square). Image if available, otherwise emoji.
/// If there is nothing else, display a placeholder.
struct IconDropZoneView: View {
    /// Current icon reference (file path / sf:foo / bundle id, etc.).
    let iconRef: String
    /// Fallback emoji when image reference is missing.
    let iconText: String
    let onDropImageURL: (URL) -> Void
    let onClickFallback: () -> Void

    private var resolvedImage: NSImage? {
        IconLoader.image(for: iconRef.isEmpty ? nil : iconRef)
    }

    private var isEmpty: Bool {
        resolvedImage == nil && iconText.isEmpty
    }

    var body: some View {
        ImageDropZone(
            width: 96,
            height: 96,
            isEmpty: isEmpty,
            placeholderCaption: L("Drop image _n or click 44aa84"),
            placeholderSystemImage: "photo.on.rectangle.angled",
            content: {
                if let img = resolvedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if !iconText.isEmpty {
                    Text(iconText)
                        .font(.system(size: 36))
                }
            },
            onDropImageURL: onDropImageURL,
            onClickFallback: onClickFallback
        )
    }
}

/// Thumbnail drop zone (160x120). Image if available, otherwise
/// Display a placeholder. It is for card display type, so no emoji fallback will be shown.
struct ThumbnailDropZoneView: View {
    let thumbnailPath: String
    let onDropImageURL: (URL) -> Void
    let onClickFallback: () -> Void

    private var resolvedImage: NSImage? {
        IconLoader.image(for: thumbnailPath.isEmpty ? nil : thumbnailPath)
    }

    var body: some View {
        ImageDropZone(
            width: 160,
            height: 120,
            isEmpty: resolvedImage == nil,
            placeholderCaption: L("Drop thumbnail image or click 323ec0"),
            placeholderSystemImage: "photo.fill.on.rectangle.fill",
            content: {
                if let img = resolvedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            },
            onDropImageURL: onDropImageURL,
            onClickFallback: onClickFallback
        )
    }
}
