import XCTest
@testable import FloatingMacroCore

final class EdgeDetectorTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testNearestEdgeLeft() {
        let center = CGPoint(x: 50, y: 540)
        XCTAssertEqual(EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen), .left)
    }

    func testNearestEdgeRight() {
        let center = CGPoint(x: 1870, y: 540)
        XCTAssertEqual(EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen), .right)
    }

    func testNearestEdgeTop() {
        let center = CGPoint(x: 960, y: 1030)
        XCTAssertEqual(EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen), .top)
    }

    func testNearestEdgeBottom() {
        let center = CGPoint(x: 960, y: 50)
        XCTAssertEqual(EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen), .bottom)
    }

    func testCornerPicksCloserEdge() {
        // Close to the top-right corner, but slightly closer to the right side
        let center = CGPoint(x: 1910, y: 1060)
        let edge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        XCTAssertEqual(edge, .right)
    }

    func testCenterDefaultsToConsistentEdge() {
        let center = CGPoint(x: 960, y: 540)
        let edge = EdgeDetector.nearestEdge(panelCenter: center, screenFrame: screen)
        XCTAssertNotNil(edge)
    }
}
