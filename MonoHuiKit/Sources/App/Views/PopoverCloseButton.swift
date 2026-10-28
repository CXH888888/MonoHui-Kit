import SwiftUI
import AppKit

/// 弹窗右上角的关闭按钮。
///
/// 弹窗改成无边框后没有系统红灯了，靠这个 + Esc 取消。
/// 视觉 20×20，命中区域 24×24（含 hover 判定），比图标本身大一圈更好点。
struct PopoverCloseButton: View {
    @State private var hovering = false

    private let hitSize: CGFloat = 24

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
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
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
