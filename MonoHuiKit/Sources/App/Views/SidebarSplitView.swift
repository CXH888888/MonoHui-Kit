import SwiftUI

/// 固定两栏（侧栏 + 详情），侧栏常驻不折叠。
///
/// 用自绘而不是 `NavigationSplitView`：后者在尺寸变化时会把内容来回挪、
/// 还会重采样背后画面。侧栏固定 200 宽，列宽和裁剪都归我们。
struct SidebarSplitView<Detail: View, TopTrailingAccessory: View>: View {
    @Binding var selection: SidebarItem?
    @ViewBuilder var detail: Detail
    @ViewBuilder var topTrailingAccessory: TopTrailingAccessory

    /// 侧栏内容距窗口顶的距离：红绿灯组底边再让 8pt
    @State private var sidebarTopInset: CGFloat = 40
    /// 红绿灯最右一颗按钮的右边缘（窗口坐标，距左边），拖拽区从它右边开始
    @State private var trafficLightTrailingEdge: CGFloat = 70

    init(selection: Binding<SidebarItem?>,
         @ViewBuilder detail: () -> Detail,
         @ViewBuilder topTrailingAccessory: () -> TopTrailingAccessory) {
        self._selection = selection
        self.detail = detail()
        self.topTrailingAccessory = topTrailingAccessory()
    }

    static var width: CGFloat { 200 }
    /// 系统标题栏高度：拖拽区高度；页面内容自己从窗口顶 20pt 开始排
    static var titlebarHeight: CGFloat { 28 }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 窗口是透明的（为了侧栏毛玻璃能采样桌面），详情列必须自己铺不透明底
                .background(Color.appleCanvas.allowsHitTesting(false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            // 内容整体上移到窗口顶了，标题栏那一条的拖拽区得自己补。
            // 起点让开红绿灯：拖拽区会吞掉点击，压到按钮上就点不动了
            WindowDragStrip()
                .frame(maxWidth: .infinity)
                .frame(height: Self.titlebarHeight)
                .padding(.leading, trafficLightTrailingEdge + 8)
        }
        // 右上角附件（如快速压缩设置）放在内容坐标系里，距上、右各 20pt
        .overlay(alignment: .topTrailing) {
            topTrailingAccessory
        }
        .ignoresSafeArea(edges: .top)
        // 让窗口非不透明，`.behindWindow` 的毛玻璃才采样得到桌面
        .background(WindowTransparency())
        // 把原生红绿灯挪到距左、上边缘各 16pt，再读回实际布局给侧栏和拖拽区定位
        .background(TitlebarLayout { sidebarInset, trailingEdge in
            sidebarTopInset = sidebarInset
            trafficLightTrailingEdge = trailingEdge
        })
    }

    private var sidebar: some View {
        SidebarView(selection: $selection)
            .frame(width: Self.width)
            .padding(.top, sidebarTopInset)
            // 毛玻璃垫在内容下面、铺满整列（含标题栏那条）
            .background(SidebarBackdrop())
            // 分隔线画在右边缘
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.appleDivider)
                    .frame(width: 1)
            }
    }
}
