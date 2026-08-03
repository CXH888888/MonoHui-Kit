import AppKit
import SwiftUI

/// 最小化横条面板：10pt 宽，贴屏幕左侧，高度同主面板
/// 鼠标悬停时由 ShelfPanelController 触发 peekExpand；点击主 panel 右上角 pin icon 触发 unminimize
final class ShelfMinimizedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = false
        self.appearance = NSAppearance(named: .vibrantDark)
        self.identifier = NSUserInterfaceItemIdentifier("ShelfMinimizedPanel")
    }
}

/// 横条内容视图：纯背景条，无交互按钮
/// pin icon 已移至主 panel 右上角（peek 展开时显示）
/// hover 检测由 ShelfPanelController 统一用 NSEvent 监听处理
struct ShelfMinimizedBar: View {
    var body: some View {
        // 背景条：右侧圆角对齐主面板（左侧贴屏幕边缘为直角）
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 6,
            topTrailingRadius: 6
        )
        .fill(.ultraThinMaterial)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
            .fill(Color.black.opacity(0.55))
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
