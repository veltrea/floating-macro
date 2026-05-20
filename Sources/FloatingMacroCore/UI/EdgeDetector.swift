import Foundation

public struct EdgeDetector {
    /// パネルの中心座標から最寄りの画面辺を判定する。
    /// パネル中心が visibleFrame 外の場合でも正しく判定できるようクランプする。
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
