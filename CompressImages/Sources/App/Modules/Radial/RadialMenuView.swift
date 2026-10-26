import SwiftUI
import Observation

@MainActor
@Observable
final class RadialMenuModel {
    var actions: [RadialAction] = []
    var selection: Int?
    var isShown: Bool = false

    /// 以下三项由控制器在每次唤出时从设置写入。
    /// 面板是复用的，不能依赖「单例被 Observation 追踪」来刷新——
    /// 之前扇区文字开关失灵就是这个原因。
    var showLabels: Bool = false
    var iconSize: CGFloat = 14
    var titleSize: CGFloat = 12

    var selectedAction: RadialAction? {
        guard let selection, selection >= 0, selection < actions.count else { return nil }
        return actions[selection]
    }
}

/// 单个扇区的环形路径。角度以正上方为 0°、顺时针递增。
struct RadialSectorShape: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat
    /// 扇区缝隙。0.6° 在 300pt 环上约 1.5pt，只留一道细线，不切断环的连续性
    var gapDegrees: Double = 0.6

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(max(1, count))
        let start = -90 + Double(index) * step + gapDegrees / 2
        let end = -90 + Double(index + 1) * step - gapDegrees / 2

        var path = Path()
        path.addArc(center: center, radius: outer,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: inner,
                    startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// 圆环菜单视图。
///
/// 排版参考 Loop / Pieoneer：**扇区只放图标，文字集中在中心**。
/// 结构自下而上：毛玻璃底座 → 扇区色块 → 图标/文字 → 内外细描边。
struct RadialMenuView: View {
    let model: RadialMenuModel
    let metrics: RadialMenuMetrics
    var isPreview: Bool = false

    private var size: CGFloat { metrics.panelSize }
    private var iconRadius: CGFloat { (metrics.innerRadius + metrics.outerRadius) / 2 + size * 0.022 }
    private var labelRadius: CGFloat { (metrics.innerRadius + metrics.outerRadius) / 2 - size * 0.062 }
    private var hintSize: CGFloat { max(9, model.titleSize - 3) }

    var body: some View {
        ZStack {
            backdrop
            ring
            center
        }
        .frame(width: size, height: size)
        .scaleEffect(model.isShown ? 1 : 0.8)
        .opacity(model.isShown ? 1 : 0)
        .rotationEffect(.degrees(model.isShown ? 0 : -5))
        .scaleEffect(model.selection == nil ? 1 : 0.985)
        .animation(isPreview ? nil : .spring(response: 0.32, dampingFraction: 0.76), value: model.isShown)
        .animation(.easeOut(duration: 0.13), value: model.selection)
    }

    /// 外圈毛玻璃底座：比扇区外沿再向外 8pt、向内 6pt，
    /// 让扇区缝隙露出的是磨砂底而不是桌面，环的轮廓更完整。
    private var backdrop: some View {
        let bandOuter = metrics.outerRadius + 4
        let bandInner = metrics.innerRadius - 2
        let diameter = bandOuter * 2

        return Circle()
            .strokeBorder(.ultraThinMaterial, lineWidth: bandOuter - bandInner)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    .frame(width: diameter, height: diameter)
            )
            .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
    }

    private var ring: some View {
        ZStack {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let isSelected = model.selection == index
                let shape = RadialSectorShape(index: index, count: model.actions.count,
                                              inner: metrics.innerRadius, outer: metrics.outerRadius)

                shape
                    .fill(isSelected
                          ? AnyShapeStyle(Color.appleBlue)
                          : AnyShapeStyle(Color.primary.opacity(0.045)))
                    .animation(.easeOut(duration: 0.12), value: model.selection)

                sectorContent(index: index, action: action, isSelected: isSelected)
            }

            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                .frame(width: metrics.outerRadius * 2,
                       height: metrics.outerRadius * 2)
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                .frame(width: metrics.innerRadius * 2,
                       height: metrics.innerRadius * 2)
        }
    }

    @ViewBuilder
    private func sectorContent(index: Int, action: RadialAction, isSelected: Bool) -> some View {
        let step = 360.0 / Double(max(1, model.actions.count))
        let midDegrees = -90 + (Double(index) + 0.5) * step
        let mid: Double = midDegrees * .pi / 180
        let midCos = CGFloat(cos(mid))
        let midSin = CGFloat(sin(mid))
        // 选中某个扇区时，其余图标只降一点亮度，不把整块底色变透明
        let idleOpacity: Double = model.selection == nil ? 1 : 0.55

        ZStack {
            Image(systemName: action.icon)
                .font(.system(size: model.iconSize, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.appleInk.opacity(0.75))
                .opacity(isSelected ? 1 : idleOpacity)
                .scaleEffect(isSelected ? 1.1 : 1)
                .position(
                    x: size / 2 + midCos * iconRadius,
                    y: size / 2 + midSin * iconRadius
                )

            if model.showLabels {
                Text(action.displayName)
                    .font(.system(size: hintSize, weight: .regular))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.appleSoft)
                    .opacity(isSelected ? 1 : idleOpacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 58)
                    .position(
                        x: size / 2 + midCos * labelRadius,
                        y: size / 2 + midSin * labelRadius
                    )
            }
        }
    }

    private var center: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle().stroke(
                        model.selection == nil ? Color.white.opacity(0.18) : Color.appleBlue.opacity(0.5),
                        lineWidth: 0.5
                    )
                )
                .frame(width: metrics.innerRadius * 2 - size * 0.05,
                       height: metrics.innerRadius * 2 - size * 0.05)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)

            VStack(spacing: 3) {
                Text(model.selectedAction?.displayName ?? (isPreview ? "圆环预览" : "移动选择"))
                    .font(.system(size: model.titleSize, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(model.selectedAction?.hint ?? (isPreview ? "\(model.actions.count) 个扇区" : "回到中心取消"))
                    .font(.system(size: hintSize, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: metrics.innerRadius * 2 - size * 0.106)
            .multilineTextAlignment(.center)
        }
    }
}
