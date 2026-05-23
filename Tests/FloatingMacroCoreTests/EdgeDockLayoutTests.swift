import XCTest
@testable import FloatingMacroCore

final class EdgeDockLayoutTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testSingleBarRightEdgeCentered() {
        let bars: [(id: String, size: CGSize)] = [
            (id: "p1", size: CGSize(width: 28, height: 100)),
        ]
        let result = EdgeDockLayout.positions(edge: .right, screenFrame: screen, bars: bars)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "p1")
        XCTAssertEqual(result[0].origin.x, 1920 - 28, accuracy: 0.1)
        XCTAssertEqual(result[0].origin.y, 1080 / 2 - 100 / 2, accuracy: 0.1)
    }

    func testSingleBarLeftEdge() {
        let bars: [(id: String, size: CGSize)] = [
            (id: "p1", size: CGSize(width: 28, height: 80)),
        ]
        let result = EdgeDockLayout.positions(edge: .left, screenFrame: screen, bars: bars)
        XCTAssertEqual(result[0].origin.x, 0, accuracy: 0.1)
    }

    func testSingleBarTopEdge() {
        let bars: [(id: String, size: CGSize)] = [
            (id: "p1", size: CGSize(width: 120, height: 26)),
        ]
        let result = EdgeDockLayout.positions(edge: .top, screenFrame: screen, bars: bars)
        XCTAssertEqual(result[0].origin.y, 1080 - 26, accuracy: 0.1)
        XCTAssertEqual(result[0].origin.x, 1920 / 2 - 120 / 2, accuracy: 0.1)
    }

    func testSingleBarBottomEdge() {
        let bars: [(id: String, size: CGSize)] = [
            (id: "p1", size: CGSize(width: 120, height: 26)),
        ]
        let result = EdgeDockLayout.positions(edge: .bottom, screenFrame: screen, bars: bars)
        XCTAssertEqual(result[0].origin.y, 0, accuracy: 0.1)
    }

    func testMultipleBarsRightEdgeNoOverlap() {
        let bars: [(id: String, size: CGSize)] = [
            (id: "p1", size: CGSize(width: 28, height: 80)),
            (id: "p2", size: CGSize(width: 28, height: 100)),
            (id: "p3", size: CGSize(width: 28, height: 60)),
        ]
        let result = EdgeDockLayout.positions(edge: .right, screenFrame: screen, bars: bars)
        XCTAssertEqual(result.count, 3)

        // Check that bars do not overlap
        for i in 0..<result.count - 1 {
            let bottom1 = result[i].origin.y
            let top2 = result[i + 1].origin.y + bars[i + 1].size.height
            XCTAssertGreaterThanOrEqual(bottom1, top2, "bar \(i) and \(i+1) Overlapping")
        }
    }

    func testMultipleBarsTopEdgeNoOverlap() {
        let bars: [(id: String, size: CGSize)] = [
            (id: "p1", size: CGSize(width: 100, height: 26)),
            (id: "p2", size: CGSize(width: 120, height: 26)),
        ]
        let result = EdgeDockLayout.positions(edge: .top, screenFrame: screen, bars: bars)
        XCTAssertEqual(result.count, 2)

        let right1 = result[0].origin.x + bars[0].size.width
        let left2 = result[1].origin.x
        XCTAssertLessThanOrEqual(right1, left2, "Overlapping horizontal bar")
    }

    func testEmptyBarsReturnsEmpty() {
        let result = EdgeDockLayout.positions(edge: .right, screenFrame: screen, bars: [])
        XCTAssertTrue(result.isEmpty)
    }
}
