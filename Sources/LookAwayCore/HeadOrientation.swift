import Foundation

public enum HeadOrientation {
    /// CoreMotion 的 attitude 是右手系，yaw 绕垂直轴逆时针为正——也就是
    /// **向左转头 yaw 增大**。而屏幕坐标系向右为正。两者方向相反，
    /// 必须在这里翻过来，否则左右边界会整个对调。
    public static func screenDeviation(fromYawDeviation yawDeviation: Double) -> Double {
        -yawDeviation
    }

    /// 人看侧面目标时眼球先转、头跟不到位，头部大约只贡献视线角度的七成。
    /// 直接拿屏幕张角当头部转动阈值会系统性偏大，导致该遮的时候不遮。
    public static let headContribution: Double = 0.7
}
