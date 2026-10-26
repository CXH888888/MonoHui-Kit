import SwiftUI
import Observation

@MainActor
@Observable
final class RadialMenuModel {
    var actions: [RadialAction] = []
    var selection: Int?
    var isShown: Bool = false

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
    var gapDegrees: Double = 1.4

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
/// 这样 8 个扇区也不会出现文字挤压，环本身可以做得更小更薄。
struct RadialMenuView: View {
    let model: RadialMenuModel
    let metrics: RadialMenuMetrics
    var isPreview: Bool = false

    private var size: CGFloat { metrics.panelSize }
    private var iconSize: CGFloat { CGFloat(RadialMenuSettings.shared.iconSize) }
    private var titleSize: CGFloat { CGFloat(RadialMenuSettings.shared.textSize) }
    private var hintSize: CGFloat { max(9, titleSize - 3) }
    private var iconRadius: CGFloat { (metrics.innerRadius + metrics.outerRadius) / 2 + size * 0.022 }
    private var labelRadius: CGFloat { (metrics.innerRadius + metrics.outerRadius) / 2 - size * 0.062 }

    var body: some View {
        ZStack {
            ring
            center
        }
        .frame(width: size, height: size)
        .scaleEffect(model.isShown ? 1 : 0.8)
        .opacity(model.isShown ? 1 : 0)
        .rotationEffect(.degrees(model.isShown ? 0 : -5))
        .scaleEffect(model.selection == nil ? 1 : 0.982)
        .animation(isPreview ? nil : .spring(response: 0.32, dampingFraction: 0.76), value: model.isShown)
        .animation(.easeOut(duration: 0.13), value: model.selection)
    }

    private var ring: some View {
        ZStack {
            // 底衬：让扇区缝隙之间不是全透明，轮廓更完整
            Circle()
                .strokeBorder(Color.white.opacity(0.05),
                              lineWidth: metrics.outerRadius - metrics.innerRadius)
                .frame(width: metrics.outerRadius * 2,
                       height: metrics.outerRadius * 2)

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let isSelected = model.selection == index
                let shape = RadialSectorShape(index: index, count: model.actions.count,
                                              inner: metrics.innerRadius, outer: metrics.outerRadius)

                shape
                    .fill(isSelected
                          ? AnyShapeStyle(Color.appleBlue)
                          : AnyShapeStyle(.ultraThinMaterial))
                    .opacity(model.selection == nil || isSelected ? 1 : 0.5)
                    .animation(.easeOut(duration: 0.12), value: model.selection)

                sectorContent(index: index, action: action, isSelected: isSelected)
            }

            // 内外两道极细描边，统一环的轮廓
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                .frame(width: metrics.outerRadius * 2,
                       height: metrics.outerRadius * 2)
            Circle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                .frame(width: metrics.innerRadius * 2,
                       height: metrics.innerRadius * 2)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 7)
    }

    @ViewBuilder
    private func sectorContent(index: Int, action: RadialAction, isSelected: Bool) -> some View {
        let step = 360.0 / Double(max(1, model.actions.count))
        let midDegrees = -90 + (Double(index) + 0.5) * step
        let mid: Double = midDegrees * .pi / 180
        let midCos = CGFloat(cos(mid))
        let midSin = CGFloat(sin(mid))

        ZStack {
            Image(systemName: action.icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.appleSoft)
                .scaleEffect(isSelected ? 1.12 : 1)
                .position(
                    x: size / 2 + midCos * iconRadius,
                    y: size / 2 + midSin * iconRadius
                )

            if RadialMenuSettings.shared.showLabels {
                Text(action.displayName)
                    .font(.system(size: hintSize, weight: .regular))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.appleSoft.opacity(0.85))
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
                    .font(.system(size: titleSize, weight: .semibold))
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
