import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// 正方形文件项（94×94）+ 右侧悬停操作栈
struct ShelfItemView: View {
    let item: ShelfItem
    @Bindable var store: ShelfStore

    @State private var isHovered: Bool = false
    @State private var thumbnail: NSImage? = nil
    @State private var fileTypeIcon: NSImage? = nil
    @State private var showClearConfirm: Bool = false

    /// 预览正方形尺寸：比面板宽度小更多，让预览更紧凑（面板宽度 - 36）
    private var size: CGFloat {
        let panelWidth = UserDefaults.standard.object(forKey: "shelf_panel_width") as? Double ?? 140
        return CGFloat(panelWidth) - 36
    }

    /// 右侧操作栈按钮定义（关闭、锁定、重命名、新建文件夹）
    private var actions: [(icon: String, tip: String, color: Color, role: ActionRole)] {
        [
            ("xmark", "关闭", Color(red: 1, green: 0.23, blue: 0.19), .close),
            (item.isLocked ? "lock.fill" : "lock.open.fill", item.isLocked ? "解锁" : "锁定", Color(red: 1, green: 0.62, blue: 0.04), .lock),
            ("pencil", "重命名", Color(red: 0.2, green: 0.6, blue: 1), .rename),
            ("folder.badge.plus", "新建文件夹", Color(red: 0.2, green: 0.78, blue: 0.35), .folder),
        ]
    }

    enum ActionRole { case close, lock, compress, folder, airdrop, rename }

    var body: some View {
        VStack(spacing: 4) {
            // 顶部：正方形预览区（访达风格，fit 不裁剪）
            ZStack {
                // 底层：淡底色 + hover 时加深背景
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04))

                previewArea
                    .frame(width: size, height: size)

                // 格式标签（左上角）
                if !formatLabel.isEmpty {
                    formatBadge
                }

                // 锁定 badge（右上角）
                if item.isLocked {
                    lockBadge
                }

                // 转换状态 spinner
                if case .converting = item.transformStatus {
                    convertingOverlay
                }

                // 右侧操作栈（右上角对齐，悬停时渐显，用 opacity 控制避免加入/移出视图树导致布局重算）
                actionStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 4)
                    .padding(.top, 4)
                    .zIndex(10)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
            }
            .frame(width: size, height: size)
            // 记录预览区中心在 AppKit 屏幕坐标系中的 Y，供弹窗精确跟随预览区中间
            // 用 NSView 直接 convert 到窗口再转屏幕坐标，避免 SwiftUI .global 坐标系歧义
            .background(
                PreviewPositionReader(itemID: item.id) { screenY in
                    store.itemScreenYs[item.id] = screenY
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        store.selectedIds.contains(item.id) ? Color.appleBlue : Color.clear,
                        lineWidth: 2
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.18), radius: isHovered ? 8 : 4)
            // 所有交互（hover、click、drag）统一由 overlay NSView 处理
            // SwiftUI onHover/onTapGesture/onDrag 会被 overlay NSView 的 hitTest 拦截，所以全部移到 NSView
            .overlay {
                ShelfItemDragOverlay(item: item, store: store) {
                    // 点击回调
                    if NSEvent.modifierFlags.contains(.shift) {
                        store.toggleSelect(id: item.id)
                    } else {
                        store.selectSingle(id: item.id)
                    }
                } onHover: { hovering in
                    withAnimation(Motion.moveFast) {
                        isHovered = hovering
                    }
                }
            }

            // 中部：居中文件名
            Text(item.fileName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)

            // 底部：居中文件大小 + 压缩变化百分比（压缩并暂存后显示）
            // savedPercent > 0 = 压缩变小（节省）显示 -X%；< 0 = 变大显示 +X%；= 0 = 无变化
            if let savedPercent = item.savedPercent {
                Text("\(item.formattedSize)\(Self.compressLabel(savedPercent))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(item.formattedSize)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(width: size)
        .onAppear {
            loadThumbnail()
            loadFileTypeIcon()
        }
    }

    // MARK: - 右侧操作栈

    private var actionStack: some View {
        VStack(spacing: 3) {
            ForEach(actions, id: \.tip) { action in
                ActionButton(
                    icon: action.icon,
                    tip: action.tip,
                    hoverColor: action.color
                ) {
                    handleAction(action.role)
                }
            }
        }
        .padding(3)
        .background(
            // 黑色模糊背景：用 material 实现毛玻璃效果，配合黑色叠加保持暗色调
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.35))
                )
        )
    }

    private func handleAction(_ role: ActionRole) {
        switch role {
        case .close:
            store.remove(id: item.id)
        case .lock:
            store.toggleLock(id: item.id)
        case .compress:
            store.compressItem(id: item.id)
        case .rename:
            // 复用新建文件夹的重命名弹窗（ShelfRenamePanel）
            // 弹窗 Y 实时读取预览区中心的屏幕 Y（精确对齐预览区中间）
            let id = item.id
            let anchorY = PreviewPositionNSView.screenCenterY(for: id)
                ?? store.itemScreenYs[id]
                ?? NSEvent.mouseLocation.y
            // 弹窗内会去掉扩展名让用户改文件名主体，确认时自动补回原扩展名（若用户未手动输入）
            let oldExt = item.url.pathExtension
            ShelfRenamePanel.shared.show(
                initialName: item.fileName,
                itemId: id,
                anchorScreenY: anchorY,
                onConfirm: { newName in
                    var finalName = newName
                    if !oldExt.isEmpty && (newName as NSString).pathExtension.isEmpty {
                        finalName = "\(newName).\(oldExt)"
                    }
                    store.renameItem(id: id, newName: finalName)
                },
                onCancel: {}
            )
        case .folder:
            // 默认文件夹名为当前日期+时分（yyMMdd-HHmm 格式，如 260812-1456），文件项变为文件夹项，然后弹重命名小窗
            // 用时分避免与回收站同名文件夹冲突触发序号后缀
            // 弹窗 Y 实时读取预览区中心的屏幕 Y
            // 关键：必须在 createFolder 之前取 anchorY——createFolder 会 removeFromList 并清空
            // itemScreenYs[item.id]，之后读取会变 nil 落到鼠标位置导致弹窗不对齐
            let id = item.id
            let anchorY = PreviewPositionNSView.screenCenterY(for: id)
                ?? store.itemScreenYs[id]
                ?? NSEvent.mouseLocation.y
            Task { @MainActor in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyMMdd-HHmm"
                let defaultName = formatter.string(from: Date())
                guard let folderItem = ShelfFolderEngine.createFolder(
                    with: [id],
                    in: store,
                    name: defaultName
                ) else { return }
                NotificationCenter.default.post(
                    name: .shelfRenameFolder,
                    object: nil,
                    userInfo: [
                        "id": folderItem.id,
                        "name": folderItem.fileName,
                        "anchorY": anchorY
                    ]
                )
            }
        case .airdrop:
            // 检查文件是否存在，避免分享已废纸篓的文件
            guard FileManager.default.fileExists(atPath: item.url.path) else {
                AppLog.shared.log("AirDrop 失败：文件不存在 - \(item.fileName)", category: "Shelf", level: .warn)
                return
            }
            AirDropHelper.share(urls: [item.url])
        }
    }

    // MARK: - 预览区（访达风格：fit 完整显示不裁剪，带浅色背景）

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            if let thumbnail = thumbnail {
                // fit 模式：完整显示图片不裁剪（跟访达一致）
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipped()
            } else if let icon = fileTypeIcon {
                // 显示系统文件图标（根据扩展名真实图标）
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.6, height: size * 0.6)
            } else {
                Image(systemName: fileTypeSFSymbol)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    /// 文件类型对应的 SF Symbol（兜底，统一使用 FileTypeClassifier）
    private var fileTypeSFSymbol: String {
        FileTypeClassifier.shared.sfSymbol(ext: item.fileExtension, isDirectory: item.isDirectory)
    }

    /// 格式标签文字（如 PNG、PDF、MP4、文件夹等）
    private var formatLabel: String {
        let ext = item.fileExtension
        if ext.isEmpty {
            // 判断是否为目录
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDir), isDir.boolValue {
                return "文件夹"
            }
            return ""
        }
        return ext.uppercased()
    }

    /// 格式标签底色（统一使用 FileTypeClassifier，兼容所有格式）
    private var formatLabelColor: Color {
        let (r, g, b) = FileTypeClassifier.shared.labelColor(ext: item.fileExtension, isDirectory: item.isDirectory)
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - 格式标签 badge（左上角）

    private var formatBadge: some View {
        Text(formatLabel)
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(formatLabelColor)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(4)
    }

    // MARK: - 锁定 badge（左下角）

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9))
            .foregroundStyle(.white)
            .padding(3)
            .background(Color.orange)
            .clipShape(Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(4)
    }

    // MARK: - 转换中遮罩

    private var convertingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        }
    }

    // MARK: - 压缩变化标签
    /// 压缩变化百分比转显示标签
    /// savedPercent > 0 = 压缩变小（节省）→ -X%；< 0 = 变大 → +X%；= 0 = 无变化
    private static func compressLabel(_ savedPercent: Double) -> String {
        let pct = Int(savedPercent.rounded())
        if pct == 0 { return "（无变化）" }
        let sign = pct > 0 ? "-" : "+"
        return "（\(sign)\(abs(pct))%）"
    }

    // MARK: - 缩略图加载

    private func loadThumbnail() {
        // 支持图片和 PDF 预览
        guard item.isImage || item.fileExtension == "pdf" else { return }
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            AppLog.shared.log("缩略图加载失败：文件不存在 - \(item.fileName)", category: "Shelf", level: .warn)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let img: NSImage?
            if item.fileExtension == "pdf" {
                // PDF：用 CGImage 取第一页作为缩略图
                img = Self.loadPDFFirstPage(url: item.url)
            } else {
                img = NSImage(contentsOf: item.url)
            }

            guard let img = img else {
                AppLog.shared.log("缩略图加载失败：无法解析文件 - \(item.fileName)", category: "Shelf", level: .warn)
                return
            }

            let maxSize: CGFloat = 400
            let scale = min(maxSize / img.size.width, maxSize / img.size.height, 1)
            let target = NSSize(
                width: img.size.width * scale,
                height: img.size.height * scale
            )
            let resized = NSImage(size: target)
            resized.lockFocus()
            img.draw(
                in: NSRect(origin: .zero, size: target),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            resized.unlockFocus()
            DispatchQueue.main.async {
                self.thumbnail = resized
            }
        }
    }

    /// 加载 PDF 第一页为 NSImage（用于缩略图预览）
    /// 使用 PDFKit 的 thumbnail API，高分辨率渲染确保清晰度接近访达 Quick Look
    private static func loadPDFFirstPage(url: URL) -> NSImage? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            return nil
        }
        let bounds = page.bounds(for: .mediaBox)
        // 提高渲染分辨率到 600px，确保预览清晰（访达 Quick Look 级别）
        let maxRender: CGFloat = 600
        let scale: CGFloat = min(maxRender / bounds.width, maxRender / bounds.height, 1)
        let width = bounds.width * scale
        let height = bounds.height * scale
        return page.thumbnail(of: NSSize(width: width, height: height), for: .mediaBox)
    }

    /// 加载系统文件图标（缓存到 @State，避免每次重绘都调用 NSWorkspace.shared.icon）
    private func loadFileTypeIcon() {
        let path = item.url.path
        DispatchQueue.global(qos: .userInitiated).async {
            // NSWorkspace.shared.icon 在文件不存在时返回通用文档图标（非 nil）
            // 此处只对存在的文件获取真实图标
            guard FileManager.default.fileExists(atPath: path) else { return }
            let icon = NSWorkspace.shared.icon(forFile: path)
            // 回主线程在浅色（Aqua）外观下栅格化：面板强制 vibrantDark，
            // 否则系统图标里跟随外观的变体（如文件夹）会被渲染得偏暗、发闷
            DispatchQueue.main.async {
                self.fileTypeIcon = Self.rasterizeInLightAppearance(icon) ?? icon
            }
        }
    }

    /// 在浅色外观下按 2x 栅格化图标，得到外观无关、始终明亮的位图。
    /// 需在主线程调用（lockFocus 依赖）。
    @MainActor
    private static func rasterizeInLightAppearance(_ source: NSImage) -> NSImage? {
        let size = source.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale: CGFloat = 2
        let canvas = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            source.draw(in: NSRect(origin: .zero, size: canvas.size))
        }
        return canvas
    }
}

// MARK: - 操作按钮组件

private struct ActionButton: View {
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
