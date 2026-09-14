import XCTest
@testable import DuoCore

final class HeadOrientationTests: XCTestCase {
    func testYawIsInvertedToScreenDirection() {
        // 向左转头 yaw 为正，对应屏幕左侧（负方向）
        XCTAssertEqual(HeadOrientation.screenDeviation(fromYawDeviation: 40), -40, accuracy: 1e-9)
        // 向右转头 yaw 为负，对应屏幕右侧（正方向）
        XCTAssertEqual(HeadOrientation.screenDeviation(fromYawDeviation: -64), 64, accuracy: 1e-9)
        XCTAssertEqual(HeadOrientation.screenDeviation(fromYawDeviation: 0), 0, accuracy: 1e-9)
    }

    func testHeadContributionShrinksThreshold() {
        // 屏幕右缘在视线 +60°，头大约只转到 +42°
        XCTAssertEqual(60 * HeadOrientation.headContribution, 42, accuracy: 1e-9)
    }
}
