import XCTest
@testable import DuoCore

final class AttentionPolicyTests: XCTestCase {
    private func makePolicy(
        engage: Double = 30,
        hysteresis: Double = 8,
        engageDwell: TimeInterval = 0.25,
        disengageDwell: TimeInterval = 0.15
    ) -> AttentionPolicy {
        AttentionPolicy(configuration: .init(
            engageAngle: engage,
            hysteresis: hysteresis,
            engageDwell: engageDwell,
            disengageDwell: disengageDwell
        ))
    }

    func testStartsClear() {
        let policy = makePolicy()
        XCTAssertEqual(policy.state, .clear)
    }

    func testStaysClearBelowThreshold() {
        var policy = makePolicy()
        XCTAssertEqual(policy.update(deviation: 29.9, now: 0), .clear)
        XCTAssertEqual(policy.update(deviation: -29.9, now: 10), .clear)
    }

    func testCrossingThresholdNeedsDwellBeforeObscuring() {
        var policy = makePolicy()
        XCTAssertEqual(policy.update(deviation: 35, now: 0), .clear, "刚越界不该立刻遮")
        XCTAssertEqual(policy.update(deviation: 35, now: 0.24), .clear)
        XCTAssertEqual(policy.update(deviation: 35, now: 0.25), .obscured)
    }

    func testTriggersOnEitherDirection() {
        var policy = makePolicy()
        _ = policy.update(deviation: -40, now: 0)
        XCTAssertEqual(policy.update(deviation: -40, now: 1), .obscured, "向左转头同样要遮")
    }

    func testGlanceShorterThanDwellNeverObscures() {
        var policy = makePolicy()
        _ = policy.update(deviation: 45, now: 0)
        _ = policy.update(deviation: 45, now: 0.1)
        XCTAssertEqual(policy.update(deviation: 5, now: 0.2), .clear)
        // 回正后重新越界，计时要从头算
        _ = policy.update(deviation: 45, now: 0.3)
        XCTAssertEqual(policy.update(deviation: 45, now: 0.5), .clear)
        XCTAssertEqual(policy.update(deviation: 45, now: 0.55), .obscured)
    }

    func testHysteresisKeepsObscuredInsideDeadband() {
        var policy = makePolicy()
        _ = policy.update(deviation: 35, now: 0)
        XCTAssertEqual(policy.update(deviation: 35, now: 1), .obscured)

        // 掉回 25°：低于 engage(30) 但仍高于 release(22)，必须保持遮住
        XCTAssertEqual(policy.update(deviation: 25, now: 2), .obscured)
        XCTAssertEqual(policy.update(deviation: 25, now: 5), .obscured)
    }

    func testReleasesBelowHysteresisAfterDwell() {
        var policy = makePolicy()
        _ = policy.update(deviation: 35, now: 0)
        XCTAssertEqual(policy.update(deviation: 35, now: 1), .obscured)

        XCTAssertEqual(policy.update(deviation: 20, now: 2), .obscured, "刚回正不该立刻撤")
        XCTAssertEqual(policy.update(deviation: 20, now: 2.14), .obscured)
        XCTAssertEqual(policy.update(deviation: 20, now: 2.2), .clear)
    }

    func testBoundaryJitterDoesNotFlicker() {
        var policy = makePolicy()
        _ = policy.update(deviation: 35, now: 0)
        XCTAssertEqual(policy.update(deviation: 35, now: 1), .obscured)

        // 在 engage 阈值附近来回抖 2 秒，迟滞带应该把状态焊死
        var now: TimeInterval = 1
        for step in 0..<40 {
            now += 0.05
            let deviation = step.isMultiple(of: 2) ? 31.0 : 28.0
            XCTAssertEqual(policy.update(deviation: deviation, now: now), .obscured)
        }
    }

    func testResetReturnsToClear() {
        var policy = makePolicy()
        _ = policy.update(deviation: 40, now: 0)
        XCTAssertEqual(policy.update(deviation: 40, now: 1), .obscured)
        policy.reset()
        XCTAssertEqual(policy.state, .clear)
    }

    func testOverwideHysteresisCollapsesReleaseBandToMidpoint() {
        // 迟滞带比视野还宽时，撤销条件退化成「正对中点」，而不是变成空区间卡死
        let config = AttentionPolicy.Configuration(leftBound: -5, rightBound: 5, hysteresis: 50)
        let bounds = config.releaseBounds
        XCTAssertEqual(bounds.left, 0, accuracy: 1e-9)
        XCTAssertEqual(bounds.right, 0, accuracy: 1e-9)
        XCTAssertTrue(config.containsWithHysteresis(0))
        XCTAssertFalse(config.containsWithHysteresis(1))
    }

    func testAsymmetricFieldTriggersOnCorrectSide() {
        // 左边多一块屏：向左转 40° 仍在视野内，向右转 40° 已经出界
        var policy = AttentionPolicy(configuration: .init(leftBound: -55, rightBound: 20))
        _ = policy.update(deviation: -40, now: 0)
        XCTAssertEqual(policy.update(deviation: -40, now: 1), .clear)

        _ = policy.update(deviation: 40, now: 2)
        XCTAssertEqual(policy.update(deviation: 40, now: 3), .obscured)
    }

    func testStaysClearAcrossTheWholeArray() {
        // 视线从最左屏扫到最右屏，全程不该触发
        var policy = AttentionPolicy(configuration: .init(leftBound: -48, rightBound: 48))
        var now: TimeInterval = 0
        for deviation in stride(from: -45.0, through: 45.0, by: 5.0) {
            now += 0.3
            XCTAssertEqual(policy.update(deviation: deviation, now: now), .clear,
                           "偏离 \(deviation)° 仍落在屏幕上")
        }
    }
}
