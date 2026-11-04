import SwiftUI

/// 滚动边缘淡出：把滚动内容本身按渐变淡到透明，露出**下面真实的底色**。
///
/// 为什么不继续用「近似底色覆盖」：
/// 弹窗根视图是 `applePopupCanvas`（62% 不透明）叠在 `.popover` 毛玻璃上，卡片再叠一层
/// `appleSurface`（5% 白），这条链的合成结果会随桌面壁纸明暗浮动。任何写死的近似色
/// （例如 `appleCardOnCanvas` = 0.155）只在一个背景亮度下对得上——实测卡片实际是 45/255、
/// 遮罩色是 39/255，于是卡片顶/底多出一条比卡片更深、末端还有硬边的色带。
/// mask 只改内容的透明度、不改画面颜色，浅色/深色、任何壁纸都严丝合缝。
struct ScrollEdgeFade: ViewModifier {
    /// 淡出带宽度（pt）
    var length: CGFloat
    /// 顶部、底部各自独立开关：滚到边界时关掉对应一侧
    var top: Bool
    var bottom: Bool

    func body(content: Content) -> some View {
        content
            .mask { fadeMask }
            .animation(Motion.easeInstant, value: top)
            .animation(Motion.easeInstant, value: bottom)
    }

    /// 固定 4 个停靠点，只动颜色不动位置——位置一变就没法补间，开关切换会「跳」
    private var fadeMask: some View {
        GeometryReader { geo in
            let fraction = min(0.5, max(0.0001, length / max(geo.size.height, 1)))
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(top ? 0 : 1), location: 0),
                    .init(color: .black, location: fraction),
                    .init(color: .black, location: 1 - fraction),
                    .init(color: .black.opacity(bottom ? 0 : 1), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

extension View {
    /// 纵向滚动边缘淡出（顶/底各自独立开关）
    func scrollEdgeFade(top: Bool, bottom: Bool, length: CGFloat) -> some View {
        modifier(ScrollEdgeFade(length: length, top: top, bottom: bottom))
    }
}
