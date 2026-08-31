import Foundation
import Observation

/// 中转站文件状态管理
@Observable
final class ShelfStore {
    static let shared = ShelfStore()

    /// 文件项列表（按添加顺序）
    var items: [ShelfItem] = []

    /// 当前选中的文件项 ID（用于空格快速预览）
    var selectedIds: Set<UUID> = []

    /// 是否曾经有过文件（用于首次唤醒虚线占位：一旦加入过文件就不再显示虚线引导）
    var hasHadItems: Bool = false

    /// 各文件项预览区中心在屏幕坐标系中的 Y（用于弹窗精确跟随文件位置）
    /// 由 ShelfItemView 的 PreviewPositionReader 更新
    /// 用 @ObservationIgnored：此数据仅供弹窗定位读取，写入不应触发 UI 观察，
    /// 否则 PreviewPositionReader 在 layout 时写入会触发 SwiftUI 重新布局 → 死循环卡死
    @ObservationIgnored var itemScreenYs: [UUID: CGFloat] = [:]

    /// 临时文件目录（对外暴露，供设置页打开查看）
    /// 只存放「当前暂存箱内」的文件，拖出后的文件移到 historyDirectory
    static let cacheDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home
            .appendingPathComponent("Library/Caches/QuickActions/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// 历史缓存目录（拖出后的文件移到这里）
    /// 与 cacheDirectory 分离，避免再次拖入同名文件时 relocateToCache 检测到重名触发 (1)(2) 重命名
    /// 用「.」前缀隐藏，用户「查看缓存文件夹」时不会看到混乱
    static let historyDirectory: URL = {
        let url = cacheDirectory.appendingPathComponent(".history", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// 临时文件目录（实例属性引用 static，保持单一数据源）
    private var cacheDir: URL { ShelfStore.cacheDirectory }

    /// 历史缓存目录（实例属性引用 static）
    private var historyDir: URL { ShelfStore.historyDirectory }

    private init() {
        // 借鉴 Yoink：监听文件被移到废纸篓，自动从中转站移除对应项
        // 使用 NSWorkspace.didTrashFileNotification（macOS 14+）或定期检查
    }

    /// 检查并移除已不存在的文件（被移到废纸篓或删除）
    /// 在面板显示、拖入、定时器等时机调用
    @MainActor
    func cleanupMissingItems() {
        let toRemove = items.filter { item in
            !FileManager.default.fileExists(atPath: item.url.path)
        }
        for item in toRemove {
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items.remove(at: idx)
                selectedIds.remove(item.id)
                itemScreenYs.removeValue(forKey: item.id)
                AppLog.shared.log("文件已不存在（可能已废纸篓），自动移除：\(item.fileName)", category: "Shelf")
            }
        }
        if items.isEmpty {
            // 被动检查场景（如 showPanel 后异步触发）：用延迟自动隐藏，
            // 不能立即 hidePanel——否则与刚执行的 showPanel 形成
            // showPanel → cleanupMissingItems → hidePanel → 再次 showPanel 死循环，
            // 面板永远停在屏幕外无法显示
            if ShelfPanelController.shared.isMinimized {
                ShelfPanelController.shared.unminimize()
            }
            ShelfPanelController.shared.scheduleAutoHide()
        }
    }

    // MARK: - 增删

    /// 添加文件项（支持批量）
    /// 本地文件（Finder 拖入）会移动到 cacheDir 真正暂存；应用拖入的数据已保存为临时文件
    /// 图片按应用规则自动转换格式（不缩放，保留原始尺寸）
    /// - Returns: 新加入的文件项列表（item.url 已是 cacheDir 下的最终路径）
    @MainActor
    @discardableResult
    func addItems(urls: [URL], sourceBundleId: String? = nil) -> [ShelfItem] {
        let rule = AppRules.shared.rule(for: sourceBundleId)
        // Finder 拖入的文件需要真正暂存（移动到 cacheDir）；应用拖入的保留原 URL
        let shouldRelocate = (sourceBundleId == "com.apple.finder" || sourceBundleId == nil)
        var newItems: [ShelfItem] = []

        for url in urls {
            var item = ShelfItem(url: url, sourceBundleId: sourceBundleId)

            // 本地文件：移动到 cacheDir 真正暂存，记录 originalURL 以便放回原位
            if shouldRelocate {
                let originalURL = url
                if let cachedURL = relocateToCache(from: url) {
                    item.url = cachedURL
                    item.originalURL = originalURL
                    AppLog.shared.log("文件已暂存到缓存目录：\(url.lastPathComponent) → \(cachedURL.path)", category: "Shelf")
                } else {
                    // 移动失败（可能是跨卷或权限问题），保留原 URL
                    AppLog.shared.log("文件移动到缓存失败，保留原 URL：\(url.lastPathComponent)", category: "Shelf", level: .warn)
                }
            }

            items.append(item)
            newItems.append(item)
            AppLog.shared.log("中转站添加：\(item.fileName)（源：\(sourceBundleId ?? "nil")，暂存：\(shouldRelocate)）", category: "Shelf")

            // 有规则且需要转换：按规则转换格式（不缩放，保留原始尺寸）
            if let rule = rule, rule.outputFormat.lowercased() != "original" {
                item.transformStatus = .converting
                updateItem(item)

                Task { @MainActor in
                    let transformed = await Task.detached(priority: .userInitiated) {
                        TransformEngine.transform(url: item.url, rule: rule)
                    }.value
                    if let transformed = transformed {
                        var updated = item
                        // 只有真正转换了（url 变化）才更新 url 和 transformFormat
                        // 避免矢量格式（PDF/SVG）原样返回时被错误标记为已转换
                        if transformed != item.url {
                            updated.url = transformed
                            updated.transformStatus = .completed
                            updated.transformFormat = rule.formatDisplayName
                        } else {
                            // 原样保留（如 PDF/SVG 不转换），清除 converting 状态
                            updated.transformStatus = .none
                            updated.transformFormat = nil
                        }
                        updateItem(updated)
                        if transformed != item.url {
                            AppNotification.send(
                                title: "转换完成",
                                body: "\(item.fileName) → \(rule.formatDisplayName)"
                            )
                        }
                    } else {
                        var updated = item
                        updated.transformStatus = .failed("转换失败")
                        updateItem(updated)
                    }
                }
            }
        }

        // 标记曾经有过文件（首次唤醒虚线占位用）
        if !items.isEmpty {
            hasHadItems = true
        }

        // 有文件添加后取消自动隐藏（保持固定显示）
        if !items.isEmpty {
            ShelfPanelController.shared.cancelAutoHide()
        }

        return newItems
    }

    /// 确保 cacheDir/ 中该文件名可用（同名孤儿先移到 .history/，同名非孤儿加序号）
    /// 解决"重复拖入同名文件 → (1)(2) 累积"问题：
    /// cacheDir/ 中的同名文件一定是拖出后留下的孤儿（不在 items 中），直接移到 .history/ 腾位置
    private func ensureCacheSlot(for fileName: String) -> URL {
        let baseTarget = cacheDir.appendingPathComponent(fileName)

        // 1. 目标位置不存在，直接用
        guard FileManager.default.fileExists(atPath: baseTarget.path) else {
            return baseTarget
        }

        // 2. 同名文件存在，判断是否是孤儿（不在当前 items 中）
        let isInItems = items.contains { $0.url.path == baseTarget.path }
        if !isInItems {
            // 孤儿（上次拖出后留下的），移到 .history/，腾出原位置给新文件
            moveToHistory(baseTarget)
            return baseTarget
        }

        // 3. 同名文件在 items 中（罕见，用户暂存了同名文件），给新文件加序号
        var counter = 1
        let nameWithoutExt = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        while true {
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            let candidate = cacheDir.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            // candidate 也存在，若也是孤儿则移走
            let candidateInItems = items.contains { $0.url.path == candidate.path }
            if !candidateInItems {
                moveToHistory(candidate)
                return candidate
            }
            counter += 1
        }
    }

    /// 把文件移动到 cacheDir，处理重名（同名孤儿先移到 .history/，再不行加序号）
    /// 返回移动后的 URL，失败返回 nil
    private func relocateToCache(from url: URL) -> URL? {
        let fileName = url.lastPathComponent
        let finalTarget = ensureCacheSlot(for: fileName)

        do {
            try FileManager.default.moveItem(at: url, to: finalTarget)
            return finalTarget
        } catch {
            // 移动失败（跨卷等），尝试复制
            do {
                try FileManager.default.copyItem(at: url, to: finalTarget)
                // 复制成功后删除原文件（模拟移动语义）
                try? FileManager.default.removeItem(at: url)
                return finalTarget
            } catch {
                AppLog.shared.log("relocateToCache 失败：\(error.localizedDescription)", category: "Shelf", level: .warn)
                return nil
            }
        }
    }

    /// 把应用拖入的数据（图片/PDF）保存到 cacheDir 为临时文件
    /// 用于 PS/AI 等应用拖出的图层/对象（不是 file URL，是原始数据）
    /// 返回保存后的 URL，失败返回 nil
    func saveDataToCache(data: Data, fileExtension: String, sourceBundleId: String?) -> URL? {
        let timestamp = Int(Date().timeIntervalSince1970)
        let appName = (sourceBundleId ?? "app").split(separator: ".").last.map(String.init) ?? "app"
        let baseName = "\(appName)_\(timestamp)"
        let fileName = "\(baseName).\(fileExtension)"
        let target = ensureCacheSlot(for: fileName)

        do {
            try data.write(to: target)
            AppLog.shared.log("数据已保存到缓存目录：\(target.lastPathComponent)", category: "Shelf")
            return target
        } catch {
            AppLog.shared.log("数据保存到缓存失败：\(error.localizedDescription)", category: "Shelf", level: .warn)
            return nil
        }
    }

    /// 更新指定文件项（触发 UI 刷新）
    @MainActor
    private func updateItem(_ item: ShelfItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
    }

    /// 对单个文件项手动触发格式转换（按应用规则，不缩放）
    @MainActor
    func compressItem(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]
        // 优先用源应用的规则，否则默认 PNG
        let fmt = AppRules.shared.rule(for: item.sourceBundleId)?.outputFormat ?? "png"
        let rule = AppRule(
            bundleId: "manual",
            appName: "手动",
            outputFormat: fmt,
            enabled: true
        )
        items[idx].transformStatus = .converting

        // 转换在后台线程执行，避免阻塞主线程；用 id 重新查找避免 idx 越界
        Task { @MainActor in
            let transformed = await Task.detached(priority: .userInitiated) {
                TransformEngine.transform(url: item.url, rule: rule)
            }.value
            guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
            if let transformed = transformed {
                var updated = items[idx]
                updated.url = transformed
                updated.transformStatus = .completed
                updated.transformFormat = rule.formatDisplayName
                items[idx] = updated
            } else {
                var updated = items[idx]
                updated.transformStatus = .failed("压缩失败")
                items[idx] = updated
            }
        }
    }

    /// 压缩并暂存：使用「快速压缩」设置档位压缩文件，更新对应暂存箱 item
    /// 读取 UserDefaults 中的 quickQuality（默认档位）、quickKeepOriginal（保持原格式）、quickFormat（转换格式）
    /// 仅支持图片格式，非图片文件跳过
    @MainActor
    func compressAndShelf(url: URL) async {
        // 用 url 查找 item id，再走 id 通道
        // 注意：item.url 可能在规则转换后已变成转换后的路径（如 png→jpeg），
        // 此时用原 url 查不到。所以优先精确匹配 url，匹配不到则按 path 比较
        guard let idx = items.firstIndex(where: { $0.url == url || $0.url.path == url.path }) else {
            AppLog.shared.log("压缩并暂存：未找到对应 item - \(url.lastPathComponent)", category: "Shelf", level: .warn)
            return
        }
        await compressAndShelf(id: items[idx].id)
    }

    /// 按 item id 压缩并暂存（更可靠：不受规则转换后 url 变化影响）
    @MainActor
    func compressAndShelf(id: UUID) async {
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            AppLog.shared.log("压缩并暂存：未找到对应 item id=\(id)", category: "Shelf", level: .warn)
            return
        }
        let item = items[idx]
        // 仅支持图片压缩
        let ext = item.url.pathExtension.lowercased()
        guard CompressionFormat.from(fileExtension: ext) != nil else {
            AppLog.shared.log("压缩并暂存：非图片格式，跳过 - \(item.fileName)", category: "Shelf")
            return
        }
        items[idx].transformStatus = .converting

        // 读取「快速压缩」设置（与 Finder 右键「图片·快速压缩」共用同一组配置）
        let defaults = UserDefaults.standard
        let qualityRaw = defaults.string(forKey: "quickQuality") ?? QualityLevel.high.rawValue
        let quality = QualityLevel(rawValue: qualityRaw) ?? .high
        let keepOriginal = defaults.object(forKey: "quickKeepOriginal") as? Bool ?? true
        // 保持原格式：用文件扩展名推断格式；否则用 quickFormat
        let format: CompressionFormat
        if keepOriginal {
            format = CompressionFormat.from(fileExtension: ext) ?? .jpeg
        } else {
            let fmtRaw = defaults.string(forKey: "quickFormat") ?? CompressionFormat.jpeg.rawValue
            format = CompressionFormat(rawValue: fmtRaw) ?? .jpeg
        }

        let inputURL = item.url
        let imageItem = ImageItem(url: inputURL)

        let result = await Task.detached(priority: .userInitiated) {
            let engine = CompressionEngine()
            return await engine.compressSingle(item: imageItem, format: format, quality: quality)
        }.value

        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }

        switch result.status {
        case .completed(let cr):
            // 压缩后输出文件替换原 url，记录压缩后大小和节省百分比用于 UI 显示
            var updated = items[idx]
            updated.url = cr.outputURL
            updated.transformStatus = .completed
            updated.transformFormat = format.displayName
            updated.compressedSize = cr.outputSize
            updated.savedPercent = cr.savedPercent
            items[idx] = updated
            AppLog.shared.log("压缩并暂存完成：\(item.fileName) \(cr.inputSize) → \(cr.outputSize) bytes（节省 \(String(format: "%.0f", cr.savedPercent))%，档位=\(quality.shortLabel) 格式=\(format.rawValue)）", category: "Shelf")
            // 压缩后原文件成为孤立缓存，清理超出 5 个的历史文件
            cleanupExcessCache(keepCount: 5)
        case .failed(let err):
            var updated = items[idx]
            updated.transformStatus = .failed("压缩失败: \(err)")
            items[idx] = updated
            AppLog.shared.log("压缩并暂存失败：\(item.fileName) - \(err)", category: "Shelf", level: .warn)
        default:
            break
        }
    }

    @MainActor
    func remove(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]
        // 非锁定项才允许移除（调用方应已检查，这里兜底）
        items.remove(at: idx)
        selectedIds.remove(id)
        itemScreenYs.removeValue(forKey: id)
        // 根据设置处理文件
        handleFileRemoval(item: item)
        AppLog.shared.log("中转站移除：\(item.fileName)", category: "Shelf")

        // 移除后若无文件：若处于最小化模式先退出，再启动 1.5s 自动隐藏倒计时（消失前先等 1.5s）
        if items.isEmpty {
            if ShelfPanelController.shared.isMinimized {
                ShelfPanelController.shared.unminimize()
            }
            // 先等 1.5s 再消失（用户明确要求：暂存箱窗口消失前都要先等 1.5s）
            ShelfPanelController.shared.scheduleAutoHide()
        }
    }

    /// 仅从暂存箱列表移除 item，不触发文件处理（废纸篓/放回原位）
    /// 用于文件已被其他操作移动的场景（如 createFolder 把文件移入新文件夹）
    @MainActor
    func removeFromList(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        selectedIds.remove(id)
        itemScreenYs.removeValue(forKey: id)
        AppLog.shared.log("中转站列表移除（不处理文件）：\(item.fileName)", category: "Shelf")
    }

    /// 拖出剪切：从暂存箱移除 item，缓存文件保留原位供目标应用读取
    /// - 立即从 UI 移除 item（符合剪切语义）
    /// - 缓存文件保留 cacheDir/ 原位，**不立即移动**（AI 等目标应用持有的 URL 一直有效）
    /// - 延迟 120s 后把孤儿（超 5 个的）移到 .history/，给 AI 充足嵌入时间
    /// - 拖入同名文件时由 ensureCacheSlot 立即把同名孤儿移到 .history/（不等 120s）
    @MainActor
    func removeAfterDrag(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        selectedIds.remove(id)
        itemScreenYs.removeValue(forKey: id)
        AppLog.shared.log("拖出剪切：已从暂存箱移除 - \(item.fileName)（缓存文件保留原位供目标应用读取，120s 后清理）", category: "Shelf")

        // 文件保留 cacheDir/ 原位，延迟 120s 后把孤儿移到 .history/
        // 120s 给 AI/PS 等目标应用充足读取/嵌入时间（AI 嵌入大图可能要几十秒）
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120.0) { [weak self] in
            Task { @MainActor in
                self?.cleanupExcessCache(keepCount: 5)
            }
        }

        // 移除后若无文件：若处于最小化模式先退出，再启动 1.5s 自动隐藏倒计时（消失前先等 1.5s）
        if items.isEmpty {
            if ShelfPanelController.shared.isMinimized {
                ShelfPanelController.shared.unminimize()
            }
            // 先等 1.5s 再消失（用户明确要求：暂存箱窗口消失前都要先等 1.5s）
            ShelfPanelController.shared.scheduleAutoHide()
        }
    }

    /// 把文件从 cacheDir/ 移到 .history/，处理重名（加序号）
    private func moveToHistory(_ url: URL) {
        guard url.path.hasPrefix(cacheDir.path) else { return }
        let fileName = url.lastPathComponent
        var target = historyDir.appendingPathComponent(fileName)
        // 重名处理：加序号（.history/ 内可能已有同名历史文件）
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            target = historyDir.appendingPathComponent(newName)
            counter += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            AppLog.shared.log("缓存文件已移到历史：\(fileName) → .history/", category: "Shelf")
        } catch {
            AppLog.shared.log("移动到历史失败：\(error.localizedDescription)", category: "Shelf", level: .warn)
        }
    }

    // MARK: - 历史记录管理

    /// 清理缓存：cacheDir/ 孤儿（超 keepCount 个）移到 .history/，.history/（超 keepCount 个）移到废纸篓
    /// - cacheDir/ 中的孤儿 = 不在当前 items 中的文件/文件夹（拖出后留下的，给目标应用读取用）
    /// - 保留最新 keepCount 个孤儿在 cacheDir/（给慢速目标应用留时间），其余移到 .history/
    /// - .history/ 保留最新 keepCount 个，其余移到废纸篓
    /// - 文件夹与文件统一处理，避免删除的文件夹在 .history/ 中无限累积
    @MainActor
    func cleanupExcessCache(keepCount: Int = 5) {
        // 第一阶段：把 cacheDir/ 中超 keepCount 个的孤儿移到 .history/
        if let cacheFiles = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let currentItemURLs = Set(items.map { $0.url.path })
            let cacheOrphans = cacheFiles.filter { url in
                // 不过滤文件夹：删除的文件夹也是孤儿，需要参与清理
                FileManager.default.fileExists(atPath: url.path)
                    && !currentItemURLs.contains(url.path)
            }.sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA > dateB  // 最新在前
            }

            // 保留最新 keepCount 个孤儿在 cacheDir/，其余移到 .history/
            if cacheOrphans.count > keepCount {
                for url in cacheOrphans.dropFirst(keepCount) {
                    moveToHistory(url)
                }
                AppLog.shared.log("cacheDir/ 孤儿超 \(keepCount) 个，已把最老的 \(cacheOrphans.count - keepCount) 个移到 .history/", category: "Shelf")
            }
        }

        // 第二阶段：清理 .history/ 中超 keepCount 个的，移到废纸篓
        guard let historyFiles = try? FileManager.default.contentsOfDirectory(
            at: historyDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let historyOrphans = historyFiles.filter { url in
            // 不过滤文件夹：.history/ 中的文件夹也需要超量时清到系统废纸篓
            FileManager.default.fileExists(atPath: url.path)
        }.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dateA > dateB
        }

        if historyOrphans.count > keepCount {
            for url in historyOrphans.dropFirst(keepCount) {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    AppLog.shared.log(".history/ 超 \(keepCount) 个，已移到废纸篓：\(url.lastPathComponent)", category: "Shelf")
                } catch {
                    AppLog.shared.log("移到废纸篓失败：\(url.lastPathComponent) - \(error.localizedDescription)", category: "Shelf", level: .warn)
                }
            }
        }
    }

    /// 恢复上次暂存的文件（从 .history/ 取最新文件，移回 cacheDir/ 并加回暂存箱）
    /// - Returns: 是否恢复成功
    @MainActor
    @discardableResult
    func restoreLastCached() -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: historyDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            AppLog.shared.log("恢复上次暂存：历史目录为空", category: "Shelf", level: .warn)
            return false
        }

        // .history/ 里的文件按修改时间降序
        let historyFiles = files.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return !isDir.boolValue
        }.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dateA > dateB
        }

        guard let lastURL = historyFiles.first else {
            AppLog.shared.log("恢复上次暂存：没有可恢复的文件", category: "Shelf", level: .warn)
            return false
        }

        // 把文件从 .history/ 移回 cacheDir/（处理重名）
        let fileName = lastURL.lastPathComponent
        var target = cacheDir.appendingPathComponent(fileName)
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            target = cacheDir.appendingPathComponent(newName)
            counter += 1
        }
        do {
            try FileManager.default.moveItem(at: lastURL, to: target)
        } catch {
            AppLog.shared.log("恢复上次暂存：移动文件失败 - \(error.localizedDescription)", category: "Shelf", level: .warn)
            return false
        }

        var item = ShelfItem(url: target, sourceBundleId: nil)
        item.originalURL = nil  // 恢复的文件没有原位
        items.append(item)
        hasHadItems = true
        ShelfPanelController.shared.cancelAutoHide()
        AppLog.shared.log("已恢复上次暂存文件：\(item.fileName)", category: "Shelf")
        return true
    }

    /// 一键清空（仅清空未锁定项，根据设置处理文件）
    @MainActor
    func clearUnlocked() {
        let toRemove = items.filter { !$0.isLocked }
        for item in toRemove {
            handleFileRemoval(item: item)
            itemScreenYs.removeValue(forKey: item.id)
        }
        items.removeAll { !$0.isLocked }
        selectedIds.removeAll()
        AppLog.shared.log("中转站清空未锁定项（\(toRemove.count) 个）", category: "Shelf")

        // 清空后若无文件：若处于最小化模式先退出，再启动 1.5s 自动隐藏倒计时（消失前先等 1.5s）
        if items.isEmpty {
            if ShelfPanelController.shared.isMinimized {
                ShelfPanelController.shared.unminimize()
            }
            // 先等 1.5s 再消失（用户明确要求：暂存箱窗口消失前都要先等 1.5s）
            ShelfPanelController.shared.scheduleAutoHide()
        }
    }

    /// 文件移除时的处理：根据设置决定放回原位或移到 App 回收站
    /// App 回收站架构：cacheDir/（当前暂存）→ .history/（App回收站）→ 系统废纸篓（.history/ 超 5 个时清理）
    /// - 本地暂存文件（originalURL != nil，在 cacheDir 下）：
    ///   - "keep"（放回原位）→ 移动回 originalURL
    ///   - "trash"（移到回收站）→ 移到 .history/（App 回收站）
    /// - 应用拖入并转存的文件 / 新建文件夹（originalURL == nil，在 cacheDir 下）：
    ///   - 始终移到 .history/（App 回收站）
    /// - 应用拖入未转存文件（originalURL == nil，不在 cacheDir 下）：
    ///   - "keep" → 不动文件
    ///   - "trash" → 移到系统废纸篓（不归 App 管，无法进 App 回收站）
    private func handleFileRemoval(item: ShelfItem) {
        let isInCache = item.url.path.hasPrefix(cacheDir.path)
        let action = UserDefaults.standard.string(forKey: "shelf_remove_action") ?? "trash"

        if let originalURL = item.originalURL, isInCache {
            // 本地文件暂存：根据设置决定
            if action == "keep" {
                // 放回原位：移动回 originalURL
                moveBackToOriginal(from: item.url, to: originalURL, fileName: item.fileName)
            } else {
                // 移到 App 回收站（.history/）
                moveToHistory(item.url)
                AppLog.shared.log("暂存文件已移到 App 回收站：\(item.fileName)", category: "Shelf")
            }
        } else if isInCache {
            // 应用拖入转存的缓存文件 / 新建文件夹：移到 App 回收站（.history/）
            moveToHistory(item.url)
            AppLog.shared.log("缓存文件已移到 App 回收站：\(item.fileName)", category: "Shelf")
        } else {
            // 应用拖入未转存（保留原 URL）：根据设置决定
            if action == "keep" {
                AppLog.shared.log("文件已放回原位（未暂存）：\(item.fileName)", category: "Shelf")
            } else {
                // 不在缓存中的文件不归 App 管，移到系统废纸篓
                moveURLToTrash(url: item.url, fileName: item.fileName)
                AppLog.shared.log("文件已移到系统废纸篓：\(item.fileName)", category: "Shelf")
            }
        }
    }

    /// 把缓存文件移动回原位置，处理原位置已有同名文件的情况
    private func moveBackToOriginal(from cachedURL: URL, to originalURL: URL, fileName: String) {
        // 如果原位置已有同名文件（比如用户重新下载了），直接删除缓存副本
        if FileManager.default.fileExists(atPath: originalURL.path) {
            try? FileManager.default.removeItem(at: cachedURL)
            AppLog.shared.log("原位置已有同名文件，缓存副本已删除：\(fileName)", category: "Shelf")
            return
        }

        // 确保原位置父目录存在
        let parentDir = originalURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        do {
            try FileManager.default.moveItem(at: cachedURL, to: originalURL)
            AppLog.shared.log("文件已放回原位：\(fileName) → \(originalURL.path)", category: "Shelf")
        } catch {
            // 移动失败（跨卷等），尝试复制后删除缓存
            do {
                try FileManager.default.copyItem(at: cachedURL, to: originalURL)
                try? FileManager.default.removeItem(at: cachedURL)
                AppLog.shared.log("文件已复制回原位：\(fileName) → \(originalURL.path)", category: "Shelf")
            } catch {
                AppLog.shared.log("放回原位失败，文件保留在缓存目录：\(fileName) - \(error.localizedDescription)", category: "Shelf", level: .warn)
            }
        }
    }

    /// 把文件移到废纸篓（不直接删除，可在废纸篓中恢复）
    private func moveURLToTrash(url: URL, fileName: String) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            AppLog.shared.log("移到废纸篓失败，可能已不存在：\(fileName) - \(error.localizedDescription)", category: "Shelf", level: .warn)
        }
    }

    // MARK: - 重命名

    /// 重命名文件项（对文件系统中的文件/文件夹重命名，并更新 item.url）
    /// - Parameters:
    ///   - id: 文件项 ID
    ///   - newName: 新名称（不含路径，含扩展名；文件夹不需要扩展名）
    /// - Returns: 是否重命名成功
    @MainActor
    @discardableResult
    func renameItem(id: UUID, newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }

        let currentURL = items[idx].url
        let currentName = currentURL.lastPathComponent
        // 名字未变化，直接返回成功
        if trimmed == currentName { return true }

        let parentDir = currentURL.deletingLastPathComponent()
        var newURL = parentDir.appendingPathComponent(trimmed)

        // 处理目标重名（同名时加序号）
        var counter = 2
        while FileManager.default.fileExists(atPath: newURL.path) {
            newURL = parentDir.appendingPathComponent("\(trimmed) \(counter)")
            counter += 1
        }

        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            items[idx].url = newURL
            AppLog.shared.log("重命名：\(currentName) → \(trimmed)", category: "Shelf")
            return true
        } catch {
            AppLog.shared.log("重命名失败：\(currentName) → \(trimmed) - \(error.localizedDescription)", category: "Shelf", level: .error)
            return false
        }
    }

    // MARK: - 锁定

    @MainActor
    func toggleLock(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isLocked.toggle()
    }

    // MARK: - 选择

    /// 切换选中状态（Shift+点击多选场景）
    @MainActor
    func toggleSelect(id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    /// 单选（普通点击场景：清空其他选中，只选当前）
    /// - Parameter id: 要选中的文件项 ID（若已选中则取消选中）
    @MainActor
    func selectSingle(id: UUID) {
        if selectedIds == [id] {
            // 已唯一选中：取消选中
            selectedIds.removeAll()
        } else {
            selectedIds = [id]
        }
    }

    @MainActor
    func selectAll() {
        selectedIds = Set(items.map { $0.id })
    }

    @MainActor
    func clearSelection() {
        selectedIds.removeAll()
    }

    /// 当前选中的文件项
    var selectedItems: [ShelfItem] {
        items.filter { selectedIds.contains($0.id) }
    }

    // MARK: - 临时文件清理

    /// App 退出时清理当前暂存箱内的未锁定项（移到废纸篓），保留近 5 次历史缓存
    func cleanupUnlockedOnExit() {
        // 只清理当前暂存箱内的未锁定项，不动已拖出的历史缓存
        let unlockedItems = items.filter { !$0.isLocked }
        for item in unlockedItems {
            let isInCache = item.url.path.hasPrefix(cacheDir.path)
            if isInCache {
                try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            }
        }
        // 清理超出 5 个的历史缓存（移到废纸篓）—— 在 MainActor 上执行
        Task { @MainActor in
            ShelfStore.shared.cleanupExcessCache(keepCount: 5)
        }
        AppLog.shared.log("中转站退出清理完成（未锁定项已移到废纸篓，保留近 5 次历史缓存）", category: "Shelf")
    }
}
