import XCTest
@testable import LookAwayCore

final class BaselineTrackerTests: XCTestCase {
    func testFirstSampleBecomesBaseline() {
        var tracker = BaselineTracker()
        XCTAssertEqual(tracker.update(yawDegrees: 137, now: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(tracker.baseline ?? .nan, 137, accuracy: 1e-9)
    }

    func testCalibrateOverwritesBaseline() {
        var tracker = BaselineTracker()
        _ = tracker.update(yawDegrees: 0, now: 0)
        tracker.calibrate(yawDegrees: 20, now: 1)
        XCTAssertEqual(tracker.update(yawDegrees: 50, now: 2), 30, accuracy: 1e-9)
    }

    func testDeviationTakesShortestArcAcrossWrap() {
        var tracker = BaselineTracker()
        tracker.calibrate(yawDegrees: 170, now: 0)
        // 170° -> -170° 实际只转了 20°，不是 -340°
        XCTAssertEqual(tracker.update(yawDegrees: -170, now: 0.1), 20, accuracy: 1e-6)
    }

    func testBaselineFollowsSlowDriftWhenFacingScreen() {
        var tracker = BaselineTracker(configuration: .init(captureAngle: 10, timeConstant: 10))
        tracker.calibrate(yawDegrees: 0, now: 0)
        // 持续小幅偏 5°，基准应缓慢靠过去
        var now: TimeInterval = 0
        for _ in 0..<200 {
            now += 0.5
            _ = tracker.update(yawDegrees: 5, now: now)
        }
        XCTAssertEqual(tracker.baseline ?? .nan, 5, accuracy: 0.2)
    }

    func testBaselineIgnoresLargeTurns() {
        var tracker = BaselineTracker(configuration: .init(captureAngle: 10, timeConstant: 10))
        tracker.calibrate(yawDegrees: 0, now: 0)
        var now: TimeInterval = 0
        for _ in 0..<200 {
            now += 0.5
            _ = tracker.update(yawDegrees: 60, now: now)
        }
        XCTAssertEqual(tracker.baseline ?? .nan, 0, accuracy: 1e-9, "真转头时基准绝不能跟过去")
        XCTAssertEqual(tracker.update(yawDegrees: 60, now: now + 0.5), 60, accuracy: 1e-9)
    }

    func testResetForgetsBaseline() {
        var tracker = BaselineTracker()
        tracker.calibrate(yawDegrees: 90, now: 0)
        tracker.reset()
        XCTAssertNil(tracker.baseline)
        XCTAssertEqual(tracker.update(yawDegrees: 10, now: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(tracker.baseline ?? .nan, 10, accuracy: 1e-9)
    }
}
