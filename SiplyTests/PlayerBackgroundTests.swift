import XCTest
@testable import Siply

final class PlayerBackgroundTests: XCTestCase {
    private let corners: [(Int, SIMD2<Float>)] = [(0, [0, 0]), (2, [1, 0]), (6, [0, 1]), (8, [1, 1])]

    func testCornersFixed() {
        for t in [0.0, 1.7, 9.3] {
            let p = PlayerBackground.points(at: t, amplitude: 0.14)
            XCTAssertEqual(p.count, 9)
            for (i, c) in corners { XCTAssertEqual(p[i], c, "t=\(t) i=\(i)") }
        }
    }

    func testEdgesStayOnEdges() {
        let p = PlayerBackground.points(at: 4.2, amplitude: 0.14)
        XCTAssertEqual(p[1].y, 0)   // верх
        XCTAssertEqual(p[7].y, 1)   // низ
        XCTAssertEqual(p[3].x, 0)   // лево
        XCTAssertEqual(p[5].x, 1)   // право
    }

    func testInUnitSquareAndMove() {
        let a = PlayerBackground.points(at: 0, amplitude: 0.14)
        let b = PlayerBackground.points(at: 3, amplitude: 0.14)
        for p in a + b {
            XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y), "\(p)")
        }
        XCTAssertNotEqual(a, b)
    }
}
