import AppKit

/// 校准用的倒计时提示，显示在主屏正中央。
///
/// 存在的理由：点菜单里的「校准」时，你的头是转向菜单栏的（主屏左上角），
/// 当场采样会把一个偏了三十几度的朝向当成正前方。让用户盯着屏幕正中的
/// 倒计时，采样时刻的头部朝向才真的是「正对屏幕」。
final class CalibrationHUD {
    private var window: NSWindow?
    private var timer: Timer?
    private let countdownLabel = NSTextField(labelWithString: "")

    /// 在主屏中央倒数 `seconds` 秒，结束时回调。重复调用会取消上一次。
    func run(seconds: Int, onComplete: @escaping () -> Void) {
        cancel()

        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else {
            onComplete()
            return
        }

        let size = NSSize(width: 300, height: 200)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        let panel = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 24
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "看着这里别动")
        title.font = .systemFont(ofSize: 17, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 40, width: size.width, height: 24)
        title.autoresizingMask = [.width]

        countdownLabel.font = .systemFont(ofSize: 84, weight: .thin)
        countdownLabel.textColor = .labelColor
        countdownLabel.alignment = .center
        countdownLabel.frame = NSRect(x: 0, y: 72, width: size.width, height: 100)
        countdownLabel.autoresizingMask = [.width]

        effect.addSubview(title)
        effect.addSubview(countdownLabel)
        panel.contentView = effect
        panel.orderFrontRegardless()
        window = panel

        var remaining = max(1, seconds)
        countdownLabel.stringValue = "\(remaining)"

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            remaining -= 1
            if remaining > 0 {
                self.countdownLabel.stringValue = "\(remaining)"
            } else {
                self.dismiss()
                onComplete()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        dismiss()
    }

    private func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }
}
