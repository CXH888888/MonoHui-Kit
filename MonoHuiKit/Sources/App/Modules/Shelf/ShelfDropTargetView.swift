import SwiftUI
import AppKit

// MARK: - 通知名

extension Notification.Name {
    static let openShelfSettings = Notification.Name("openShelfSettings")
    static let shelfMinimizedChanged = Notification.Name("shelfMinimizedChanged")
}

// MARK: - 原生拖放接收视图（NSViewRepresentable）

/// 用 NSView 的 registerForDraggedTypes + NSDraggingDestination 协议接收拖放
/// 比 SwiftUI onDrop 在 nonactivatingPanel 上更可靠（SwiftUI onDrop 依赖 responder chain，
/// 而 nonactivatingPanel 不成为 key 窗口时 responder chain 可能断裂）
struct ShelfDropTargetView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void
    /// 是否允许接收暂存箱自身拖出的文件（cacheDir 路径）
    /// - false（默认）：面板顶层 drop target，过滤自身拖出避免循环添加
    /// - true：压缩区/AirDrop区，允许自身拖放以触发压缩/AirDrop
    var allowsSelfDrop: Bool = false

    func makeNSView(context: Context) -> ShelfDropTargetNSView {
        let view = ShelfDropTargetNSView()
        view.allowsSelfDrop = allowsSelfDrop
        // 注册文件 URL、URL、图像、PDF、AI 矢量、SVG、通用数据等拖放类型
        // 矢量格式（com.adobe.pdf / com.adobe.illustrator.ai-image）必须注册，
        // 否则 AI 拖出的矢量数据无法被接收，只能降级为 NSImage 转 PNG 丢失矢量信息
        view.registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType(rawValue: "public.url"),
            NSPasteboard.PasteboardType(rawValue: "public.image"),
            NSPasteboard.PasteboardType(rawValue: "com.adobe.pdf"),
            NSPasteboard.PasteboardType(rawValue: "com.adobe.illustrator.ai-image"),
            NSPasteboard.PasteboardType(rawValue: "public.svg-image"),
            NSPasteboard.PasteboardType(rawValue: "public.data")
        ])
        let binding = context.coordinator.isTargeted
        view.onEnter = { binding.wrappedValue = true }
        view.onExit = { binding.wrappedValue = false }
        view.onDropProviders = { urls in
            self.onDrop(urls)
        }
        return view
    }

    func updateNSView(_ nsView: ShelfDropTargetNSView, context: Context) {
        nsView.allowsSelfDrop = allowsSelfDrop
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isTargeted: $isTargeted)
    }

    final class Coordinator: NSObject {
        let isTargeted: Binding<Bool>
        init(isTargeted: Binding<Bool>) {
            self.isTargeted = isTargeted
        }
    }
}

/// 拖放接收 NSView：实现 NSDraggingDestination 协议
final class ShelfDropTargetNSView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onDropProviders: (([URL]) -> Void)?
    /// 是否允许接收暂存箱自身拖出的文件（cacheDir 路径）
    /// false 时过滤 cacheDir 文件避免循环添加；true 时允许（压缩区/AirDrop区需要）
    var allowsSelfDrop: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // 透明背景，不遮挡下层 UI
        self.wantsLayer = true
        self.layer?.backgroundColor = .clear
    }

    override var acceptsFirstResponder: Bool { false }

    /// hitTest 返回 nil：让鼠标点击事件穿透到下层 SwiftUI 视图（如 onTapGesture）
    /// 不影响拖放接收（拖放走 registerForDraggedTypes + NSDraggingDestination，不依赖 hitTest）
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - NSDraggingDestination

    /// 拖动进入：返回 .copy 表示接受拖放
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onEnter?()
        return .copy
    }

    /// 拖动在视图内移动
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    /// 拖动离开
    override func draggingExited(_ sender: NSDraggingInfo?) {
        onExit?()
    }

    /// 执行拖放：从 pasteboard 提取 URL 并回调
    /// 优先级：
    /// 1. NSURL（Finder 文件拖入、PS/AI 拖出 URL 等）
    /// 2. 矢量格式原始数据（PDF/AI/SVG）—— 保留矢量信息，避免转 PNG 后无法在 AI 中打开
    /// 3. NSImage（PS 拖出位图）—— 转 PNG 保存
    /// 4. NSString（SVG 文本）
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onExit?()
        let pboard = sender.draggingPasteboard
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let types = pboard.types ?? []

        // 1. 先尝试读取 NSURL（Finder 文件拖入、PS/AI 拖出 URL 等）
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: false
        ]) as? [URL], !urls.isEmpty {
            // 面板顶层 drop target（allowsSelfDrop=false）：过滤掉来自暂存箱自身缓存目录的文件
            // 场景：从暂存箱拖出文件时，鼠标经过面板会触发顶层 drop target，
            // 若不过滤会把刚拖出的文件又添加回暂存箱，产生 0kb 副本（源文件被拖放会话占用）
            // 压缩区/AirDrop区（allowsSelfDrop=true）：允许自身拖放，以触发压缩/AirDrop
            if !allowsSelfDrop {
                let cacheDir = ShelfStore.cacheDirectory
                let filtered = urls.filter { !$0.path.hasPrefix(cacheDir.path) }
                if filtered.isEmpty {
                    AppLog.shared.log("ShelfDropTargetNSView performDrop: 所有文件均来自缓存目录，过滤掉（暂存箱自身拖出）", category: "Shelf")
                    return true
                }
                AppLog.shared.log("ShelfDropTargetNSView performDrop: urls=\(filtered.count)（过滤前 \(urls.count)）", category: "Shelf")
                onDropProviders?(filtered)
                return true
            } else {
                AppLog.shared.log("ShelfDropTargetNSView performDrop: allowsSelfDrop=true，接收 urls=\(urls.count)", category: "Shelf")
                onDropProviders?(urls)
                return true
            }
        }

        // 2. 优先读取矢量格式原始数据（AI 拖出 PDF/AI 数据，保留矢量信息）
        // AI 默认导出 PDF 矢量数据，转 PNG 会丢失矢量信息导致拖回 AI 无法编辑
        let vectorTypes: [(NSPasteboard.PasteboardType, String)] = [
            (NSPasteboard.PasteboardType(rawValue: "com.adobe.pdf"), "pdf"),
            (NSPasteboard.PasteboardType(rawValue: "com.adobe.illustrator.ai-image"), "ai"),
            (NSPasteboard.PasteboardType(rawValue: "public.svg-image"), "svg"),
        ]

        var urls: [URL] = []
        for (type, ext) in vectorTypes {
            if types.contains(type), let data = pboard.data(forType: type) {
                if let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: ext, sourceBundleId: sourceBundleId) {
                    urls.append(url)
                    AppLog.shared.log("ShelfDropTargetNSView: 提取矢量数据 type=\(type.rawValue) ext=\(ext)", category: "Shelf")
                }
                break  // 只取第一个匹配的矢量格式
            }
        }

        // 3. 兜底：读取 NSImage（PS 拖出位图数据），转 PNG 保存
        if urls.isEmpty, let images = pboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                if let png = ShelfDropTargetNSView.nsImageToPNG(image),
                   let url = ShelfStore.shared.saveDataToCache(data: png, fileExtension: "png", sourceBundleId: sourceBundleId) {
                    urls.append(url)
                }
            }
        }

        // 4. 兜底：读取 NSString（可能是 SVG 文本）
        if urls.isEmpty, let strings = pboard.readObjects(forClasses: [NSString.self], options: nil) as? [NSString] {
            for str in strings {
                let s = str as String
                if s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg"),
                   let data = s.data(using: .utf8),
                   let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: "svg", sourceBundleId: sourceBundleId) {
                    urls.append(url)
                }
            }
        }

        if !urls.isEmpty {
            AppLog.shared.log("ShelfDropTargetNSView performDrop: 从原始数据提取 urls=\(urls.count)", category: "Shelf")
            onDropProviders?(urls)
            return true
        }

        AppLog.shared.log("ShelfDropTargetNSView performDrop: 未提取到 URL types=\(types.map { $0.rawValue })", category: "Shelf", level: .warn)
        return false
    }

    /// NSImage 转 PNG Data
    private static func nsImageToPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
