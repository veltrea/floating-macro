import Foundation

public struct EdgeDetector {
    /// Determines the nearest screen edge from the center coordinates of a panel.
    /// Clamp the panel center to be correctly judged even if it is outside the visibleFrame.
    public static func nearestEdge(
        panelCenter: CGPoint,
        screenFrame: CGRect
    ) -> DockEdge {
        let cx = max(screenFrame.minX, min(panelCenter.x, screenFrame.maxX))
        let cy = max(screenFrame.minY, min(panelCenter.y, screenFrame.maxY))
        let distances: [(DockEdge, CGFloat)] = [
            (.left,   cx - screenFrame.minX),
            (.right,  screenFrame.maxX - cx),
            (.top,    screenFrame.maxY - cy),
            (.bottom, cy - screenFrame.minY),
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }
}
