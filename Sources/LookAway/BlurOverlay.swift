import AppKit
import LookAwayCore

/// 一块屏幕上的一层遮罩窗口：鼠标穿透、盖在一切之上、只负责显示毛玻璃。
/// 同一块屏会摞好几层，靠层数把模糊半径叠上去。
private final class OverlayWindow: NSWindow {
    private let effectView = NSVisualEffectView()
    private let tintView = NSView()
    private let debugLabel = NSTextField(labelWithString: "")

    init(screen: NSScreen, layer: Int, debugIndex: Int? = nil) {
        // 用 designated initializer；contentRect 是全局坐标，
        // 给成目标屏幕的 frame 就落在那块屏上了。
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true           // 遮住时仍然能正常操作底下的窗口
        isReleasedWhenClosed = false
        // 刚好低于状态栏下拉菜单：盖得住菜单栏、Dock 和全屏 App，
        // 但遮罩生效时用户依然看得见、点得到我们自己的菜单去关掉它。
        // 同屏各层之间再按层号拉开，保证摞的顺序是确定的。
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 16 + layer)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        alphaValue = 0
        appearance = NSAppearance(named: .darkAqua)

        // behindWindow：模糊的是这扇窗背后的一切，包括下面几层已经模糊过的结果
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.material = .fullScreenUI
        effectView.autoresizingMask = [.width, .height]
        effectView.frame = screen.frame

        tintView.wantsLayer = true
        tintView.autoresizingMask = [.width, .height]
        tintView.frame = effectView.bounds
        effectView.addSubview(tintView)

        contentView = effectView

        if let debugIndex {
            applyDebugDecoration(index: debugIndex, screen: screen)
        }
    }

    /// LOOKAWAY_DEBUG_OVERLAY=1 时给每块屏涂上不同颜色并标注编号，
    /// 用来区分「窗口根本没到这块屏」和「窗口到了但毛玻璃没渲染」。
    private func applyDebugDecoration(index: Int, screen: NSScreen) {
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemOrange, .systemPurple]
        tintView.layer?.backgroundColor = colors[index % colors.count].withAlphaComponent(0.45).cgColor

        let name = screen.localizedName
        debugLabel.stringValue = "屏 \(index)  \(name)  \(Int(screen.frame.width))×\(Int(screen.frame.height))"
        debugLabel.font = .systemFont(ofSize: 64, weight: .bold)
        debugLabel.textColor = .white
        debugLabel.alignment = .center
        debugLabel.sizeToFit()
        debugLabel.frame.origin = NSPoint(
            x: (screen.frame.width - debugLabel.frame.width) / 2,
            y: (screen.frame.height - debugLabel.frame.height) / 2
        )
        debugLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        effectView.addSubview(debugLabel)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 压暗只加在最底层。均匀的黑被上面几层模糊之后还是均匀的黑，
    /// 效果一样，但省得去算「最上面那个可见层是哪个」。
    func applyTint(_ alpha: Double) {
        guard debugLabel.superview == nil else { return }   // 调试配色优先，别被强度设置盖掉
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
    }

    func reposition(to screen: NSScreen) {
        setFrame(screen.frame, display: false)
        effectView.frame = NSRect(origin: .zero, size: screen.frame.size)
    }
}

/// 管理所有屏幕上的遮罩，并跟着显示器插拔变化重建。
final class OverlayController {
    var intensity: BlurIntensity = .default {
        didSet {
            applyTint()
            guard isObscured else { return }
            // 正遮着的时候换档，让新的浓度自己滑过去，别硬跳
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                animateToObscured(true)
            }
        }
    }
    var fadeDuration: TimeInterval = 0.28

    /// 每块屏一摞窗口，stacks[屏][层]，层号越大摞得越上面。
    private var stacks: [[OverlayWindow]] = []
    private(set) var isObscured = false
    private let isDebugging = ProcessInfo.processInfo.environment["LOOKAWAY_DEBUG_OVERLAY"] == "1"

    private var allWindows: [OverlayWindow] { stacks.flatMap { $0 } }

    init() {
        rebuildWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setObscured(_ obscured: Bool, animated: Bool = true) {
        guard obscured != isObscured else { return }
        isObscured = obscured

        if obscured {
            // 从下往上依次上屏，保证摞的顺序跟层号一致
            stacks.forEach { $0.forEach { $0.orderFrontRegardless() } }
        }

        let duration = animated ? fadeDuration : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animateToObscured(obscured)
        } completionHandler: { [weak self] in
            guard let self, !self.isObscured else { return }
            // 收起来之后把窗口撤下，避免空转合成
            self.allWindows.forEach { $0.orderOut(nil) }
        }
    }

    /// 目标浓度按层分配：底层先满，再往上摞，所以强度调高是「多糊一层」而不是「更黑一点」。
    private func animateToObscured(_ obscured: Bool) {
        let alphas = intensity.layerAlphas
        for stack in stacks {
            for (layer, window) in stack.enumerated() {
                window.animator().alphaValue = obscured ? alphas[layer] : 0
            }
        }
    }

    private func applyTint() {
        stacks.forEach { $0.first?.applyTint(intensity.tintAlpha) }
    }

    @objc private func screensChanged() {
        rebuildWindows()
    }

    private func rebuildWindows() {
        let screens = NSScreen.screens

        // 屏幕变多就补一摞，变少就把多余的整摞关掉
        while stacks.count > screens.count {
            stacks.removeLast().forEach { $0.close() }
        }
        for (index, screen) in screens.enumerated() {
            if index < stacks.count {
                stacks[index].forEach { $0.reposition(to: screen) }
            } else {
                stacks.append((0..<BlurIntensity.maxLayers).map { layer in
                    OverlayWindow(
                        screen: screen,
                        layer: layer,
                        // 调试配色只画在最上面那层，不然几层颜色叠一块儿看不出东西
                        debugIndex: (isDebugging && layer == BlurIntensity.maxLayers - 1) ? index : nil
                    )
                })
            }
        }

        applyTint()
        let alphas = intensity.layerAlphas
        for stack in stacks {
            for (layer, window) in stack.enumerated() {
                window.alphaValue = isObscured ? alphas[layer] : 0
                if isObscured { window.orderFrontRegardless() }
            }
        }
    }
}
