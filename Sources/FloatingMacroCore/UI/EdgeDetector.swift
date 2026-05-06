import Foundation

public struct EdgeDetector {
    /// パネルの中心座標から最寄りの画面辺を判定する。
    public static func nearestEdge(
        panelCenter: CGPoint,
        screenFrame: CGRect
    ) -> DockEdge {
        let distances: [(DockEdge, CGFloat)] = [
            (.left,   panelCenter.x - screenFrame.minX),
            (.right,  screenFrame.maxX - panelCenter.x),
            (.top,    screenFrame.maxY - panelCenter.y),
            (.bottom, panelCenter.y - screenFrame.minY),
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }
}
