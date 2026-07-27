import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            // 左上：功能区（主）— 按钮更大、更重
            VStack(alignment: .leading, spacing: 6) {
                primarySectionHeader("功能")
                navButton(.compress, icon: "photo", label: "图片压缩", isPrimary: true)
                navButton(.datefolder, icon: "folder", label: "日期文件夹", isPrimary: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appleSurface)
        .navigationSplitViewColumnWidth(200)
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
            HStack(spacing: 0) {
                // 左侧选中强调条
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.appleBlue : Color.clear)
                    .frame(width: 3, height: isPrimary ? 20 : 14)
                    .padding(.trailing, isPrimary ? 10 : 8)
                HStack(spacing: isPrimary ? 10 : 8) {
                    Image(systemName: icon)
                        .font(.system(size: isPrimary ? 16 : 13, weight: .regular))
                        .frame(width: isPrimary ? 18 : 15, height: isPrimary ? 18 : 15)
                        .foregroundStyle(isSelected ? Color.appleBlue : Color.appleInk)
                    Text(label)
                        .font(.system(size: isPrimary ? 14 : 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.appleBlue : Color.appleInk)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, minHeight: isPrimary ? 40 : 28, alignment: .leading)
            .padding(.horizontal, isPrimary ? 10 : 8)
            .background(isSelected ? Color.appleBlue.opacity(isPrimary ? 0.12 : 0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: isPrimary ? 8 : 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
