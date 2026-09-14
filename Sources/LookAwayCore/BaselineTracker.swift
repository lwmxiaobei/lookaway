import Foundation

/// 维护「正对屏幕」的偏航基准。
///
/// `CMHeadphoneMotionManager` 的 yaw 是相对于传感器启动姿态的，而且会随时间缓慢漂移，
/// 所以基准不能只靠一次校准定死：
///   1. 用户显式校准时直接把当前 yaw 设为基准；
///   2. 之后只在「判定为正对屏幕」的小角度区间内，让基准以一阶低通慢慢跟随，抵消漂移。
///      大角度（真的转头了）时绝不跟随，否则转头一会儿基准就跟过去、遮罩自己撤了。
public struct BaselineTracker {
    public struct Configuration: Equatable, Sendable {
        /// 只有偏离在这个角度内才允许基准跟随漂移
        public var captureAngle: Double
        /// 一阶低通时间常数（秒）。越大跟随越慢。
        public var timeConstant: TimeInterval

        public init(captureAngle: Double = 10, timeConstant: TimeInterval = 45) {
            self.captureAngle = captureAngle
            self.timeConstant = timeConstant
        }
    }

    public private(set) var baseline: Double?
    private var configuration: Configuration
    private var lastUpdate: TimeInterval?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func calibrate(yawDegrees: Double, now: TimeInterval) {
        baseline = Angle.wrapDegrees(yawDegrees)
        lastUpdate = now
    }

    /// 传感器断开后基准失效，下一帧重新认基准
    public mutating func reset() {
        baseline = nil
        lastUpdate = nil
    }

    /// 吃进一帧 yaw，返回相对基准的偏离角（度，(-180, 180]）
    public mutating func update(yawDegrees: Double, now: TimeInterval) -> Double {
        let yaw = Angle.wrapDegrees(yawDegrees)

        guard let current = baseline, let last = lastUpdate else {
            // 首帧：当前朝向就是基准，假定用户此刻正对屏幕
            baseline = yaw
            lastUpdate = now
            return 0
        }

        let deviation = Angle.shortestDelta(from: current, to: yaw)
        let dt = max(0, now - last)
        lastUpdate = now

        if abs(deviation) <= configuration.captureAngle, configuration.timeConstant > 0, dt > 0 {
            let alpha = 1 - exp(-dt / configuration.timeConstant)
            baseline = Angle.wrapDegrees(current + deviation * alpha)
        }

        return deviation
    }
}
