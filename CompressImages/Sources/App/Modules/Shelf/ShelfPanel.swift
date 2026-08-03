import AppKit

/// 中转站面板窗口（non-activating NSPanel，不抢前台但可接收点击）
final class ShelfPanel: NSPanel {
    // 必须允许成为 key 窗口，否则内部 SwiftUI 按钮不响应点击
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
        // 允许面板按需成为 key，从而接收键盘和点击事件
        self.becomesKeyOnlyIfNeeded = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = false
        self.appearance = NSAppearance(named: .vibrantDark)
        self.identifier = NSUserInterfaceItemIdentifier("ShelfPanel")
    }
}
