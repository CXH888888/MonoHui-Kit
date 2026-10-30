import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 拖入处理与设置入口
extension ShelfView {
    // MARK: - 操作

    func openSettings() {
        NotificationCenter.default.post(name: .openShelfSettings, object: nil)
    }

    /// 拖入处理（接收已提取的 URL 数组，由 ShelfDropTargetNSView 从 pasteboard 提取）
    /// 外部拖入暂存箱 = 仅暂存，不自动压缩
    /// 压缩只在用户手动拖到压缩区时触发
    func handleDropURLs(urls: [URL]) {
        ShelfPanelController.shared.isDraggingOver = true
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        Task { @MainActor in
            store.addItems(urls: urls, sourceBundleId: sourceBundleId)
            ShelfPanelController.shared.isDraggingOver = false
            // 拖入完成后：若暂存箱为空（例如文件被过滤掉），启动自动隐藏
            if store.items.isEmpty {
                ShelfPanelController.shared.scheduleAutoHide()
            }
            AppLog.shared.log("拖入完成：\(urls.count) 个文件", category: "Shelf")
        }
    }

    func handleDrop(providers: [NSItemProvider]) {
        ShelfPanelController.shared.isDraggingOver = true
        // 在拖入入口立即获取源应用 bundleId，避免异步解析期间用户切换应用导致识别错误
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            // 诊断日志：打印 provider 注册的所有 UTI，便于排查应用拖入问题
            let utis = provider.registeredTypeIdentifiers
            AppLog.shared.log("handleDrop: provider UTIs=\(utis) sourceBundleId=\(sourceBundleId ?? "nil")", category: "Shelf")

            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                // file URL（Finder 文件拖入）：直接拿 URL
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = ShelfView.extractURL(from: item) { urls.append(url) }
                }
            } else {
                // 借鉴 Yoink：遍历 provider 注册的所有 UTI，找到第一个能确定文件扩展名的
                // 用该 UTI 加载原始数据，保存为对应扩展名的文件
                // 这样不管 AI/PS/Figma 拖出什么类型（SVG/PDF/PNG/AI 原生）都能正确处理
                let (loadUTI, fileExt) = ShelfView.bestUTI(for: provider)
                guard !loadUTI.isEmpty else {
                    AppLog.shared.log("handleDrop: 无法识别的 provider，UTIs=\(utis)", category: "Shelf", level: .warn)
                    continue
                }
                group.enter()
                provider.loadItem(forTypeIdentifier: loadUTI, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data {
                        if let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: fileExt, sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        }
                    } else if let nsImage = item as? NSImage {
                        // NSImage 兜底转 PNG
                        if let png = ShelfView.nsImageToPNG(nsImage),
                           let url = ShelfStore.shared.saveDataToCache(data: png, fileExtension: "png", sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        }
                    } else if let url = item as? URL {
                        urls.append(url)
                    } else if let str = item as? String {
                        // 文本类型（如 SVG 源码）：检测是否像 SVG，保存为 .svg
                        if str.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg") || str.contains("<svg"),
                           let data = str.data(using: .utf8),
                           let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: "svg", sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        } else if let data = str.data(using: .utf8),
                                  let url = ShelfStore.shared.saveDataToCache(data: data, fileExtension: fileExt, sourceBundleId: sourceBundleId) {
                            urls.append(url)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                store.addItems(urls: urls, sourceBundleId: sourceBundleId)
                ShelfPanelController.shared.isDraggingOver = false
                AppLog.shared.log("拖入完成：\(urls.count) 个文件", category: "Shelf")
            }
        }
    }

    /// 从 NSItemProvider.loadItem 的回调对象中提取 URL
    private static func extractURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        } else if let url = item as? URL {
            return url
        } else if let str = item as? String,
                  let url = URL(string: str) {
            return url
        }
        return nil
    }

    /// NSImage 转 PNG Data
    private static func nsImageToPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// 借鉴 Yoink：遍历 provider 注册的所有 UTI，找到第一个能确定文件扩展名的
    /// 返回 (用于加载的 UTI, 文件扩展名)
    /// 优先选择具体的类型（如 public.svg），跳过过于宽泛的类型（如 public.data）
    private static func bestUTI(for provider: NSItemProvider) -> (String, String) {
        // 优先级：具体类型 > 宽泛类型
        // public.data/public.item/public.content 等太宽泛，放最后兜底
        let genericTypes: Set<String> = [
            "public.data", "public.item", "public.content",
            "public.composite-content", "public.text"
        ]

        // 第一轮：找具体类型（能确定扩展名且不是宽泛类型）
        for uti in provider.registeredTypeIdentifiers {
            if genericTypes.contains(uti) { continue }
            if let utType = UTType(uti),
               let ext = utType.preferredFilenameExtension,
               !ext.isEmpty {
                return (uti, ext)
            }
        }

        // 第二轮：宽泛类型兜底，用 .dat
        for uti in provider.registeredTypeIdentifiers {
            if provider.hasItemConformingToTypeIdentifier(uti) {
                return (uti, "dat")
            }
        }

        return ("public.data", "dat")
    }
}
