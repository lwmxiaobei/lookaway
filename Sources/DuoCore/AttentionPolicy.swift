import Foundation

/// 决定「该不该遮屏」的纯状态机。
///
/// 判定依据是视线有没有落在屏幕阵列张开的角度范围内。多屏横排时这个范围
/// 通常不对称（比如左边多一块屏），所以左右边界分开表达。
///
/// 只有两件事需要防：一是角度在边界上抖动导致遮罩闪烁（靠迟滞），
/// 二是快速扫一眼就触发（靠停留时间）。两者都在这里，不碰任何 UI。
public struct AttentionPolicy {
    public struct Configuration: Equatable, Sendable {
        /// 视野左边界（相对基准的角度，负值）
        public var leftBound: Double
        /// 视野右边界（相对基准的角度，正值）
        public var rightBound: Double
        /// 迟滞带宽：遮住后要回到边界内侧这么多度才撤
        public var hysteresis: Double
        /// 越界持续多久才真的遮
        public var engageDwell: TimeInterval
        /// 回到视野内持续多久才撤
        public var disengageDwell: TimeInterval

        public init(
            leftBound: Double = -30,
            rightBound: Double = 30,
            hysteresis: Double = 8,
            engageDwell: TimeInterval = 0.25,
            disengageDwell: TimeInterval = 0.15
        ) {
            self.leftBound = leftBound
            self.rightBound = rightBound
            self.hysteresis = hysteresis
            self.engageDwell = engageDwell
            self.disengageDwell = disengageDwell
        }

        /// 对称视野的便利写法
        public init(
            engageAngle: Double,
            hysteresis: Double = 8,
            engageDwell: TimeInterval = 0.25,
            disengageDwell: TimeInterval = 0.15
        ) {
            self.init(
                leftBound: -engageAngle,
                rightBound: engageAngle,
                hysteresis: hysteresis,
                engageDwell: engageDwell,
                disengageDwell: disengageDwell
            )
        }

        /// 撤销遮罩要求的内缩边界。视野窄到迟滞带会把它夹穿时，退化成中点。
        public var releaseBounds: (left: Double, right: Double) {
            let left = leftBound + hysteresis
            let right = rightBound - hysteresis
            guard left <= right else {
                let mid = (leftBound + rightBound) / 2
                return (mid, mid)
            }
            return (left, right)
        }

        public func contains(_ deviation: Double) -> Bool {
            deviation >= leftBound && deviation <= rightBound
        }

        public func containsWithHysteresis(_ deviation: Double) -> Bool {
            let bounds = releaseBounds
            return deviation >= bounds.left && deviation <= bounds.right
        }
    }

    public enum State: Equatable, Sendable {
        case clear      // 视线在屏幕上，不遮
        case obscured   // 转开了，遮
    }

    public private(set) var state: State = .clear
    public var configuration: Configuration

    /// 当前候选状态的起始时间；nil 表示没有待确认的翻转
    private var pendingSince: TimeInterval?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// 传感器断开 / 重新校准时清掉半途的判定
    public mutating func reset() {
        state = .clear
        pendingSince = nil
    }

    @discardableResult
    public mutating func update(deviation: Double, now: TimeInterval) -> State {
        switch state {
        case .clear:
            if configuration.contains(deviation) {
                pendingSince = nil
            } else {
                let since = pendingSince ?? now
                pendingSince = since
                if now - since >= configuration.engageDwell {
                    state = .obscured
                    pendingSince = nil
                }
            }

        case .obscured:
            if configuration.containsWithHysteresis(deviation) {
                let since = pendingSince ?? now
                pendingSince = since
                if now - since >= configuration.disengageDwell {
                    state = .clear
                    pendingSince = nil
                }
            } else {
                pendingSince = nil
            }
        }

        return state
    }
}
