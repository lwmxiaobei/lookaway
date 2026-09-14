import XCTest
@testable import LookAwayCore

final class AngleTests: XCTestCase {
    func testWrapKeepsValuesInRange() {
        XCTAssertEqual(Angle.wrapDegrees(0), 0, accuracy: 1e-9)
        XCTAssertEqual(Angle.wrapDegrees(180), 180, accuracy: 1e-9)
        XCTAssertEqual(Angle.wrapDegrees(-180), 180, accuracy: 1e-9)
        XCTAssertEqual(Angle.wrapDegrees(190), -170, accuracy: 1e-9)
        XCTAssertEqual(Angle.wrapDegrees(-190), 170, accuracy: 1e-9)
        XCTAssertEqual(Angle.wrapDegrees(720 + 45), 45, accuracy: 1e-9)
    }

    func testShortestDelta() {
        XCTAssertEqual(Angle.shortestDelta(from: 10, to: 40), 30, accuracy: 1e-9)
        XCTAssertEqual(Angle.shortestDelta(from: 40, to: 10), -30, accuracy: 1e-9)
        XCTAssertEqual(Angle.shortestDelta(from: 179, to: -179), 2, accuracy: 1e-9)
    }

    func testRadianConversion() {
        XCTAssertEqual(Angle.degrees(fromRadians: .pi), 180, accuracy: 1e-9)
        XCTAssertEqual(Angle.degrees(fromRadians: -.pi / 2), -90, accuracy: 1e-9)
    }
}
