import Foundation

public struct EdgeDockLayout {
    /// Calculates the layout positions for a group of bars docked to the same edge.
    /// The bar arranges the edges with a center base, evenly spaced (gap = 4pt).
    ///
    /// - Parameters:
    /// Dock-side edge
    /// screenFrame: equivalent to `NSScreen.visibleFrame` (excluding menuBar/Dock)
    /// Bars: List of (id, size) pairs of bars docked in this area (in display order).
    /// Returns: Origin (x, y) for each id
    public static func positions(
        edge: DockEdge,
        screenFrame: CGRect,
        bars: [(id: String, size: CGSize)]
    ) -> [(id: String, origin: CGPoint)] {
        guard !bars.isEmpty else { return [] }

        let gap: CGFloat = 4

        switch edge {
        case .left, .right:
            let totalHeight = bars.map(\.size.height).reduce(0, +)
                + CGFloat(bars.count - 1) * gap
            var y = screenFrame.midY + totalHeight / 2

            return bars.map { bar in
                y -= bar.size.height
                let x: CGFloat
                if edge == .right {
                    x = screenFrame.maxX - bar.size.width
                } else {
                    x = screenFrame.minX
                }
                let origin = CGPoint(x: x, y: y)
                y -= gap
                return (id: bar.id, origin: origin)
            }

        case .top, .bottom:
            let totalWidth = bars.map(\.size.width).reduce(0, +)
                + CGFloat(bars.count - 1) * gap
            var x = screenFrame.midX - totalWidth / 2

            return bars.map { bar in
                let y: CGFloat
                if edge == .top {
                    y = screenFrame.maxY - bar.size.height
                } else {
                    y = screenFrame.minY
                }
                let origin = CGPoint(x: x, y: y)
                x += bar.size.width + gap
                return (id: bar.id, origin: origin)
            }
        }
    }
}
