import AppKit
import CoreMotion
import LookAwayCore

/// 包住 `CMHeadphoneMotionManager`，对外只吐「相对基准的偏航角」和连接状态。
///
/// 有一条硬性安全约束：只要姿态数据断流，就必须立刻通知上层撤掉遮罩。
/// 否则摘下 AirPods 的那一刻屏幕会永远糊着，用户没法自救。
final class HeadTracker: NSObject, CMHeadphoneMotionManagerDelegate {
    enum Status: Equatable {
        case unsupported            // 这台机器 / 这副耳机没有姿态传感器
        case denied                 // 用户拒绝了动作与体能训练权限
        case waitingForHeadphones   // 等 AirPods 连上
        case tracking
    }

    /// 每帧姿态：相对基准的偏航角（度）
    var onDeviation: ((Double) -> Void)?
    /// 数据断流。上层收到后必须无条件撤掉遮罩。
    var onSignalLost: (() -> Void)?
    var onStatusChange: ((Status) -> Void)?

    private(set) var status: Status = .waitingForHeadphones {
        didSet {
            guard oldValue != status else { return }
            onStatusChange?(status)
        }
    }

    /// 最近一次的原始 yaw，校准时要用
    private(set) var lastRawYaw: Double?

    /// 当前的「正前方」基准，诊断时用来确认零点有没有偏
    var currentBaseline: Double? { baseline.baseline }

    private let manager = CMHeadphoneMotionManager()
    private var baseline = BaselineTracker()
    private var watchdog: Timer?
    private var isRunning = false

    /// 多久没数据就认为断流
    private let signalTimeout: TimeInterval = 1.5

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard !isRunning else { return }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            status = .denied
            return
        default:
            break
        }

        isRunning = true
        baseline.reset()

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }

            if error != nil {
                self.handleSignalLoss()
                return
            }
            guard let motion else { return }
            self.handle(motion: motion)
        }

        // 起步时 AirPods 可能还没连上，这不算错误
        status = manager.isDeviceMotionActive ? .tracking : .waitingForHeadphones
    }

    func stop() {
        isRunning = false
        manager.stopDeviceMotionUpdates()
        cancelWatchdog()
        baseline.reset()
        lastRawYaw = nil
        status = .waitingForHeadphones
        onSignalLost?()
    }

    /// 用户此刻正对屏幕，把当前朝向定为基准
    func calibrate() {
        guard let yaw = lastRawYaw else { return }
        baseline.calibrate(yawDegrees: yaw, now: Date.timeIntervalSinceReferenceDate)
    }

    // MARK: - 姿态

    private func handle(motion: CMDeviceMotion) {
        let now = Date.timeIntervalSinceReferenceDate
        let yaw = Angle.degrees(fromRadians: motion.attitude.yaw)
        lastRawYaw = yaw
        status = .tracking

        let yawDeviation = baseline.update(yawDegrees: yaw, now: now)
        armWatchdog()
        onDeviation?(HeadOrientation.screenDeviation(fromYawDeviation: yawDeviation))
    }

    private func handleSignalLoss() {
        cancelWatchdog()
        baseline.reset()
        lastRawYaw = nil
        if isRunning {
            status = .waitingForHeadphones
        }
        onSignalLost?()
    }

    // MARK: - 看门狗

    private func armWatchdog() {
        cancelWatchdog()
        watchdog = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false) { [weak self] _ in
            self?.handleSignalLoss()
        }
    }

    private func cancelWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    // MARK: - CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        baseline.reset()
        status = .tracking
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        handleSignalLoss()
    }
}
