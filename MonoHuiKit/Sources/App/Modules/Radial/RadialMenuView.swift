import SwiftUI
import Observation

@MainActor
@Observable
final class RadialMenuModel {
    var actions: [RadialAction] = []
    var selection: Int?
    var isShown: Bool = false

    /// 由控制器在每次唤出时从设置写入。
    /// 面板是复用的，不能依赖「单例被 Observation 追踪」来刷新。
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

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(max(1, count))
        let start = -90 + Double(index) * step
        let end = -90 + Double(index + 1) * step

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
/// 结构自下而上：毛玻璃底座 → 扇区高亮 → 分隔细线 → 图标 → 中心信息。
/// 扇区默认完全透明，只有选中时才填蓝；分隔靠 0.5px 细线，环保持连续。
struct RadialMenuView: View {
    let model: RadialMenuModel
    let metrics: RadialMenuMetrics
    var isPreview: Bool = false

    private var size: CGFloat { metrics.panelSize }
    /// 图标严格落在环带正中
    private var iconRadius: CGFloat { (metrics.innerRadius + metrics.outerRadius) / 2 }
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

    // MARK: - 毛玻璃底座

    /// 外圈毛玻璃底座：比扇区外沿向外 4pt、内沿向内 2pt。
    /// 用 0.8 不透明度的材质 + 斜向渐变光泽，让壁纸透上来，避免看起来像一块实心灰盘。
    private var backdrop: some View {
        let bandOuter = metrics.outerRadius + 4
        let bandInner = metrics.innerRadius - 2
        let diameter = bandOuter * 2
        let lineWidth = bandOuter - bandInner

        return ZStack {
            Circle()
                .strokeBorder(.ultraThinMaterial, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
                .opacity(0.8)

            // 玻璃光泽：左上偏亮、右下偏暗，形成一层很薄的渐变
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                .frame(width: diameter, height: diameter)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    // MARK: - 扇区

    private var ring: some View {
        ZStack {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let isSelected = model.selection == index
                let shape = RadialSectorShape(index: index, count: model.actions.count,
                                              inner: metrics.innerRadius, outer: metrics.outerRadius)

                shape
                    .fill(isSelected ? AnyShapeStyle(Color.appleBlue) : AnyShapeStyle(Color.clear))
                    .animation(.easeOut(duration: 0.12), value: model.selection)

                iconContent(index: index, action: action, isSelected: isSelected)
            }

            sectorDividers

            Circle()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                .frame(width: metrics.outerRadius * 2,
                       height: metrics.outerRadius * 2)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                .frame(width: metrics.innerRadius * 2,
                       height: metrics.innerRadius * 2)
        }
    }

    /// 扇区分隔线：比留缝更精致，环仍然是完整的一圈玻璃
    private var sectorDividers: some View {
        let count = max(1, model.actions.count)
        let step = 360.0 / Double(count)

        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                Path { path in
                    let angle = (-90 + Double(index) * step) * .pi / 180
                    let dx = CGFloat(cos(angle))
                    let dy = CGFloat(sin(angle))
                    path.move(to: CGPoint(x: size / 2 + dx * metrics.innerRadius,
                                          y: size / 2 + dy * metrics.innerRadius))
                    path.addLine(to: CGPoint(x: size / 2 + dx * metrics.outerRadius,
                                             y: size / 2 + dy * metrics.outerRadius))
                }
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private func iconContent(index: Int, action: RadialAction, isSelected: Bool) -> some View {
        let step = 360.0 / Double(max(1, model.actions.count))
        let midDegrees = -90 + (Double(index) + 0.5) * step
        let mid: Double = midDegrees * .pi / 180
        let midCos = CGFloat(cos(mid))
        let midSin = CGFloat(sin(mid))
        let idleOpacity: Double = model.selection == nil ? 1 : 0.55

        Image(systemName: action.icon)
            .font(.system(size: model.iconSize, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : Color.appleInk.opacity(0.78))
            .opacity(isSelected ? 1 : idleOpacity)
            .scaleEffect(isSelected ? 1.1 : 1)
            .position(
                x: size / 2 + midCos * iconRadius,
                y: size / 2 + midSin * iconRadius
            )
    }

    // MARK: - 中心

    private var center: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
                .overlay(
                    Circle().stroke(
                        model.selection == nil ? Color.white.opacity(0.16) : Color.appleBlue.opacity(0.5),
                        lineWidth: 0.5
                    )
                )
                .frame(width: metrics.innerRadius * 2 - size * 0.05,
                       height: metrics.innerRadius * 2 - size * 0.05)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 3)

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
