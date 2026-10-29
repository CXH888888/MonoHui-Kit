import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    /// 侧栏内容随列宽伸缩。
    ///
    /// 试过「内容固定 200 宽 + 外层裁剪」，结果更糟：列宽变窄时系统会把这一列往左挪，
    /// 裁剪只会把内容**左边**切掉（截图里「图片压缩」变成「片压缩」）。
    /// 所以这里老老实实跟着列宽走，只在按钮文字上加 `lineLimit(1)`，
    /// 保证中间宽度下不会换行把按钮撑高。
    var body: some View {
        column
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appleSidebar)
            // 干掉侧栏底下那层系统毛玻璃（见 SplitMaterialKiller）
            .background(SplitMaterialKiller())
            // 只给 ideal：写死 min = ideal = max 会让系统在展开时先摆到别的宽度再归位，
            // 看起来就是「先缩一下才正常」
            .navigationSplitViewColumnWidth(200)
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
                    // 折叠/展开过程中列宽会短暂变窄，不限制行数的话文字会折行把按钮撑高
                    .lineLimit(1)
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
