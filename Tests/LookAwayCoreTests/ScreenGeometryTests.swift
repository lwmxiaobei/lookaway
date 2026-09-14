import XCTest
@testable import LookAwayCore

final class ScreenGeometryTests: XCTestCase {
    private func display(
        minX: Double, width: Double, mm: Double, main: Bool = false
    ) -> ScreenGeometry.Display {
        .init(logicalMinX: minX, logicalWidth: width, physicalWidthMM: mm, isMain: main)
    }

    func testSingleScreenIsSymmetric() {
        let field = ScreenGeometry.horizontalField(
            displays: [display(minX: 0, width: 1512, mm: 300, main: true)],
            viewingDistanceMM: 600
        )
        // 半宽 150mm / 600mm -> atan = 14.04°
        XCTAssertEqual(field?.left ?? .nan, -14.04, accuracy: 0.05)
        XCTAssertEqual(field?.right ?? .nan, 14.04, accuracy: 0.05)
    }

    func testThreeScreensSpanWiderThanOne() {
        let displays = [
            display(minX: -1920, width: 1920, mm: 530),
            display(minX: 0, width: 1512, mm: 300, main: true),
            display(minX: 1512, width: 1920, mm: 530),
        ]
        let field = ScreenGeometry.horizontalField(displays: displays, viewingDistanceMM: 600)
        // 主屏中心到阵列左缘 = 150 + 530 = 680mm -> atan(680/600) = 48.6°
        XCTAssertEqual(field?.left ?? .nan, -48.57, accuracy: 0.1)
        XCTAssertEqual(field?.right ?? .nan, 48.57, accuracy: 0.1)
    }

    func testAsymmetricLayoutProducesAsymmetricField() {
        let displays = [
            display(minX: -1920, width: 1920, mm: 530),
            display(minX: 0, width: 1512, mm: 300, main: true),
        ]
        let field = ScreenGeometry.horizontalField(displays: displays, viewingDistanceMM: 600)
        XCTAssertEqual(field?.left ?? .nan, -48.57, accuracy: 0.1)
        XCTAssertEqual(field?.right ?? .nan, 14.04, accuracy: 0.05, "右边没有屏，边界就是主屏右缘")
    }

    func testCloserViewingDistanceWidensField() {
        let displays = [display(minX: 0, width: 1512, mm: 300, main: true)]
        let near = ScreenGeometry.horizontalField(displays: displays, viewingDistanceMM: 400)!
        let far = ScreenGeometry.horizontalField(displays: displays, viewingDistanceMM: 800)!
        XCTAssertGreaterThan(near.right, far.right)
    }

    func testMissingPhysicalSizeFallsBackToEstimate() {
        let field = ScreenGeometry.horizontalField(
            displays: [display(minX: 0, width: 1512, mm: 0, main: true)],
            viewingDistanceMM: 600
        )
        XCTAssertNotNil(field)
        XCTAssertEqual(field?.right ?? .nan, 18.1, accuracy: 1.0, "拿不到物理尺寸时也要给出合理角度")
    }

    func testNonMainAnchorDefaultsToLeftmost() {
        let displays = [
            display(minX: 0, width: 1512, mm: 300),
            display(minX: 1512, width: 1920, mm: 530),
        ]
        XCTAssertNotNil(ScreenGeometry.horizontalField(displays: displays, viewingDistanceMM: 600))
    }

    func testEmptyOrInvalidInput() {
        XCTAssertNil(ScreenGeometry.horizontalField(displays: [], viewingDistanceMM: 600))
        XCTAssertNil(ScreenGeometry.horizontalField(
            displays: [display(minX: 0, width: 1512, mm: 300, main: true)],
            viewingDistanceMM: 0
        ))
    }

    func testExpandedAddsMarginOnBothSides() {
        let field = ScreenGeometry.Field(left: -40, right: 20).expanded(by: 10)
        XCTAssertEqual(field.left, -50)
        XCTAssertEqual(field.right, 30)
    }
}
