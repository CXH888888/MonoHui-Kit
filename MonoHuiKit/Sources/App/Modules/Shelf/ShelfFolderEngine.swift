import Foundation
import AppKit

/// 中转站新建文件夹引擎：把选中项移入新文件夹，新文件夹作为一项保留在中转站
enum ShelfFolderEngine {
    /// 在第一个选中项所在目录创建新文件夹，并把所有选中项移入
    /// - Returns: 新加入暂存箱的文件夹 item（失败返回 nil）
    @MainActor
    static func createFolder(with itemIds: [UUID], in store: ShelfStore, name: String) -> ShelfItem? {
        let items = store.items.filter { itemIds.contains($0.id) }
        guard !items.isEmpty else { return nil }

        // 取第一个选中项的目录作为创建位置（暂存箱文件都在 cacheDir，所以文件夹也创建在 cacheDir）
        let parentDir = items[0].url.deletingLastPathComponent()
        let folderURL = parentDir.appendingPathComponent(name, isDirectory: true)

        // 处理重名
        var finalURL = folderURL
        var counter = 2
        while FileManager.default.fileExists(atPath: finalURL.path) {
            finalURL = parentDir.appendingPathComponent("\(name) \(counter)", isDirectory: true)
            counter += 1
        }

        do {
            try FileManager.default.createDirectory(at: finalURL, withIntermediateDirectories: false)

            // 移入文件
            for item in items {
                let dest = finalURL.appendingPathComponent(item.url.lastPathComponent)
                // 处理目标重名
                var destFinal = dest
                var c = 2
                while FileManager.default.fileExists(atPath: destFinal.path) {
                    let stem = item.url.deletingPathExtension().lastPathComponent
                    let ext = item.url.pathExtension
                    destFinal = finalURL.appendingPathComponent(ext.isEmpty ? "\(stem) \(c)" : "\(stem) \(c).\(ext)")
                    c += 1
                }
                try FileManager.default.moveItem(at: item.url, to: destFinal)
            }

            // 从暂存箱列表移除已移入的项（不触发 handleFileRemoval，文件已移入文件夹）
            for id in itemIds {
                store.removeFromList(id: id)
            }

            // 文件夹已在 cacheDir 里，直接创建 ShelfItem 加入
            // 关键：sourceBundleId 传 "shelf.internal"（非 nil 非 finder），
            // 避免 addItems 的 shouldRelocate=true 把文件夹当孤儿移到 .history/
            let newItems = store.addItems(urls: [finalURL], sourceBundleId: "shelf.internal")

            AppLog.shared.log("中转站新建文件夹：\(finalURL.lastPathComponent)，移入 \(items.count) 项，文件夹已加入中转站", category: "Shelf")
            return newItems.first
        } catch {
            AppLog.shared.log("新建文件夹失败：\(error.localizedDescription)", category: "Shelf", level: .error)
            return nil
        }
    }
}
