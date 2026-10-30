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
