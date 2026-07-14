import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            // 左上：功能区（主）
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("功能")
                navButton(.compress, icon: "photo", label: "图片压缩")
                navButton(.datefolder, icon: "folder", label: "日期文件夹")
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Divider()

            Spacer()

            // 左下：设置区（次）
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("设置")
                navButton(.hotkey, icon: "keyboard", label: "快捷键")
                navButton(.settings, icon: "gearshape", label: "设置")
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appleSurface)
        .navigationSplitViewColumnWidth(200)
    }

    // MARK: - Section header（micro 样式：11/500/uppercase/0.066em tracking）

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color.appleMuted)
            .padding(.leading, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    // MARK: - 导航按钮（统一 34pt 高，icon 14+text 13）

    private func navButton(_ item: SidebarItem, icon: String, label: String) -> some View {
        let isSelected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 0) {
                // 左侧选中强调条
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.appleBlue : Color.clear)
                    .frame(width: 3, height: 18)
                    .padding(.trailing, 8)
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(isSelected ? Color.appleBlue : Color.appleInk)
                    Text(label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.appleBlue : Color.appleInk)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.appleBlue.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
