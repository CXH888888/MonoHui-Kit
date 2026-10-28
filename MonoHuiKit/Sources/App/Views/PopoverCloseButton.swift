import SwiftUI
import AppKit

/// 弹窗右上角的关闭按钮。
///
/// 弹窗改成无边框后没有系统红灯了，靠这个 + Esc 取消。
/// 样式跟标题行里的「重置」按钮同尺寸（20×20），悬停时才出底色，不抢标题的注意力。
struct PopoverCloseButton: View {
    @State private var hovering = false

    var body: some View {
        Button {
            closeHostWindow()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Color.appleInk : Color.appleSoft)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(hovering ? Color.appleSurface3 : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(.cancelAction)
        .help("关闭（Esc）")
    }

    private func closeHostWindow() {
        let host = NSApp.keyWindow ?? NSApp.windows.first { $0.level == .screenSaver }
        host?.close()
    }
}
