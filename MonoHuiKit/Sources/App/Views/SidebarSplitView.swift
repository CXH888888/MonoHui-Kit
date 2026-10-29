import SwiftUI

/// 自绘的两栏布局（侧栏 + 详情），用来替换 `NavigationSplitView`。
///
/// 为什么不用系统的：它的折叠动画由 `NSSplitView` 驱动，列宽从 0 到 200 的过程中
/// 内容会被系统来回挪动，表现为「展开时先缩一下」「内容被左边切掉」。
/// 这几轮反复调列宽约束、材质、裁剪都没能彻底消除，所以自己画：
/// 一个 `HStack` + 一段 `withAnimation`，宽度、裁剪、节奏都归我们。
///
/// 关键做法：侧栏内容（含毛玻璃）**按 200 排版**，宽度交给外层 `.frame(width:)` 动画
/// 加 `.clipped()`。折叠时内容不重排、玻璃层尺寸也不变，只是被从右往左盖住。
struct SidebarSplitView<Detail: View>: View {
    @Binding var selection: SidebarItem?
    @Binding var visible: Bool
    @ViewBuilder var detail: Detail

    @State private var hoveringToggle = false
    /// 从窗口实际布局读到的标题栏高度（默认 28 兜底）
    @State private var titlebarInset: CGFloat = 28
    /// 红绿灯按钮中心到窗口顶的距离，用来让右侧开关和它垂直居中对齐
    @State private var trafficLightCenterY: CGFloat = 14
    /// 红绿灯最右侧按钮的右边缘（窗口坐标，距左边），开关从它右边 12pt 开始
    @State private var trafficLightTrailingEdge: CGFloat = 64

    static var width: CGFloat { 200 }
    static var toggleSize: CGFloat { 24 }
    /// 开关与红绿灯之间的水平间距
    static var toggleGap: CGFloat { 12 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                sidebar
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, titlebarInset)
                    // 窗口是透明的（为了侧栏毛玻璃能采样桌面），详情列必须自己铺不透明底
                    .background(Color.appleCanvas.allowsHitTesting(false))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 内容整体上移到窗口顶了，标题栏那一条的拖拽区得自己补。
            // 起点让开红绿灯：拖拽区会吞掉点击，压到按钮上就点不动了
            WindowDragStrip()
                .frame(maxWidth: .infinity)
                .frame(height: titlebarInset)
                .padding(.leading, trafficLightTrailingEdge + 8)

            // 侧栏开关：水平距红绿灯右边缘 12pt，垂直与红绿灯中心线对齐
            toggleButton(icon: "sidebar.leading")
                .padding(.leading, trafficLightTrailingEdge + Self.toggleGap)
                .padding(.top, max(0, trafficLightCenterY - Self.toggleSize / 2))
        }
        .ignoresSafeArea(edges: .top)
        // 让窗口非不透明，`.behindWindow` 的毛玻璃才采样得到桌面
        .background(WindowTransparency())
        // 从系统读标题栏高度、红绿灯的实际 frame，别写死数字
        .background(TitlebarMetrics { inset, centerY, trailingEdge in
            titlebarInset = inset
            trafficLightCenterY = centerY
            trafficLightTrailingEdge = trailingEdge
        })
    }

    private var sidebar: some View {
        Color.clear
            .frame(width: visible ? Self.width : 0)
            .overlay(alignment: .topLeading) {
                SidebarView(selection: $selection)
                    .frame(width: Self.width)
                    .padding(.top, titlebarInset)
                    // 毛玻璃垫在内容下面、铺满整列（含标题栏那条）；固定 200 宽，不随折叠重采样
                    .background(SidebarBackdrop())
                    // 分隔线画在右边缘，跟着内容一起被裁掉
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.appleDivider)
                            .frame(width: 1)
                    }
            }
            .clipped()
            .animation(Motion.move, value: visible)
    }

    private func toggleButton(icon: String) -> some View {
        Button {
            withAnimation(Motion.move) { visible.toggle() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hoveringToggle ? Color.appleInk : Color.appleSoft)
                // 平时透明，只在悬停时浮出底色——不要给常驻底色，那样像一直按着
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hoveringToggle ? Color.appleSurface2.opacity(0.7) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringToggle = $0 }
        .help(visible ? "隐藏边栏" : "显示边栏")
    }
}
