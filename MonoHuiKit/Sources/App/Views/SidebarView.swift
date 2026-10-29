import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    /// 侧栏内容固定宽度。
    ///
    /// 折叠 / 展开时系统会把这一列从 0 动画到 200，**每个中间宽度都会让内容重新布局一遍**，
    /// 按钮被压窄、文字重排，看起来就是「先缩一下再展开」。
    /// 把内容钉死在 200 宽，再让外层按列宽裁掉超出的部分：
    /// 内容原地不动、从左往右揭开，不再有任何重排。
    private static let columnWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            column
                .frame(width: Self.columnWidth)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .background(Color.appleSidebar)
        // 干掉侧栏底下那层系统毛玻璃（见 SplitMaterialKiller）
        .background(SplitMaterialKiller())
        // min = ideal = max：列宽只由系统开合控制，不能拖拽
        .navigationSplitViewColumnWidth(min: Self.columnWidth,
                                        ideal: Self.columnWidth,
                                        max: Self.columnWidth)
    }

    private var column: some View {
        VStack(spacing: 0) {
            // 最上：圆环菜单 —— 交互层，不属于功能模块，单独置顶
            navButton(.radial, icon: "circle.dashed", label: "圆环菜单", isPrimary: true)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 12)

            // 功能区（主）— 按钮更大、更重
            VStack(alignment: .leading, spacing: 6) {
                primarySectionHeader("功能")
                navButton(.compress, icon: "photo", label: "图片压缩", isPrimary: true)
                navButton(.video, icon: "film", label: "视频压缩", isPrimary: true)
                navButton(.format, icon: "arrow.triangle.2.circlepath", label: "格式转化", isPrimary: true)
                navButton(.datefolder, icon: "folder", label: "文件命名扩展", isPrimary: true)
                navButton(.shelf, icon: "tray", label: "文件暂存箱", isPrimary: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 18)

            Spacer()

            // 分割线移到「设置」小标题上方
            Divider()
                .padding(.horizontal, 12)

            // 左下：设置区（次）— 更小、更轻
            VStack(alignment: .leading, spacing: 2) {
                navButton(.hotkey, icon: "keyboard", label: "快捷键", isPrimary: false)
                navButton(.settings, icon: "gearshape", label: "设置", isPrimary: false)
                navButton(.about, icon: "info.circle", label: "关于与诊断", isPrimary: false)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 功能区 section header（更显著）

    private func primarySectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(Color.appleInk)
            .padding(.leading, 10)
            .padding(.bottom, 2)
    }

    // MARK: - 导航按钮（isPrimary 区分主次）

    private func navButton(_ item: SidebarItem, icon: String, label: String, isPrimary: Bool) -> some View {
        let isSelected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: isPrimary ? 10 : 8) {
                Image(systemName: icon)
                    .font(.system(size: isPrimary ? 16 : 13, weight: .regular))
                    .frame(width: isPrimary ? 18 : 15, height: isPrimary ? 18 : 15)
                    .foregroundStyle(isSelected ? Color.white : Color.appleInk)
                Text(label)
                    .font(.system(size: isPrimary ? 14 : 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.appleInk)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: isPrimary ? 40 : 28, alignment: .leading)
            .padding(.horizontal, isPrimary ? 10 : 8)
            .background(isSelected ? Color.appleBlue : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: isPrimary ? 8 : 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
