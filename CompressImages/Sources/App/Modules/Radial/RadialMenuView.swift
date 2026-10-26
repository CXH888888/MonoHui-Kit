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
    var inner: CGFloat = RadialMenuGeometry.innerRadius
    var outer: CGFloat = RadialMenuGeometry.outerRadius
    var gapDegrees: Double = 2.4

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

struct RadialMenuView: View {
    let model: RadialMenuModel
    var isPreview: Bool = false

    private let size = RadialMenuGeometry.panelSize

    var body: some View {
        ZStack {
            ring
            center
        }
        .frame(width: size, height: size)
        .scaleEffect(model.isShown ? 1 : 0.74)
        .opacity(model.isShown ? 1 : 0)
        .rotationEffect(.degrees(model.isShown ? 0 : -7))
        .scaleEffect(model.selection == nil ? 1 : 0.965)
        .animation(isPreview ? nil : .spring(response: 0.34, dampingFraction: 0.74), value: model.isShown)
        .animation(.easeOut(duration: 0.14), value: model.selection)
    }

    private var ring: some View {
        ZStack {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let isSelected = model.selection == index
                let shape = RadialSectorShape(index: index, count: model.actions.count)

                shape
                    .fill(isSelected
                          ? AnyShapeStyle(Color.appleBlue)
                          : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        shape.stroke(
                            isSelected ? Color.white.opacity(0.35) : Color.white.opacity(0.14),
                            lineWidth: 0.5
                        )
                    )
                    .opacity(model.selection == nil || isSelected ? 1 : 0.55)
                    .animation(.easeOut(duration: 0.12), value: model.selection)

                sectorContent(index: index, action: action, isSelected: isSelected)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 26, y: 10)
    }

    @ViewBuilder
    private func sectorContent(index: Int, action: RadialAction, isSelected: Bool) -> some View {
        let step = 360.0 / Double(max(1, model.actions.count))
        let midDegrees = -90 + (Double(index) + 0.5) * step
        let mid: Double = midDegrees * .pi / 180
        // 先算成 CGFloat，避免 cos/sin 在 Double 与 CGFloat 重载之间歧义
        let midCos = CGFloat(cos(mid))
        let midSin = CGFloat(sin(mid))
        let iconRadius = (RadialMenuGeometry.innerRadius + RadialMenuGeometry.outerRadius) / 2 + 26
        let labelRadius = (RadialMenuGeometry.innerRadius + RadialMenuGeometry.outerRadius) / 2 - 26
        // 显式标注 Font 类型：三元表达式直接写在 .font(.system(...)) 里会让
        // Text.font 与 View.font 两个重载无法消歧
        let labelFont: Font = isSelected
            ? .system(size: 12, weight: .semibold)
            : .system(size: 12, weight: .regular)
        // 显式标注 Text：否则 Text.font 与 View.font 两个重载在 ViewBuilder 里无法消歧
        let labelText: Text = Text(action.displayName).font(labelFont)

        ZStack {
            Image(systemName: action.icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(isSelected ? Color.white : Color.appleInk)
                .position(
                    x: size / 2 + midCos * iconRadius,
                    y: size / 2 + midSin * iconRadius
                )

            if RadialMenuSettings.shared.showLabels {
                labelText
                    .foregroundStyle(isSelected ? Color.white : Color.appleInk)
                    .lineLimit(1)
                    .fixedSize()
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
                        model.selection == nil ? Color.white.opacity(0.16) : Color.appleBlue.opacity(0.55),
                        lineWidth: 1
                    )
                )
                .frame(width: RadialMenuGeometry.innerRadius * 2 - 18,
                       height: RadialMenuGeometry.innerRadius * 2 - 18)
                .shadow(color: .black.opacity(0.16), radius: 14, y: 4)

            VStack(spacing: 4) {
                Text(model.selectedAction?.displayName ?? (isPreview ? "圆环预览" : "移动选择"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                    .lineLimit(1)

                Text(model.selectedAction?.hint ?? (isPreview ? "\(model.actions.count) 个扇区" : "回到中心取消"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
            .frame(width: RadialMenuGeometry.innerRadius * 2 - 40)
            .multilineTextAlignment(.center)
        }
    }
}
