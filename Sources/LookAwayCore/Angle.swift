import Foundation

/// 角度工具：CoreMotion 给的是弧度且会在 ±π 处回绕，
/// 所有比较都必须走最短弧，否则头一转过 180° 判定就会整个翻掉。
public enum Angle {
    /// 把任意角度规整到 (-180, 180]
    public static func wrapDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }

    /// 从 `from` 到 `to` 的最短有向角差，结果落在 (-180, 180]
    public static func shortestDelta(from: Double, to: Double) -> Double {
        wrapDegrees(to - from)
    }

    public static func degrees(fromRadians radians: Double) -> Double {
        radians * 180 / .pi
    }
}
