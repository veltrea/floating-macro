import SwiftUI
import AppKit
import FloatingMacroCore

/// An NSScrollView wrapped in an NSViewRepresentable to create a scroll view.
/// The standard SwiftUI ScrollView does not allow reading and writing the current scroll position on macOS 13.
/// There is no official API, so the position cannot be restored after app restart.
/// Using this rapper:
/// Restore scroll position at launch with initial `initialY`.
/// Notify scroll change via `onScrollChange` closure (through PresetManager)
/// Persistent across panels)
/// In the internal `NSClipView.bounds.didChange` notification, pick up changes.
/// The `documentView` uses a flipped coordinate system, so the `bounds.origin.y` is negative.
/// How many pixels have been scrolled down from the top? (Standard Cocoa bottom-up)
/// The value becomes intuitive instead of matching the coordinates (not fitting).
struct PanelScrollView<Content: View>: NSViewRepresentable {

    /// Scroll position at launch (number of pixels from top to bottom, non-negative).
    let initialY: CGFloat
    /// Called when the scroll position changes. The argument is the current `scrollY` (non-negative).
    /// Called in the main queue.
    let onScrollChange: (CGFloat) -> Void
    /// Scrollable content area. SwiftUI view.
    let content: Content

    init(initialY: CGFloat,
         onScrollChange: @escaping (CGFloat) -> Void,
         @ViewBuilder content: () -> Content) {
        self.initialY = initialY
        self.onScrollChange = onScrollChange
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollChange: onScrollChange)
    }

    final class Coordinator: NSObject {
        let onScrollChange: (CGFloat) -> Void
        var hostingView: NSHostingView<Content>?
        weak var scrollViewRef: NSScrollView?
        weak var documentRef: NSView?
        var clipObserver: NSObjectProtocol?
        var hostingFrameObserver: NSObjectProtocol?
        /// Scroll Y to Reflect at Launch SwiftUI Layout Completion Document View
        /// Continue retrying until the height reaches this value + clipView height, and if it can be reflected, return nil.
        /// Unsubscribe and remove.
        var pendingInitialY: CGFloat?
        /// Whether to pass scroll changes to `onScrollChange`. For `scroll(to:)`.
        /// When moving myself, suppress echo back (= overwritten by restore value)
        /// Prevent destruction of persisted values).
        var suppressNotify = false

        init(onScrollChange: @escaping (CGFloat) -> Void) {
            self.onScrollChange = onScrollChange
        }

        deinit {
            if let o = clipObserver { NotificationCenter.default.removeObserver(o) }
            if let o = hostingFrameObserver { NotificationCenter.default.removeObserver(o) }
        }

        @objc func clipBoundsChanged(_ note: Notification) {
            guard !suppressNotify, let clip = note.object as? NSClipView else { return }
            let y = max(0, clip.bounds.origin.y)
            onScrollChange(y)
        }
    }

    /// Adding a `NSView` directly to `hostingView` without adding it to the parent's view hierarchy will not cause the child view to follow the parent's resizing.
    /// Therefore, use autoresizing for width following while leaving height to the intrinsic.
    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false

        let hosting = NSHostingView(rootView: content)
        context.coordinator.hostingView = hosting
        hosting.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(hosting)

        // Pin the hosting to all four sides of the document.
        // Horizontal follows the document width (= clipView width).
        // Vertical direction is determined by the intrinsicContentSize of hosting, which decides the document height.
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: document.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        scrollView.documentView = document

        // Match the width of documentView with clipView.
        scrollView.contentView.postsBoundsChangedNotifications = true
        let widthConstraint = document.widthAnchor.constraint(
            equalTo: scrollView.contentView.widthAnchor)
        widthConstraint.priority = .required
        widthConstraint.isActive = true

        // Monitor scroll position changes.
        context.coordinator.clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coord = context.coordinator] note in
            coord?.clipBoundsChanged(note)
        }

        // Monitor the frame change of NSHostingView. After height is determined by Auto Layout.
        // explicitly synchronizes the frame of documentView. NSScrollView is
        // To determine the scrollable range using documentView.frame.size,
        // Complements cases where Auto Layout alone is slow to reflect changes.
        hosting.postsFrameChangedNotifications = true
        context.coordinator.pendingInitialY = initialY
        context.coordinator.hostingFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak coord = context.coordinator, weak scrollView, weak document, weak hosting] _ in
            guard let coord, let scrollView, let document, let hosting else { return }
            let intrinsicH = hosting.intrinsicContentSize.height
            let frameH = hosting.frame.height
            // Adopt the larger of intrinsic and frame (fallback for cases where intrinsic returns 0).
            // Add 200 to the top and bottom margins respectively.
            let baseH = max(intrinsicH, frameH)
            let targetH = baseH > 0 ? baseH : 0
            if targetH > 0, abs(document.frame.height - targetH) > 1 {
                document.setFrameSize(NSSize(width: document.frame.width, height: targetH))
            }
            // Restoration of initial scroll position.
            tryApplyPendingInitialOffset(coord: coord, scrollView: scrollView,
                                         docHeight: targetH)
        }

        context.coordinator.scrollViewRef = scrollView
        context.coordinator.documentRef = document

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content

        if let document = scrollView.documentView,
           let hosting = context.coordinator.hostingView {
            DispatchQueue.main.async {
                let intrinsicH = hosting.intrinsicContentSize.height
                let frameH = hosting.frame.height
                let baseH = max(intrinsicH, frameH)
                let targetH = baseH > 0 ? baseH + 400 : 0
                if targetH > 0, abs(document.frame.height - targetH) > 1 {
                    document.setFrameSize(NSSize(width: document.frame.width,
                                                  height: targetH))
                }
                tryApplyPendingInitialOffset(coord: context.coordinator,
                                             scrollView: scrollView,
                                             docHeight: targetH)
            }
        }
    }

    private func tryApplyPendingInitialOffset(coord: Coordinator,
                                              scrollView: NSScrollView,
                                              docHeight: CGFloat) {
        guard let pending = coord.pendingInitialY else { return }
        let clipHeight = scrollView.contentView.bounds.height
        guard docHeight > clipHeight else { return }

        let maxY = max(0, docHeight - clipHeight)
        let clampedY = min(max(0, pending), maxY)
        coord.suppressNotify = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        DispatchQueue.main.async {
            coord.suppressNotify = false
        }
        coord.pendingInitialY = nil
    }
}
