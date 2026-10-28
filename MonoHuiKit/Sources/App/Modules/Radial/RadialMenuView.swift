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
        let step = RadialMenuGeometry.step(count: count)
        // 扇区 i 的中线正对 i*step（SwiftUI 角度即 i*step - 90），起始边各退半格，
        // 与 RadialMenuGeometry.sectorIndex 的判定范围严格对齐
        let start = -90 + (Double(index) - 0.5) * step
        let end = -90 + (Double(index) + 0.5) * step

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
        // 不再整体缩放/旋转：毛玻璃底座是独立的 AppKit 视图，不跟着 SwiftUI 变换，
        // 整体缩放会让内容在固定的玻璃盘上滑动。展开动效交给各扇区自己播放。
        .opacity(model.isShown ? 1 : 0)
        .scaleEffect(model.isShown ? 1 : 0.96)
        .animation(isPreview ? nil : (model.isShown ? Motion.enter : Motion.leave),
                   value: model.isShown)
        .animation(Motion.easeInstant, value: model.selection)
    }

    // MARK: - 毛玻璃底座

    /// 整块底座的装饰层：直径比扇区外沿大 6pt，整圆盘连内部一起铺满，环心不再留空。
    ///
    /// 正式面板的背景模糊由 AppKit 的 `NSVisualEffectView` 承担（见 `RadialMenuController`），
    /// SwiftUI 的 `.ultraThinMaterial` 在透明 + `screenSaver` 层级的 NSPanel 里拿不到
    /// 窗口背后的采样，只会渲染成半透明灰，所以这里不再叠材质，只补光泽与描边。
    /// 设置页预览没有那层 AppKit 背景，退回用 SwiftUI 材质兜底。
    private var backdrop: some View {
        let diameter = metrics.backdropRadius * 2

        return ZStack {
            if isPreview {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: diameter, height: diameter)
            }

            // 压暗底层：让扇区层（80% 不透明）与底座拉开明度差，边界一眼能看出来
            Circle()
                .fill(Color.black.opacity(0.32))
                .frame(width: diameter, height: diameter)

            // 玻璃光泽：左上偏亮、右下偏暗，给整块底一点体积
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.07),
                            Color.white.opacity(0.01),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                .frame(width: diameter, height: diameter)
        }
    }

    // MARK: - 扇区

    /// 扇区填充：选中是蓝色渐变，未选中是极淡的玻璃薄片。
    /// 未选中必须给一点实体填充，否则 `Color.clear` 投不出阴影，薄片就浮不起来。
    private func sectorFill(isSelected: Bool) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.appleBlueHover, Color.appleBlue],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.08))
    }

    /// 依次展开：从正上方向两侧对称铺开（先上，再右上/左上，再右/左…），最后收在正下方。
    /// 纯顺时针排队会让末尾停在左上，看起来像绕了一圈没闭合。
    /// 错峰步长取规范 `stagger.item`（35ms），并封顶 240ms；退场用统一的 exit 曲线。
    private func revealAnimation(index: Int) -> Animation? {
        guard model.isShown else { return Motion.leave }
        let count = max(1, model.actions.count)
        let distance = min(index, count - index)
        guard let base = Motion.snappy else { return nil }
        return base.delay(Motion.Stagger.delay(distance))
    }

    private var ring: some View {
        ZStack {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let isSelected = model.selection == index
                let shape = RadialSectorShape(index: index, count: model.actions.count,
                                              inner: metrics.innerRadius, outer: metrics.outerRadius)

                shape
                    .fill(sectorFill(isSelected: isSelected))
                    // 扇区是压在毛玻璃上的第二层：80% 不透明，留 20% 透出底下的背景模糊
                    .opacity(0.8)
                    // 选中时抬起得更明显；未选中靠极淡的投影把薄片从底座上托起来
                    .shadow(color: .black.opacity(isSelected ? 0.32 : 0.14),
                            radius: isSelected ? 8 : 3,
                            y: isSelected ? 4 : 2)
                    .scaleEffect(model.isShown ? 1 : 0.88)
                    .opacity(model.isShown ? 1 : 0)
                    .animation(revealAnimation(index: index), value: model.isShown)
                    .animation(Motion.easeInstant, value: model.selection)

                iconContent(index: index, action: action, isSelected: isSelected)
                    .scaleEffect(model.isShown ? 1 : 0.7)
                    .opacity(model.isShown ? 1 : 0)
                    .animation(revealAnimation(index: index), value: model.isShown)
            }

            sectorDividers
                .scaleEffect(model.isShown ? 1 : 0.9)
                .opacity(model.isShown ? 1 : 0)
                .animation(ringReveal, value: model.isShown)

            // 环带内外描边：必须和扇区一起缩放淡入。
            // 之前只有扇区有入场动画，这两圈线一唤出就是全尺寸，看起来像「先画了个框再填内容」。
            Circle()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                .frame(width: metrics.outerRadius * 2,
                       height: metrics.outerRadius * 2)
                .scaleEffect(model.isShown ? 1 : 0.9)
                .opacity(model.isShown ? 1 : 0)
                .animation(ringReveal, value: model.isShown)

            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                .frame(width: metrics.innerRadius * 2,
                       height: metrics.innerRadius * 2)
                .scaleEffect(model.isShown ? 1 : 0.9)
                .opacity(model.isShown ? 1 : 0)
                .animation(ringReveal, value: model.isShown)
        }
    }

    /// 环带描边与分隔线的入场/退场曲线，跟扇区同一节奏但不排队
    private var ringReveal: Animation? {
        model.isShown ? Motion.enter : Motion.leave
    }

    /// 扇区分隔线：比留缝更精致，环仍然是完整的一圈玻璃
    private var sectorDividers: some View {
        let count: Int = max(1, model.actions.count)
        let step: Double = RadialMenuGeometry.step(count: count)
        let centerPoint: CGFloat = size / 2

        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                Path { path in
                    let boundary: Double = -90.0 + (Double(index) - 0.5) * step
                    let angle: Double = boundary * Double.pi / 180.0
                    let dx: CGFloat = CGFloat(cos(angle))
                    let dy: CGFloat = CGFloat(sin(angle))
                    path.move(to: CGPoint(x: centerPoint + dx * metrics.innerRadius,
                                          y: centerPoint + dy * metrics.innerRadius))
                    path.addLine(to: CGPoint(x: centerPoint + dx * metrics.outerRadius,
                                             y: centerPoint + dy * metrics.outerRadius))
                }
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private func iconContent(index: Int, action: RadialAction, isSelected: Bool) -> some View {
        let midDegrees: Double = -90.0 + RadialMenuGeometry.centerAngle(index: index, count: model.actions.count)
        let mid: Double = midDegrees * Double.pi / 180.0
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
        let title: String = model.selectedAction?.displayName ?? (isPreview ? "圆环预览" : "移动选择")
        let hint: String = model.selectedAction?.hint ?? (isPreview ? "\(model.actions.count) 个扇区" : "回到中心取消")

        return ZStack {
            // 底座已经是整块毛玻璃，中心只加一层极淡的提亮，不再重复叠材质
            Circle()
                .fill(Color.white.opacity(0.055))
                .overlay(
                    Circle().stroke(
                        model.selection == nil ? Color.white.opacity(0.16) : Color.appleBlue.opacity(0.5),
                        lineWidth: 0.5
                    )
                )
                .frame(width: metrics.innerRadius * 2 - size * 0.05,
                       height: metrics.innerRadius * 2 - size * 0.05)
                // 与扇区同层：80% 不透明，留 20% 透出底下的背景模糊
                .opacity(0.8)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 3)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: model.titleSize, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                    // 换字时按内容过渡淡入淡出，而不是硬切
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(hint)
                    .font(.system(size: hintSize, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: metrics.innerRadius * 2 - size * 0.106)
            .multilineTextAlignment(.center)
            .scaleEffect(model.selection == nil ? 1 : 1.03)
            .animation(Motion.moveFast, value: model.selection)
        }
        .scaleEffect(model.isShown ? 1 : 0.92)
        .opacity(model.isShown ? 1 : 0)
        .animation(ringReveal, value: model.isShown)
    }
}
