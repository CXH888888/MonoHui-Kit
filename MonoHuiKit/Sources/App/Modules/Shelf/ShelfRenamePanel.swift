import AppKit
import SwiftUI

/// 重命名弹窗面板：独立 NSPanel，贴在暂存箱右侧外部显示，带小尖尖指向暂存箱
/// 用独立 panel 而非 overlay，是因为暂存箱面板窗口宽度有限（140pt），
/// overlay 超出窗口边界会被裁剪
///
/// 关键设计：窗口必须用 **borderless**（无标题栏）。
/// 之前用 .titled 时，标题栏会让「窗口 frame」与「内容 view」坐标系不一致，
/// 导致弹窗垂直中心与锚点 Y 始终有偏移（用户一直反馈的"偏下/不居中"），
/// 且显式设置 preferredContentSize 会触发 NSHostingView 反推窗口 frame 递归崩溃（SIGABRT）。
/// borderless 窗口内容==frame，垂直居中即为精确值。
final class ShelfRenamePanel {
    static let shared = ShelfRenamePanel()
    private init() {}

    private var panel: NSPanel?

    /// 显示重命名弹窗
    /// - Parameters:
    ///   - initialName: 初始文件名
    ///   - itemId: 文件项 ID
    ///   - anchorScreenY: 锚点 Y 坐标（屏幕坐标系，弹窗垂直居中于该 Y）
    ///                    传 nil 则垂直居中于整个暂存箱
    ///   - onConfirm: 确认回调（参数为新名字）
    ///   - onCancel: 取消回调
    func show(
        initialName: String,
        itemId: UUID,
        anchorScreenY: CGFloat? = nil,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // 获取暂存箱面板位置，弹窗贴在其右侧
        guard let shelfFrame = ShelfPanelController.shared.panelScreenFrame else {
            AppLog.shared.log("重命名弹窗：暂存箱面板未显示，无法定位", category: "Shelf", level: .warn)
            return
        }

        // 内容尺寸：箭头 + 主体 + 四周阴影内边距（与 ShelfRenamePopover 完全一致）
        let contentWidth = RenamePopupMetrics.contentWidth
        let contentHeight = RenamePopupMetrics.contentHeight
        // 弹窗左边缘：让箭头尖端（内容左边缘 + shadowInset）对准暂存箱右边缘，留 4pt 间隙
        let popoverX = shelfFrame.maxX - RenamePopupMetrics.leadingInset + 4
        // 垂直位置：优先对齐锚点 Y（文件预览区中心），否则居中于暂存箱
        let anchorY = anchorScreenY ?? shelfFrame.midY
        // 限制弹窗不超出「面板所在屏幕」的可见区域
        // 不能用 NSScreen.main：多显示器时锚点在副屏上，用主屏夹取会把弹窗推偏下
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSPoint(x: shelfFrame.midX, y: anchorY), $0.frame, false)
        } ?? NSScreen.main ?? NSScreen()
        let visibleMinY = screen.visibleFrame.minY
        let visibleMaxY = screen.visibleFrame.maxY
        var popoverY = anchorY - contentHeight / 2
        if popoverY < visibleMinY {
            popoverY = visibleMinY
        }
        if popoverY + contentHeight > visibleMaxY {
            popoverY = visibleMaxY - contentHeight
        }

        // frame 尺寸与内容完全一致（borderless 窗口内容==frame），垂直中心=锚点 Y
        let frame = NSRect(x: popoverX, y: popoverY, width: contentWidth, height: contentHeight)

        let rootView = ShelfRenamePopover(
            initialName: initialName,
            onConfirm: { newName in
                onConfirm(newName)
                ShelfRenamePanel.shared.hide()
            },
            onCancel: {
                onCancel()
                ShelfRenamePanel.shared.hide()
            }
        )
        let hosting = NSHostingController(rootView: rootView)
        hosting.view.layoutSubtreeIfNeeded()
        // borderless 窗口没有 NSThemeFrame（标题栏专用 frame view），
        // 设置 preferredContentSize 不会触发 .titled 下的递归崩溃，
        // 且能让窗口 frame 与内容完全一致，保证垂直居中对齐
        hosting.preferredContentSize = NSSize(width: contentWidth, height: contentHeight)

        let targetPanel: NSPanel
        if let existing = self.panel {
            targetPanel = existing
            existing.contentViewController = hosting
        } else {
            // 用 borderless + canBecomeKey=true 的专用窗口：
            // - borderless：内容==frame，弹窗垂直中心精确对齐锚点 Y
            // - canBecomeKey=true：允许成为 key 窗口，TextField 才能获取焦点
            let newPanel = ShelfRenamePanelWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.hidesOnDeactivate = false
            newPanel.isMovableByWindowBackground = false
            newPanel.becomesKeyOnlyIfNeeded = false
            newPanel.isReleasedWhenClosed = false
            newPanel.appearance = NSAppearance(named: .vibrantDark)
            newPanel.contentViewController = hosting
            self.panel = newPanel
            targetPanel = newPanel
        }

        // 关键：把弹窗设为暂存箱面板的 child window
        // 这样弹窗自动跟随暂存箱移动（跨屏切换时随父窗口移动）
        // 父窗口隐藏（orderOut）时 child window 也会一起隐藏，避免残留
        if targetPanel.parent == nil,
           let shelfPanel = NSApp.windows.first(where: { $0.identifier?.rawValue == "ShelfPanel" }) {
            shelfPanel.addChildWindow(targetPanel, ordered: .above)
        }
        targetPanel.setFrame(frame, display: true)
        if !targetPanel.isVisible {
            targetPanel.orderFrontRegardless()
        }

        // 让面板成为 key 窗口并激活 app，TextField 才能获取焦点编辑
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            targetPanel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        guard let panel = panel else { return }
        // 解除与暂存箱面板的父子关系，避免父窗口下次 orderFront 时弹窗自动跟随重新显示
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
    }
}

/// 重命名弹窗专用窗口：borderless，但允许成为 key 窗口（TextField 才能输入）
private final class ShelfRenamePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 重命名弹窗尺寸常量：内容视图与面板 frame 必须使用同一组数值，
/// 保证弹窗垂直中心精确对齐锚点 Y。
private enum RenamePopupMetrics {
    /// 弹窗主体（深色圆角矩形）宽高
    static let bodyWidth: CGFloat = 200
    static let bodyHeight: CGFloat = 142
    /// 左侧箭头宽度
    static let arrowWidth: CGFloat = 8
    /// 箭头与主体间距
    static let arrowSpacing: CGFloat = 8
    /// 四周阴影内边距（同时容纳 SwiftUI shadow 与窗口 shadow）
    static let shadowInset: CGFloat = 20
    /// 内容总宽：左阴影 + 箭头 + 间距 + 主体 + 右阴影
    static let contentWidth: CGFloat = shadowInset + arrowWidth + arrowSpacing + bodyWidth + shadowInset
    /// 内容总高：上阴影 + 主体 + 下阴影
    static let contentHeight: CGFloat = shadowInset + bodyHeight + shadowInset
    /// 箭头尖端距内容左边缘的距离（= 左阴影内边距），用于定位弹窗对齐暂存箱右边缘
    static let leadingInset: CGFloat = shadowInset
}

/// 重命名弹窗内容视图（带左侧小尖尖指向暂存箱）
private struct ShelfRenamePopover: View {
    let initialName: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String

    init(initialName: String, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialName = initialName
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // 选中文件名主体（不含扩展名），方便用户直接改名字
        _name = State(initialValue: initialName)
    }

    var body: some View {
        HStack(spacing: RenamePopupMetrics.arrowSpacing) {
            // 左侧小尖尖指向暂存箱
            ArrowShape()
                .fill(Color.black.opacity(0.92))
                .frame(width: RenamePopupMetrics.arrowWidth, height: 16)

            // 右侧弹窗主体
            VStack(spacing: 12) {
                Text("重命名")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                TextField("名称", text: $name, onCommit: {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onConfirm(trimmed)
                    }
                })
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onAppear {
                    // 自动选中文件名主体（不含扩展名）
                    let stem = (name as NSString).deletingPathExtension
                    if !stem.isEmpty {
                        name = stem
                    }
                }

                HStack(spacing: 8) {
                    // 关键：背景/尺寸放在 label 内部，让整个按钮区域都可点击
                    // （.plain 样式下，label 的内容区域才是点击热区；背景画在 Button 外层则只响应文字）
                    Button {
                        onCancel()
                    } label: {
                        Text("取消")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onConfirm(trimmed)
                        }
                    } label: {
                        Text("确认")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.4) : Color.appleBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
            .frame(width: RenamePopupMetrics.bodyWidth, height: RenamePopupMetrics.bodyHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
        }
        // 四周留 shadow 内边距，并固定整体尺寸 = 面板 frame 尺寸，
        // 保证弹窗内容与 frame 完全一致、垂直居中于锚点 Y
        .padding(.horizontal, RenamePopupMetrics.shadowInset)
        .padding(.vertical, RenamePopupMetrics.shadowInset)
        .frame(width: RenamePopupMetrics.contentWidth, height: RenamePopupMetrics.contentHeight)
    }

    /// 左侧小尖尖形状（三角形指向左侧）
    private struct ArrowShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            // 三角形指向左侧（暂存箱方向）
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
