import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("图片压缩", systemImage: "photo").tag(SidebarItem.compress)
                Label("日期文件夹", systemImage: "folder").tag(SidebarItem.datefolder)
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                selection = .hotkey
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                    Text("快捷键")
                        .font(.system(size: 13, weight: .regular))
                    Spacer()
                }
                .foregroundStyle(selection == .hotkey ? Color.appleBlue : Color.appleInk)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(selection == .hotkey ? Color.appleBlue.opacity(0.12) : Color.clear)

            Button {
                selection = .settings
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                    Text("设置")
                        .font(.system(size: 13, weight: .regular))
                    Spacer()
                }
                .foregroundStyle(selection == .settings ? Color.appleBlue : Color.appleInk)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(selection == .settings ? Color.appleBlue.opacity(0.12) : Color.clear)
        }
        .navigationSplitViewColumnWidth(180)
    }
}
