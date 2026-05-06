import AppKit
import QuartzCore

/// パネル ↔ Edge Dock 移動時のスライドトランジション。
final class DockTransitionAnimator {

    static func animateSlide(from sourceFrame: NSRect,
                             to destFrame: NSRect,
                             duration: TimeInterval = 0.35,
                             completion: (() -> Void)? = nil) {
        let overlay = makeOverlayWindow(frame: sourceFrame)
        let borderView = SlideBorderView(frame: NSRect(origin: .zero, size: sourceFrame.size))
        overlay.contentView = borderView
        overlay.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlay.animator().setFrame(destFrame, display: true)
            overlay.animator().alphaValue = 0.3
        }, completionHandler: {
            overlay.orderOut(nil)
            completion?()
        })
    }

    private static func makeOverlayWindow(frame: NSRect) -> NSWindow {
        let w = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = .floating + 1
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.hasShadow = false
        return w
    }
}

private final class SlideBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)

        NSColor.controlAccentColor.withAlphaComponent(0.5).setFill()
        path.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
