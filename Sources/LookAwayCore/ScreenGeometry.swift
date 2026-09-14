import Foundation

/// 从显示器的物理尺寸和排列，推算整个屏幕阵列相对主屏中心张开的水平角度。
///
/// 逻辑坐标只能告诉我们屏幕的相邻关系，换算成角度必须走物理毫米：
/// 不同屏的 DPI 不一样，同样的逻辑宽度对应的实际宽度可能差一倍。
public enum ScreenGeometry {
    public struct Display: Equatable, Sendable {
        public var logicalMinX: Double
        public var logicalWidth: Double
        /// 物理宽度（毫米）。拿不到时传 0，会按典型 Retina 密度估算。
        public var physicalWidthMM: Double
        public var isMain: Bool

        public init(logicalMinX: Double, logicalWidth: Double, physicalWidthMM: Double, isMain: Bool) {
            self.logicalMinX = logicalMinX
            self.logicalWidth = logicalWidth
            self.physicalWidthMM = physicalWidthMM
            self.isMain = isMain
        }

        /// 某些虚拟显示器 / 采集卡报不出物理尺寸，用典型 Retina 密度兜底
        var effectiveWidthMM: Double {
            physicalWidthMM > 0 ? physicalWidthMM : logicalWidth * 0.26
        }
    }

    public struct Field: Equatable, Sendable {
        /// 阵列左边缘相对主屏中心的角度（负）
        public var left: Double
        /// 阵列右边缘相对主屏中心的角度（正）
        public var right: Double

        public init(left: Double, right: Double) {
            self.left = left
            self.right = right
        }

        public func expanded(by margin: Double) -> Field {
            Field(left: left - margin, right: right + margin)
        }

        /// 按头部对视线角度的贡献比例收窄。屏幕张角是视线角度，
        /// 而我们量的是头部转角，两者不等。
        public func scaled(by factor: Double) -> Field {
            Field(left: left * factor, right: right * factor)
        }
    }

    /// - Parameter viewingDistanceMM: 眼睛到主屏的距离
    /// - Returns: 阵列张角；没有屏幕或距离非法时返回 nil
    public static func horizontalField(displays: [Display], viewingDistanceMM: Double) -> Field? {
        guard !displays.isEmpty, viewingDistanceMM > 0 else { return nil }

        let ordered = displays.sorted { $0.logicalMinX < $1.logicalMinX }
        let mainIndex = ordered.firstIndex(where: \.isMain) ?? 0

        // 以主屏物理左缘为原点，按逻辑排列把各屏的物理宽度依次接起来。
        // 屏幕之间的逻辑空隙忽略不计——实际摆放里它们是挨着的。
        var leftEdges = [Double](repeating: 0, count: ordered.count)
        leftEdges[mainIndex] = 0

        var cursor = ordered[mainIndex].effectiveWidthMM
        for index in (mainIndex + 1)..<ordered.count {
            leftEdges[index] = cursor
            cursor += ordered[index].effectiveWidthMM
        }

        cursor = 0
        for index in stride(from: mainIndex - 1, through: 0, by: -1) {
            cursor -= ordered[index].effectiveWidthMM
            leftEdges[index] = cursor
        }

        let arrayLeft = leftEdges[0]
        let arrayRight = leftEdges[ordered.count - 1] + ordered[ordered.count - 1].effectiveWidthMM
        let mainCenter = ordered[mainIndex].effectiveWidthMM / 2

        return Field(
            left: Angle.degrees(fromRadians: atan((arrayLeft - mainCenter) / viewingDistanceMM)),
            right: Angle.degrees(fromRadians: atan((arrayRight - mainCenter) / viewingDistanceMM))
        )
    }
}
