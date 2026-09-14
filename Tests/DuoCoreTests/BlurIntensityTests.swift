import XCTest
@testable import DuoCore

final class BlurIntensityTests: XCTestCase {
    /// 总模糊当量：几层各自浓度加起来，粗略正比于最终的模糊半径
    private func depth(_ intensity: BlurIntensity) -> Double {
        intensity.layerAlphas.reduce(0, +)
    }

    func testScaleIsContinuousWithNoBigJumps() {
        // 原来 4 档之间跳得太生硬，用户要的那一档正好落在缝里
        let steps = BlurIntensity.steps
        for (a, b) in zip(steps, steps.dropFirst()) {
            let jump = depth(b) - depth(a)
            XCTAssertGreaterThan(jump, 0, "\(a.localizedName)→\(b.localizedName) 必须更糊")
            XCTAssertLessThan(jump, 0.5, "\(a.localizedName)→\(b.localizedName) 跳得太狠")
        }
    }

    func testTopOfScaleStacksEveryLayer() {
        // 90% 还能看清内容，就是因为上一版的叠加根本没生效，单层糊到头就那样
        XCTAssertEqual(depth(BlurIntensity(level: 1.0)), Double(BlurIntensity.maxLayers), accuracy: 0.001)
        XCTAssertGreaterThan(depth(BlurIntensity(level: 0.9)), 3.0, "高档位必须摞满三层以上才糊得动")
    }

    func testLowEndKeepsASingleLayerSoContentStaysReadable() {
        let alphas = BlurIntensity(level: 0.1).layerAlphas
        XCTAssertLessThan(alphas[0], 1, "最轻档要透出底下的清晰画面")
        XCTAssertEqual(alphas.dropFirst().max(), 0, "最轻档不该摞第二层")
    }

    func testLayerAlphasFillFromTheBottomUp() {
        // 底层先满再往上摞，强度调高才是「多糊一层」而不是「整体变淡」
        for intensity in BlurIntensity.steps {
            let alphas = intensity.layerAlphas
            XCTAssertEqual(alphas.count, BlurIntensity.maxLayers)
            for (lower, upper) in zip(alphas, alphas.dropFirst()) {
                XCTAssertGreaterThanOrEqual(lower, upper, "\(intensity.localizedName) 的层序反了")
            }
            for alpha in alphas {
                XCTAssertGreaterThanOrEqual(alpha, 0)
                XCTAssertLessThanOrEqual(alpha, 1)
            }
        }
    }

    func testStepsCoverTheWholeRange() {
        XCTAssertEqual(BlurIntensity.steps.count, 10)
        XCTAssertEqual(BlurIntensity.steps.first?.level, BlurIntensity.minLevel)
        XCTAssertEqual(BlurIntensity.steps.last?.level, BlurIntensity.maxLevel)
        XCTAssertEqual(BlurIntensity.steps.map(\.localizedName).first, "10%")
        XCTAssertEqual(BlurIntensity.steps.map(\.localizedName).last, "100%")
    }

    func testLevelIsClampedToUsableRange() {
        XCTAssertEqual(BlurIntensity(level: -5).level, BlurIntensity.minLevel)
        XCTAssertEqual(BlurIntensity(level: 99).level, BlurIntensity.maxLevel)
        // 没存过设置时 UserDefaults 给 0，不能因此变成「完全不遮」
        XCTAssertEqual(BlurIntensity(level: 0).level, BlurIntensity.minLevel)
    }

    func testTintStaysLightSoOutlinesSurvive() {
        // 压暗只降亮度不降可读性，还会把轮廓吃掉——这正是上一版「重」档的毛病
        for intensity in BlurIntensity.steps {
            XCTAssertLessThanOrEqual(intensity.tintAlpha, 0.12, "\(intensity.localizedName) 压得太黑，轮廓没了")
        }
        XCTAssertEqual(BlurIntensity(level: 0.7).tintAlpha, 0, "七成以下完全不压暗，轮廓要留着")
    }

    func testStoredLevelRoundTrips() {
        let suite = "duo.tests.blur"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.blurIntensity, BlurIntensity.default, "没设置过时要落在默认档")
        prefs.blurIntensity = BlurIntensity(level: 0.4)
        XCTAssertEqual(Preferences(defaults: defaults).blurIntensity.level, 0.4, accuracy: 0.001)
        defaults.removePersistentDomain(forName: suite)
    }
}
