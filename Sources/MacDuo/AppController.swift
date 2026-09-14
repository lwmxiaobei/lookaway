import AppKit
import CoreMotion
import DuoCore
import ServiceManagement

/// 把追踪、判定、遮罩和菜单栏串起来。
final class AppController: NSObject, NSMenuDelegate {
    private let preferences = Preferences()
    private let tracker = HeadTracker()
    private let overlay = OverlayController()
    private var policy = AttentionPolicy()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var previewTimer: Timer?

    /// 当前屏幕阵列张开的角度范围，显示器变化时重算
    private var field: ScreenGeometry.Field?
    /// 最近一帧的偏离角，菜单里实时显示，方便校准和调参
    private var lastDeviation: Double?
    /// 菜单打开期间刷新状态行的定时器
    private var menuRefreshTimer: Timer?
    /// 诊断用的姿态轨迹，默认为 nil
    private let trace = TraceLogger()
    private let calibrationHUD = CalibrationHUD()

    override init() {
        super.init()

        overlay.intensity = preferences.blurIntensity
        overlay.fadeDuration = preferences.fadeDuration

        setUpStatusItem()
        wireTracker()
        recomputeField()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if preferences.isEnabled {
            tracker.start()
        }
        refreshStatusIcon()
        runSelfTestIfRequested()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// MACDUO_SELFTEST=1 启动时自动预览一次遮罩，用于无 AirPods 的情况下验证遮罩链路。
    private func runSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["MACDUO_SELFTEST"] == "1" else { return }
        let seconds = ProcessInfo.processInfo.environment["MACDUO_SELFTEST_SECONDS"].flatMap(Double.init) ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startPreview(duration: seconds)
        }
    }

    // MARK: - 视野

    /// 量一遍当前所有显示器，算出阵列张角并更新判定配置
    private func recomputeField() {
        let displays = NSScreen.screens.map { screen -> ScreenGeometry.Display in
            ScreenGeometry.Display(
                logicalMinX: screen.frame.minX,
                logicalWidth: screen.frame.width,
                physicalWidthMM: Self.physicalWidthMM(of: screen),
                isMain: Self.isPrimaryDisplay(screen)
            )
        }
        field = ScreenGeometry.horizontalField(
            displays: displays,
            viewingDistanceMM: preferences.viewingDistanceCM * 10
        )
        policy.configuration = preferences.policyConfiguration(field: field)
        trace?.note(String(
            format: "视野: %d 块屏, %+.1f° ~ %+.1f° (距离 %.0fcm, 余量 %.0f°)",
            displays.count, policy.configuration.leftBound, policy.configuration.rightBound,
            preferences.viewingDistanceCM, preferences.marginAngle
        ))
    }

    /// 主显示器是坐标原点所在的那块。不能用 `NSScreen.main`——
    /// 那返回的是当前有 key window 的屏，会跟着焦点乱跑，
    /// 导致视野以某块外接屏为中心算出严重不对称的边界。
    private static func isPrimaryDisplay(_ screen: NSScreen) -> Bool {
        screen.frame.origin == .zero
    }

    private static func physicalWidthMM(of screen: NSScreen) -> Double {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return 0 }
        return CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value)).width
    }

    @objc private func screensChanged() {
        recomputeField()
    }

    // MARK: - 串线

    private func wireTracker() {
        tracker.onDeviation = { [weak self] deviation in
            guard let self else { return }
            self.lastDeviation = deviation
            guard self.previewTimer == nil else { return }
            let previous = self.policy.state
            let state = self.policy.update(deviation: deviation, now: Date.timeIntervalSinceReferenceDate)
            self.trace?.record(
                rawYaw: self.tracker.lastRawYaw,
                baseline: self.tracker.currentBaseline,
                deviation: deviation,
                leftBound: self.policy.configuration.leftBound,
                rightBound: self.policy.configuration.rightBound,
                state: state == .obscured ? "OBSCURED" : "clear",
                force: previous != state
            )
            self.overlay.setObscured(state == .obscured)
            self.refreshStatusIcon()
        }

        // 姿态断流（AirPods 摘下 / 断开 / 出错）时无条件放开屏幕
        tracker.onSignalLost = { [weak self] in
            guard let self else { return }
            self.lastDeviation = nil
            guard self.previewTimer == nil else { return }
            self.policy.reset()
            self.overlay.setObscured(false)
            self.refreshStatusIcon()
        }

        tracker.onStatusChange = { [weak self] _ in
            self?.refreshStatusIcon()
        }
    }

    // MARK: - 菜单栏

    private func setUpStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func refreshStatusIcon() {
        let symbol: String
        let description: String

        if !preferences.isEnabled {
            symbol = "eye.slash.circle"
            description = "已暂停"
        } else if overlay.isObscured {
            symbol = "eye.slash.fill"
            description = "屏幕已遮蔽"
        } else {
            switch tracker.status {
            case .tracking:
                symbol = "eye.fill"
                description = "正在追踪"
            case .waitingForHeadphones:
                symbol = "eye.trianglebadge.exclamationmark"
                description = "等待 AirPods"
            case .denied, .unsupported:
                symbol = "exclamationmark.triangle"
                description = "不可用"
            }
        }

        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        statusItem.button?.image?.isTemplate = true
    }

    private var statusLine: String {
        guard preferences.isEnabled else { return "已暂停" }
        switch tracker.status {
        case .tracking:
            let angle = lastDeviation.map { String(format: "偏离 %+.0f°", $0) } ?? "偏离 —"
            return overlay.isObscured ? "已遮蔽 · \(angle)" : "正在追踪 · \(angle)"
        case .waitingForHeadphones:
            return "等待 AirPods 连接"
        case .denied:
            return "缺少「动作与体能训练」权限"
        case .unsupported:
            return "这副耳机不支持头部追踪"
        }
    }

    private var fieldLine: String {
        let config = policy.configuration
        let screens = NSScreen.screens.count
        return String(
            format: "%d 块屏 · 视野 %+.0f° ~ %+.0f°",
            screens, config.leftBound, config.rightBound
        )
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // 菜单开着的时候实时刷新角度，转着头就能读出数值来调参
        menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak menu] _ in
            guard let self, let menu, menu.numberOfItems > 1 else { return }
            menu.item(at: 0)?.title = self.statusLine
            menu.item(at: 1)?.title = self.fieldLine
        }
        RunLoop.main.add(menuRefreshTimer!, forMode: .common)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let fieldItem = NSMenuItem(title: fieldLine, action: nil, keyEquivalent: "")
        fieldItem.isEnabled = false
        menu.addItem(fieldItem)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: preferences.isEnabled ? "暂停遮蔽" : "启用遮蔽",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let calibrate = NSMenuItem(title: "校准正前方（倒数 3 秒）", action: #selector(calibrate), keyEquivalent: "")
        calibrate.target = self
        calibrate.isEnabled = tracker.status == .tracking
        menu.addItem(calibrate)

        let preview = NSMenuItem(title: "预览遮蔽效果（3 秒）", action: #selector(previewOverlay), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)

        menu.addItem(.separator())

        let distanceItem = NSMenuItem(title: "观看距离", action: nil, keyEquivalent: "")
        let distanceMenu = NSMenu()
        for distance in [40.0, 50.0, 60.0, 70.0, 80.0] {
            let item = NSMenuItem(title: "\(Int(distance)) cm", action: #selector(setDistance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = distance
            item.state = abs(preferences.viewingDistanceCM - distance) < 0.01 ? .on : .off
            distanceMenu.addItem(item)
        }
        distanceItem.submenu = distanceMenu
        menu.addItem(distanceItem)

        let marginItem = NSMenuItem(title: "边缘余量", action: nil, keyEquivalent: "")
        let marginMenu = NSMenu()
        for margin in [0.0, 6.0, 12.0, 20.0] {
            let item = NSMenuItem(title: "\(Int(margin))°", action: #selector(setMargin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = margin
            item.state = abs(preferences.marginAngle - margin) < 0.01 ? .on : .off
            marginMenu.addItem(item)
        }
        marginItem.submenu = marginMenu
        menu.addItem(marginItem)

        let blurItem = NSMenuItem(title: "模糊强度", action: nil, keyEquivalent: "")
        let blurMenu = NSMenu()
        let currentLevel = preferences.blurIntensity.level
        for intensity in BlurIntensity.steps {
            let item = NSMenuItem(title: intensity.localizedName, action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = intensity.level
            item.state = abs(currentLevel - intensity.level) < 0.01 ? .on : .off
            blurMenu.addItem(item)
        }
        blurItem.submenu = blurMenu
        menu.addItem(blurItem)

        let login = NSMenuItem(title: "开机时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 mac-duo", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - 菜单动作

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
        if preferences.isEnabled {
            policy.reset()
            tracker.start()
        } else {
            tracker.stop()
            policy.reset()
            overlay.setObscured(false)
        }
        refreshStatusIcon()
    }

    @objc private func calibrate() {
        // 不能立刻采样：此刻用户的头还转向菜单栏。倒计时把他的视线引回屏幕正中。
        overlay.setObscured(false, animated: false)
        calibrationHUD.run(seconds: 3) { [weak self] in
            guard let self else { return }
            self.trace?.note("校准: 把当前朝向 \(self.tracker.lastRawYaw.map { String(format: "%.1f°", $0) } ?? "未知") 设为零点")
            self.tracker.calibrate()
            self.policy.reset()
            self.overlay.setObscured(false)
            self.refreshStatusIcon()
            NSSound.beep()
        }
    }

    @objc private func previewOverlay() {
        startPreview(duration: 3)
    }

    /// 预览期间用 previewTimer 门控住追踪回调，免得姿态更新把预览打断
    private func startPreview(duration: TimeInterval) {
        previewTimer?.invalidate()
        overlay.setObscured(true)
        previewTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.previewTimer = nil
            self.policy.reset()
            self.overlay.setObscured(false)
            self.refreshStatusIcon()
        }
        refreshStatusIcon()
    }

    @objc private func setDistance(_ sender: NSMenuItem) {
        guard let distance = sender.representedObject as? Double else { return }
        preferences.viewingDistanceCM = distance
        recomputeField()
    }

    @objc private func setMargin(_ sender: NSMenuItem) {
        guard let margin = sender.representedObject as? Double else { return }
        preferences.marginAngle = margin
        policy.configuration = preferences.policyConfiguration(field: field)
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        let intensity = BlurIntensity(level: level)
        preferences.blurIntensity = intensity
        overlay.intensity = intensity
        // 换档时顺手预览一下，不然看不见自己刚调的是什么效果
        startPreview(duration: 2)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机启动项"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        tracker.stop()
        overlay.setObscured(false, animated: false)
        NSApp.terminate(nil)
    }
}
