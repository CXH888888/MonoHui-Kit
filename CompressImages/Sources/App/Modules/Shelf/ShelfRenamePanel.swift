import AppKit
import SwiftUI

/// 重命名弹窗面板：独立 NSPanel，贴在暂存箱右侧外部显示，带小尖尖指向暂存箱
/// 用独立 panel 而非 overlay，是因为暂存箱面板窗口宽度有限（140pt），
/// overlay 超出窗口边界会被裁剪
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

        let popoverWidth: CGFloat = 160
        let popoverHeight: CGFloat = 110
        // 贴在暂存箱右侧，间距 8pt（留出尖尖空间）
        let arrowGap: CGFloat = 8
        let popoverX = shelfFrame.maxX + arrowGap
        // 垂直位置：优先对齐锚点 Y（文件按钮位置），否则居中于暂存箱
        let anchorY = anchorScreenY ?? shelfFrame.midY
        // 限制弹窗不超出屏幕可见区域
        let screen = NSScreen.main ?? NSScreen()
        let visibleMinY = screen.visibleFrame.minY
        let visibleMaxY = screen.visibleFrame.maxY
        var popoverY = anchorY - popoverHeight / 2
        if popoverY < visibleMinY {
            popoverY = visibleMinY
        }
        if popoverY + popoverHeight > visibleMaxY {
            popoverY = visibleMaxY - popoverHeight
        }

        // frame 四周各扩大 20pt 给 shadow 留空间，避免投影被裁切
        let shadowPadding: CGFloat = 20
        let frame = NSRect(
            x: popoverX - shadowPadding,
            y: popoverY - shadowPadding,
            width: popoverWidth + shadowPadding * 2 + arrowGap,
            height: popoverHeight + shadowPadding * 2
        )

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

        let targetPanel: NSPanel
        if let existing = self.panel {
            targetPanel = existing
            existing.contentViewController = hosting
        } else {
            // 使用 .titled 样式让 panel 能成为 key 窗口（TextField 才能获取焦点）
            // 用 fullSizeContentView + titlebarAppearsTransparent 隐藏标题栏
            let newPanel = NSPanel(
                contentRect: frame,
                styleMask: [.titled, .fullSizeContentView],
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
            newPanel.titlebarAppearsTransparent = true
            newPanel.titleVisibility = .hidden
            newPanel.isReleasedWhenClosed = false
            newPanel.appearance = NSAppearance(named: .vibrantDark)
            newPanel.contentViewController = hosting
            self.panel = newPanel
            targetPanel = newPanel
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
        panel?.orderOut(nil)
    }
}

/// 重命名弹窗内容视图（带左侧小尖尖指向暂存箱）
private struct ShelfRenamePopover: View {
    let initialName: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var isConfirmHovered: Bool = false

    init(initialName: String, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialName = initialName
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // 选中文件名主体（不含扩展名），方便用户直接改名字
        _name = State(initialValue: initialName)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧小尖尖指向暂存箱
            ArrowShape()
                .fill(Color.black.opacity(0.92))
                .frame(width: 8, height: 16)

            // 右侧弹窗主体
            VStack(spacing: 8) {
                Text("重命名")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                TextField("名称", text: $name, onCommit: {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onConfirm(trimmed)
                    }
                })
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onAppear {
                    // 自动选中文件名主体（不含扩展名）
                    let stem = (name as NSString).deletingPathExtension
                    if !stem.isEmpty {
                        name = stem
                    }
                }

                HStack(spacing: 5) {
                    Button("取消") {
                        onCancel()
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)

                    Button("确认") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onConfirm(trimmed)
                        }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.4) : Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(10)
            .frame(width: 150, height: 110)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
        }
        // frame 四周扩大了 20pt 给 shadow 留空间，内容要相应偏移居中
        // 左侧额外多 arrowGap(8) 的空间
        .padding(.leading, 28)
        .padding(.trailing, 20)
        .padding(.vertical, 20)
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
