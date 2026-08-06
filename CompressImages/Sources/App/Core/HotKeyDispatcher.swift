import Foundation
import AppKit
import SwiftUI

/// 热键触发后的动作分发器。HotKeyManager 触发后通过此类调用具体业务逻辑。
@MainActor
final class HotKeyDispatcher {
    static let shared = HotKeyDispatcher()

    func dispatch(actionId: HotKeyActionId) {
        AppLog.shared.log("收到 actionId=\(actionId.rawValue)（\(actionId.displayName)）", category: "Dispatcher", level: .hot)
        Task { @MainActor in
            // 确保有通知权限（accessory 常驻模式下也需要能弹通知提示）
            await AppNotification.requestAuthorization()

            // 给 Finder 一点时间确保选中状态稳定（热键触发瞬间可能有竞态）
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            var urls = FinderSelection.currentSelection()
            AppLog.shared.log("首次读取选中项：\(urls.count) 个", category: "Dispatcher")

            // 首次读取为空时，再等 0.15s 重试一次（AppleScript 偶发延迟）
            if urls.isEmpty {
                try? await Task.sleep(nanoseconds: 150_000_000)
                urls = FinderSelection.currentSelection()
                AppLog.shared.log("重试读取选中项：\(urls.count) 个", category: "Dispatcher")
            }

            switch actionId {
            case .compressQuick:
                guard !urls.isEmpty else {
                    AppLog.shared.log("compressQuick 无选中文件，发通知", category: "Dispatcher", level: .warn)
                    AppNotification.send(title: "未检测到选中文件", body: "请先在 Finder 中选中图片再按快捷键")
                    return
                }
                AppLog.shared.log("开始快速压缩 \(urls.count) 个文件", category: "Dispatcher")
                await runQuickCompress(urls: urls)
            case .compressInteractive:
                guard !urls.isEmpty else {
                    AppLog.shared.log("compressInteractive 无选中文件，发通知", category: "Dispatcher", level: .warn)
                    AppNotification.send(title: "未检测到选中文件", body: "请先在 Finder 中选中图片再按快捷键")
                    return
                }
                AppLog.shared.log("显示压缩弹窗 urls=\(urls.count)", category: "Dispatcher")
                showInteractivePopover(urls: urls, module: "compress")
            case .datefolderInteractive:
                AppLog.shared.log("显示新建文件夹弹窗 urls=\(urls.count)", category: "Dispatcher")
                showInteractivePopover(urls: urls, module: "datefolder")
            case .quickRename:
                guard !urls.isEmpty else {
                    AppNotification.send(title: "未检测到选中文件", body: "请先在 Finder 中选中文件再按快捷键")
                    return
                }
                if urls.count > 1 {
                    AppNotification.send(title: "快速改名仅支持单个文件", body: "请只选择一个文件")
                    return
                }
                AppLog.shared.log("显示快速改名弹窗 urls=\(urls.count)", category: "Dispatcher")
                showInteractivePopover(urls: urls, module: "quickrename")
            }
        }
    }

    /// 服务菜单转发来的快速压缩请求（urls 已知，不读 FinderSelection）
    func dispatchQuickWithUrls(urls: [URL]) {
        AppLog.shared.log("服务菜单转发快速压缩 urls=\(urls.count)", category: "Dispatcher", level: .hot)
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            await runQuickCompress(urls: urls)
        }
    }

    /// 服务菜单转发来的交互弹窗请求（urls 已知，不读 FinderSelection）
    func dispatchInteractiveWithUrls(urls: [URL], actionId: HotKeyActionId) {
        AppLog.shared.log("服务菜单转发交互弹窗 actionId=\(actionId.rawValue) urls=\(urls.count)", category: "Dispatcher", level: .hot)
        let module: String
        switch actionId {
        case .compressInteractive: module = "compress"
        case .datefolderInteractive: module = "datefolder"
        case .quickRename: module = "quickrename"
        default: return
        }
        showInteractivePopover(urls: urls, module: module)
    }

    // MARK: - 快速压缩

    /// 快速压缩统一入口（快捷键 + 服务菜单都走这里）
    func runQuickCompress(urls: [URL]) async {
        let engine = CompressionEngine()
        let items = urls.map { ImageItem(url: $0) }
        let defaults = UserDefaults.standard
        let qualityRaw = defaults.string(forKey: "quickQuality") ?? QualityLevel.high.rawValue
        let quality = QualityLevel(rawValue: qualityRaw) ?? .high
        let keepOriginal = defaults.bool(forKey: "quickKeepOriginal")

        // 压缩前先确认工具可用，避免后续静默失败难排查
        let resolver = ToolResolver()
        AppLog.shared.log("ToolResolver toolsDir=\(resolver.toolsDir) libExists=\(resolver.libExists)", category: "Dispatcher")
        for tool in ["pngquant", "oxipng", "cjpeg", "djpeg", "gifsicle", "cwebp"] {
            if resolver.toolExists(tool) {
                AppLog.shared.log("工具存在 \(tool)", category: "Dispatcher")
            }
        }

        var successCount = 0
        var failCount = 0
        for item in items {
            let format: CompressionFormat
            if keepOriginal, let detected = item.estimatedFormat {
                format = detected
            } else {
                let fmtRaw = defaults.string(forKey: "quickFormat") ?? CompressionFormat.jpeg.rawValue
                format = CompressionFormat(rawValue: fmtRaw) ?? .jpeg
            }
            AppLog.shared.log("压缩 \(item.url.lastPathComponent) → format=\(format.rawValue) quality=\(quality.shortLabel) inputSize=\(item.fileSize)", category: "Dispatcher")
            let result = await engine.compressSingle(item: item, format: format, quality: quality)
            switch result.status {
            case .completed:
                successCount += 1
                AppLog.shared.log("✅ 压缩成功 \(item.url.lastPathComponent)", category: "Dispatcher", level: .success)
            case .failed(let err):
                failCount += 1
                AppLog.shared.log("压缩失败 \(item.url.lastPathComponent): \(err)", category: "Dispatcher", level: .error)
            case .compressing:
                failCount += 1
                AppLog.shared.log("压缩异常中断 \(item.url.lastPathComponent)（状态停在 compressing）", category: "Dispatcher", level: .error)
            case .pending:
                failCount += 1
                AppLog.shared.log("压缩未启动 \(item.url.lastPathComponent)（状态停在 pending）", category: "Dispatcher", level: .error)
            }
        }
        AppLog.shared.log("快速压缩完成 成功=\(successCount) 失败=\(failCount)", category: "Dispatcher", level: .success)
        AppNotification.send(
            title: "压缩完成",
            body: "\(successCount) 个文件压缩成功\(failCount > 0 ? "，\(failCount) 个失败" : "")"
        )
    }

    // MARK: - 弹出交互弹窗

    private func showInteractivePopover(urls: [URL], module: String) {
        guard let appDelegate = AppDelegate.shared else {
            AppLog.shared.log("AppDelegate.shared 不存在", category: "Dispatcher", level: .error)
            return
        }
        let state = appDelegate.appState

        // 先关闭已存在的弹窗窗口，防止重复堆积
        // 注意：必须在设置 preloadedURLs 之前关闭，因为 close() 会触发 windowWillClose，
        // 里面会清空 preloadedURLs。如果先设置 urls 再 close，urls 会被清空
        let existingPopups = NSApp.windows.filter { $0.level == .screenSaver }
        if !existingPopups.isEmpty {
            AppLog.shared.log("发现 \(existingPopups.count) 个已存在的弹窗窗口，关闭", category: "Dispatcher")
            for window in existingPopups {
                window.orderOut(nil)
                window.close()
            }
        }

        // 关闭旧窗口后再设置 urls，避免被 windowWillClose 清空
        state.preloadedURLs = urls
        // 注意：不设置 state.module / state.moduleArgs
        // openStandaloneWindow 创建的独立窗口直接用弹窗视图作为 root，不经过 ContentView 路由
        // 设置 state.module 会让主窗口的 ContentView 也切换成弹窗视图（用户看到"主窗口也变成弹窗"）
        // module 参数只用于下面决定创建哪种弹窗窗口

        AppLog.shared.log("创建独立窗口 module=\(module) urls=\(urls.count)", category: "Dispatcher")
        if module == "compress" {
            openStandaloneWindow(view: InteractivePopover().environment(state))
        } else if module == "quickrename" {
            openStandaloneWindow(view: QuickRenamePopover().environment(state))
        } else {
            openStandaloneWindow(view: DateFolderPopover().environment(state))
        }
    }

    private func openStandaloneWindow<V: View>(view: V) {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        // 保留系统原生标题栏（含红色关闭按钮），只隐藏标题文字
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 标记为弹窗窗口（windowWillClose 用此判断）
        window.identifier = NSUserInterfaceItemIdentifier("InteractivePopup")
        // 显式显示关闭按钮（标准按钮位 0）
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // 先设置内容大小，确保 frame 计算正确
        let fitting = hosting.view.fittingSize
        window.setContentSize(fitting)
        AppLog.shared.log("独立窗口创建 size=\(Int(fitting.width))x\(Int(fitting.height))", category: "Dispatcher")

        // 定位到 Finder 窗口附近
        FinderSelection.positionWindowNearFinder(window)

        // 关键：不切换 activationPolicy（切到 regular 会唤出 SwiftUI WindowGroup 主窗口）
        // accessory 模式下也能显示独立 NSWindow，靠 NSApp.activate + screenSaver level 置顶
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 再次激活确保置顶（macOS 有时需要两次）
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        AppLog.shared.log("独立窗口已显示 level=screenSaver（未切 activationPolicy）", category: "Dispatcher", level: .success)
    }
}
