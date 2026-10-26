import Foundation
import CoreGraphics

/// 圆环的几何参数。所有半径由面板边长按比例推导，
/// 这样「小 / 中 / 大」三档只改一个数字，视图与命中判定始终一致。
struct RadialMenuMetrics {
    let panelSize: CGFloat

    var innerRadius: CGFloat { (panelSize * 0.194).rounded() }
    var outerRadius: CGFloat { (panelSize * 0.444).rounded() }
    /// 中心死区：半径小于此值视为未选择（松手即取消）
    var deadZone: CGFloat { (panelSize * 0.13).rounded() }
    /// 命中判定的外沿，比视觉外圈略大，避免贴边选不中
    var hitOuter: CGFloat { (panelSize * 0.49).rounded() }

    static func current() -> RadialMenuMetrics {
        RadialMenuMetrics(panelSize: CGFloat(RadialMenuSettings.shared.menuSize))
    }
}

enum RadialMenuGeometry {
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
    static func index(for point: CGPoint, center: CGPoint, count: Int,
                      metrics: RadialMenuMetrics) -> Int? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= metrics.deadZone, radius <= metrics.hitOuter else { return nil }

        // atan2 以 +x 为 0、逆时针为正；转换成「正上方为 0、顺时针为正」
        let angle = atan2(dy, dx) * 180 / .pi
        let clockwise = 90 - angle
        return sectorIndex(clockwiseDegrees: clockwise, count: count)
    }
}
