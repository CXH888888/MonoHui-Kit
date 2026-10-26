import Foundation
import CoreGraphics

/// 圆环的几何计算。视图与命中判定共用同一套半径/角度定义，避免「看到的和选中的不一致」。
enum RadialMenuGeometry {
    /// 内圆半径（中心信息区）
    static let innerRadius: CGFloat = 96
    /// 外圆半径
    static let outerRadius: CGFloat = 212
    /// 中心死区：半径小于此值视为未选择（松手即取消）
    static let deadZone: CGFloat = 58
    /// 命中判定的外沿，比视觉外圈略大，避免贴边选不中
    static let hitOuter: CGFloat = 238
    /// 面板边长
    static let panelSize: CGFloat = 460

    /// 从正上方开始顺时针计角（0° = 上，90° = 右）
    static func sectorIndex(clockwiseDegrees degrees: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = 360.0 / Double(count)
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return Int((normalized + step / 2) / step) % count
    }

    /// 屏幕坐标（Cocoa，原点左下、y 向上）下的命中判定。
    /// - Returns: 扇区索引；在死区或圆环外返回 nil
    static func index(for point: CGPoint, center: CGPoint, count: Int) -> Int? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= deadZone, radius <= hitOuter else { return nil }

        // atan2 以 +x 为 0、逆时针为正；转换成「正上方为 0、顺时针为正」
        let angle = atan2(dy, dx) * 180 / .pi
        let clockwise = 90 - angle
        return sectorIndex(clockwiseDegrees: clockwise, count: count)
    }
}
