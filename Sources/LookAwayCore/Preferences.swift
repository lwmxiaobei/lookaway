import Foundation

/// 模糊强度是一条连续刻度，不是几个离散档位——
/// 原来 4 档之间跳得太生硬，中间那段「依稀看得见轮廓、认不出内容」恰好被跳过去了。
public struct BlurIntensity: Equatable, Sendable {
    /// 0.1...1.0。0.1 几乎看得清，1.0 只剩色块。
    public let level: Double

    public init(level: Double) {
        self.level = min(max(level, BlurIntensity.minLevel), BlurIntensity.maxLevel)
    }

    public static let minLevel = 0.1
    public static let maxLevel = 1.0

    /// 菜单里可选的刻度：10% 一格。
    public static let steps: [BlurIntensity] = stride(from: 0.1, through: 1.0, by: 0.1)
        .map { BlurIntensity(level: ($0 * 10).rounded() / 10) }

    public static let `default` = BlurIntensity(level: 0.6)

    public var localizedName: String { "\(Int((level * 100).rounded()))%" }

    /// 每块屏最多摞几层毛玻璃。
    public static let maxLayers = 4

    /// 摞几层、每层多浓。上一版想在一个窗口里叠第二层 NSVisualEffectView，
    /// 但 withinWindow 只模糊同窗口内的内容，而第一层的模糊是 WindowServer
    /// 在窗口背后合成的、不在图层里——等于对着空气模糊，所以怎么调都糊不动。
    /// 摞独立窗口才行：上层模糊的是下层已经模糊过的合成结果，半径才叠得起来。
    public var layerAlphas: [Double] {
        // 0.1 → 勉强一层，1.0 → 四层全满
        let depth = 0.6 + (level - BlurIntensity.minLevel)
            / (BlurIntensity.maxLevel - BlurIntensity.minLevel) * 3.4
        return (0..<BlurIntensity.maxLayers).map { i in
            min(max(depth - Double(i), 0), 1)
        }
    }

    /// 压暗的量。暗只降亮度不降可读性，还会把轮廓一起吃掉，
    /// 所以只在最高那几档轻轻加一点，封顶 0.12——原来封顶 0.3，屏幕直接黑成一块。
    public var tintAlpha: Double {
        guard level > 0.75 else { return 0 }
        return min((level - 0.75) / 0.25, 1) * 0.12
    }
}

/// UserDefaults 的一层薄封装，只管数值，不认识 AppKit。
public final class Preferences {
    private enum Key {
        static let enabled = "lookaway.enabled"
        static let marginAngle = "lookaway.marginAngle"
        static let viewingDistance = "lookaway.viewingDistanceCM"
        static let blurLevel = "lookaway.blurLevel"
        static let fadeDuration = "lookaway.fadeDuration"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.marginAngle: 12.0,
            Key.viewingDistance: 60.0,
            Key.blurLevel: BlurIntensity.default.level,
            Key.fadeDuration: 0.28,
        ])
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// 屏幕阵列边缘之外再放宽多少度才算「没在看屏幕」。
    /// 留这个余量是因为人看屏幕边缘时头未必转到位，眼球会先动。
    public var marginAngle: Double {
        get { defaults.double(forKey: Key.marginAngle) }
        set { defaults.set(newValue, forKey: Key.marginAngle) }
    }

    /// 眼睛到主屏的距离（厘米）。决定同样宽的屏幕张开多大角度。
    public var viewingDistanceCM: Double {
        get { defaults.double(forKey: Key.viewingDistance) }
        set { defaults.set(newValue, forKey: Key.viewingDistance) }
    }

    public var blurIntensity: BlurIntensity {
        get { BlurIntensity(level: defaults.double(forKey: Key.blurLevel)) }
        set { defaults.set(newValue.level, forKey: Key.blurLevel) }
    }

    public var fadeDuration: TimeInterval {
        get { defaults.double(forKey: Key.fadeDuration) }
        set { defaults.set(newValue, forKey: Key.fadeDuration) }
    }

    /// 把量出来的屏幕张角加上余量，变成判定用的配置。
    /// 量不到屏幕（不该发生）时退回一个对称的保守值。
    public func policyConfiguration(field: ScreenGeometry.Field?) -> AttentionPolicy.Configuration {
        guard let field else {
            return AttentionPolicy.Configuration(engageAngle: 30)
        }
        // 先按头眼贡献比例把视线角度换算成头部转角，再加余量
        let expanded = field
            .scaled(by: HeadOrientation.headContribution)
            .expanded(by: marginAngle)
        var config = AttentionPolicy.Configuration()
        config.leftBound = expanded.left
        config.rightBound = expanded.right
        return config
    }
}
