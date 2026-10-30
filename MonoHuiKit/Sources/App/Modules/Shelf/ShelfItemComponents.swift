import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 操作按钮组件

struct ActionButton: View {
    let icon: String
    let tip: String
    let hoverColor: Color
    let action: () -> Void

    @State private var isButtonHovered: Bool = false

    var body: some View {
        HoverTooltipButton(text: tip) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isButtonHovered ? .white : Color.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            // 默认透明无背景框，hover 时才显示颜色
                            .fill(isButtonHovered ? hoverColor : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering in
            isButtonHovered = hovering
        }
    }
}

// MARK: - Hover 延迟 Tooltip 公共组件

/// 独立的 tooltip 窗口：用 NSPanel 浮层显示，不受 ShelfView frame 裁切
/// 位置由调用方传入按钮在屏幕坐标系下的 frame
@MainActor
final class ShelfTooltipWindow {
    static let shared = ShelfTooltipWindow()
    private init() {}

    private var panel: NSPanel?

    /// 显示 tooltip
    /// - Parameters:
    ///   - text: tooltip 文字
    ///   - buttonScreenFrame: 按钮在屏幕坐标系下的 frame（用于定位 tooltip）
    func show(text: String, buttonScreenFrame: CGRect) {
        let tipView = TooltipView(text: text)
        let hosting = NSHostingController(rootView: tipView)
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        let tipWidth = max(size.width, CGFloat(text.count) * 7 + 16)
        let tipHeight = max(size.height, 22)

        // tooltip 显示在按钮右侧，垂直居中，水平间距 6pt
        let tipX = buttonScreenFrame.maxX + 6
        let tipY = buttonScreenFrame.midY - tipHeight / 2

        let frame = NSRect(x: tipX, y: tipY, width: tipWidth, height: tipHeight)

        // 复用 panel：先设置 contentViewController（会触发自动布局），
        // 再用 setFrame 覆盖位置，确保我们的坐标生效
        let targetPanel: NSPanel
        if let existing = self.panel {
            targetPanel = existing
            existing.contentViewController = hosting
        } else {
            let newPanel = NSPanel(
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
            newPanel.ignoresMouseEvents = true
            newPanel.hidesOnDeactivate = false
            newPanel.contentViewController = hosting
            self.panel = newPanel
            targetPanel = newPanel
        }
        // 关键：contentViewController 设置后再 setFrame，覆盖自动布局的 frame
        targetPanel.setFrame(frame, display: true)
        if !targetPanel.isVisible {
            targetPanel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// tooltip 内容视图
    private struct TooltipView: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

/// 鼠标 hover 延迟 0.5s 显示功能名称小标签
/// tooltip 用独立 NSPanel 显示，位置基于鼠标实时坐标
/// 延迟显示避免快速划过时频繁创建 NSPanel，同时提升按钮 hover 响应流畅度
struct HoverTooltipButton<Label: View>: View {
    let text: String
    @ViewBuilder let label: () -> Label

    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        label()
            .onHover { hovering in
                // 取消上一个定时任务（无论进入还是离开）
                hoverTask?.cancel()
                hoverTask = nil
                if hovering {
                    // 延迟 0.5s 显示，快速划过不触发
                    let text = self.text
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        let mouseLoc = NSEvent.mouseLocation
                        let rect = CGRect(x: mouseLoc.x - 10, y: mouseLoc.y - 10, width: 20, height: 20)
                        ShelfTooltipWindow.shared.show(text: text, buttonScreenFrame: rect)
                    }
                } else {
                    ShelfTooltipWindow.shared.hide()
                }
            }
    }
}

// MARK: - 通知名

extension Notification.Name {
    /// 打包后请求显示重命名小窗（userInfo: id=UUID, name=String）
    static let shelfRenameFolder = Notification.Name("shelfRenameFolder")
}

// MARK: - 多文件拖出（NSView + NSDraggingSource）

/// 独立的 NSDraggingSource：避免 NSView 生命周期问题导致的闪退
/// 作为 NSObject 持有 store 引用，拖动结束时通过 store 移除 items
@MainActor
final class ShelfDragSource: NSObject, NSDraggingSource {
    let store: ShelfStore
    let itemIds: [UUID]

    init(store: ShelfStore, itemIds: [UUID]) {
        self.store = store
        self.itemIds = itemIds
        super.init()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // 拖动会话结束：无论是否内部拖动，都重置 isDraggingFromSelf 标志
        ShelfPanelController.shared.isDraggingFromSelf = false

        // 内部拖动（拖到暂存箱自身的压缩区/AirDrop区）：不移除源 items
        // 只有拖到面板外部（Finder/AI 等）才执行剪切移除
        if let panel = NSApp.windows.first(where: { $0.identifier?.rawValue == "ShelfPanel" }),
           panel.frame.contains(screenPoint) {
            AppLog.shared.log("拖动结束于暂存箱内部，跳过移除（内部拖动到压缩/AirDrop区）", category: "Shelf")
            return
        }
        // 拖动结束：延迟 0.3s 确保 drop 目标处理完文件，再移除源 items
        let ids = itemIds
        let store = store
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            for id in ids {
                store.removeAfterDrag(id: id)
            }
        }
    }
}

/// 拖出交互层 NSView：处理 mouseDown/mouseDragged/mouseUp + hover
/// mouseDragged 超过阈值时启动 beginDraggingSession，支持多 NSDraggingItem
/// 借鉴 Yoink：所有交互统一在 NSView，避免 SwiftUI 修饰符被 overlay 拦截
final class ShelfItemDragNSView: NSView {
    var item: ShelfItem?
    var store: ShelfStore?
    var onTap: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var mouseDownPoint: NSPoint = .zero
    private var dragStarted: Bool = false
    private let dragThreshold: CGFloat = 5
    /// 当前拖动的 source（强引用，拖动期间保持存活）
    private var currentSource: ShelfDragSource?
    private var trackingAreaRef: NSTrackingArea?

    /// hitTest：操作按钮区域（右上角约 40×90）返回 nil，让 SwiftUI 按钮可点击
    /// 其余区域返回 self 接收鼠标事件
    override func hitTest(_ point: NSPoint) -> NSView? {
        let buttonWidth: CGFloat = 40
        let buttonHeight: CGFloat = 90
        let actionRect = NSRect(
            x: bounds.maxX - buttonWidth,
            y: bounds.maxY - buttonHeight,
            width: buttonWidth,
            height: buttonHeight
        )
        if actionRect.contains(point) {
            return nil
        }
        return self
    }

    /// 允许在面板非 key 窗口时接收第一次点击
    /// nonactivatingPanel 默认第一次点击用于"激活"，不传递给视图
    /// 返回 true 让第一次点击直接触发 mouseDown，实现"一次点击即选中"
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        let currentPoint = event.locationInWindow
        let dx = currentPoint.x - mouseDownPoint.x
        let dy = currentPoint.y - mouseDownPoint.y
        if sqrt(dx * dx + dy * dy) > dragThreshold {
            dragStarted = true
            startDragSession(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        // 未拖动则视为点击
        guard !dragStarted else { return }
        onTap?()
    }

    private func startDragSession(with event: NSEvent) {
        guard let item = item, let store = store else { return }

        // 通知 ShelfPanelController 当前为内部拖动，避免全局监听误触发 showPanel
        ShelfPanelController.shared.isDraggingFromSelf = true

        // 确定要拖出的文件列表：当前 item 在选中集合中且有多选时拖出所有选中项，否则只拖当前项
        let itemsToDrag: [ShelfItem]
        if store.selectedIds.contains(item.id) && store.selectedIds.count > 1 {
            itemsToDrag = store.items.filter { store.selectedIds.contains($0.id) }
        } else {
            itemsToDrag = [item]
        }

        AppLog.shared.log("startDragSession: 拖出 \(itemsToDrag.count) 个文件（selectedIds=\(store.selectedIds.count)）", category: "Shelf")

        // 借鉴 Yoink：每个 NSDraggingItem 必须设置 draggingFrame + imageComponentsProvider
        // 否则拖动无可见图像，且 Finder 对无图像的多文件拖动可能拒绝接收
        // draggingFrame 在 self.bounds 坐标系内，多个 item 错位堆叠呈现「一摞文件」效果
        let dragImageSize: CGFloat = 64
        let draggingItems: [NSDraggingItem] = itemsToDrag.enumerated().map { (idx, shelfItem) in
            let draggingItem = NSDraggingItem(pasteboardWriter: shelfItem.url as NSURL)
            // 错位堆叠：每个 item 偏移 12pt，第一个 item 居中在鼠标位置
            let offset = CGFloat(idx) * 12
            let frame = NSRect(
                x: bounds.midX - dragImageSize / 2 + offset,
                y: bounds.midY - dragImageSize / 2 - offset,
                width: dragImageSize,
                height: dragImageSize
            )
            draggingItem.draggingFrame = frame
            draggingItem.imageComponentsProvider = {
                let component = NSDraggingImageComponent(key: .icon)
                component.contents = Self.dragImage(for: shelfItem)
                component.frame = NSRect(origin: .zero, size: frame.size)
                return [component]
            }
            return draggingItem
        }
        guard !draggingItems.isEmpty else { return }

        // 用独立 NSObject 作为 source，避免 NSView 生命周期问题
        let source = ShelfDragSource(store: store, itemIds: itemsToDrag.map { $0.id })
        currentSource = source  // 强引用保持存活
        beginDraggingSession(with: draggingItems, event: event, source: source)
        AppLog.shared.log("startDragSession: beginDraggingSession 已调用，items=\(draggingItems.count)", category: "Shelf")
    }

    /// 生成拖动图像：优先用文件图标，兜底用通用图标
    private static func dragImage(for item: ShelfItem) -> NSImage {
        let icon: NSImage
        if FileManager.default.fileExists(atPath: item.url.path) {
            icon = NSWorkspace.shared.icon(forFile: item.url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: UTType.fileURL)
        }
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }
}

/// SwiftUI 包装的拖出交互层
/// onDrag 只能单个 NSItemProvider，这里用 NSView 的 beginDraggingSession 支持多文件拖出
struct ShelfItemDragOverlay: NSViewRepresentable {
    let item: ShelfItem
    let store: ShelfStore
    var onTap: () -> Void
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ShelfItemDragNSView {
        let view = ShelfItemDragNSView()
        view.item = item
        view.store = store
        view.onTap = onTap
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: ShelfItemDragNSView, context: Context) {
        nsView.item = item
        nsView.store = store
        nsView.onTap = onTap
        nsView.onHover = onHover
    }
}

// MARK: - 预览区位置测量（AppKit 直接转换，避免 SwiftUI .global 坐标系歧义）

/// 透明 NSView，挂在预览区 ZStack 上，尺寸等于预览区，报告预览区中心在 AppKit 屏幕坐标中的 Y
/// 转换链：视图中心 → convert 到窗口坐标（nil 即窗口）→ 加窗口 frame.origin.y 得屏幕坐标（左下原点）
/// 弹窗显示时通过 screenCenterY(for:) 实时查询，保证拿到最新位置
final class PreviewPositionNSView: NSView {
    var itemID: UUID?
    var onPositionUpdate: ((CGFloat) -> Void)?

    /// 实时查询指定 item 预览区中心在 AppKit 屏幕坐标中的 Y（找不到返回 nil）
    /// 直接遍历暂存箱面板视图层级查找对应 itemID 的测量视图，
    /// 不依赖注册表（viewDidMoveToWindow 时机不可靠，导致注册缺失）
    static func screenCenterY(for id: UUID) -> CGFloat? {
        guard let panel = NSApp.windows.first(where: { $0.identifier?.rawValue == "ShelfPanel" }),
              let contentView = panel.contentView else {
            AppLog.shared.log("screenCenterY: 面板未找到", category: "Shelf")
            return nil
        }
        let view = findPreviewView(id: id, in: contentView)
        guard let view = view, let window = view.window else {
            AppLog.shared.log("screenCenterY: 未找到 id=\(id) 的测量视图", category: "Shelf")
            return nil
        }
        let centerInWindow = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        let screenY = window.frame.origin.y + centerInWindow.y
        AppLog.shared.log("screenCenterY: id=\(id) bounds=\(view.bounds) windowY=\(centerInWindow.y) screenY=\(screenY) winFrame=\(window.frame)", category: "Shelf")
        return screenY
    }

    /// 深度优先遍历视图层级查找匹配 itemID 的测量视图
    private static func findPreviewView(id: UUID, in view: NSView) -> PreviewPositionNSView? {
        if let preview = view as? PreviewPositionNSView, preview.itemID == id {
            return preview
        }
        for sub in view.subviews {
            if let found = findPreviewView(id: id, in: sub) {
                return found
            }
        }
        return nil
    }

    override func layout() {
        super.layout()
        refresh()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refresh()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refresh()
    }

    func refresh() {
        guard let window = window else { return }
        // 视图中心在窗口坐标系（左下原点）
        let centerInWindow = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        // 窗口坐标 → 屏幕坐标（AppKit，左下原点）：窗口左下角屏幕 Y + 窗口内 Y
        let screenY = window.frame.origin.y + centerInWindow.y
        onPositionUpdate?(screenY)
    }
}

/// SwiftUI 包装的预览区位置测量视图
struct PreviewPositionReader: NSViewRepresentable {
    let itemID: UUID
    var onPositionUpdate: (CGFloat) -> Void

    func makeNSView(context: Context) -> PreviewPositionNSView {
        let view = PreviewPositionNSView()
        view.itemID = itemID
        view.onPositionUpdate = onPositionUpdate
        return view
    }

    func updateNSView(_ nsView: PreviewPositionNSView, context: Context) {
        nsView.itemID = itemID
        nsView.onPositionUpdate = onPositionUpdate
        nsView.refresh()
    }
}
