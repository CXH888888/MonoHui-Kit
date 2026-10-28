import Foundation
import AppKit
import SwiftUI

/// 热键触发后的动作分发器。HotKeyManager 触发后通过此类调用具体业务逻辑。
@MainActor
final class HotKeyDispatcher {
    static let shared = HotKeyDispatcher()

    /// 当前快速压缩任务的取消入口，供 HUD 的「取消」按钮中断
    private var cancelQuickWork: (() -> Void)?

    func dispatch(actionId: HotKeyActionId) {
        AppLog.shared.log("收到 actionId=\(actionId.rawValue)（\(actionId.displayName)）", category: "Dispatcher", level: .hot)

        // 圆环菜单要「按下即出现」，不能等通知授权与 Finder 选中项的 AppleScript 往返。
        // 先显示圆环，选中项异步补上；用户移动到扇区通常要几百毫秒，足够读完。
        if actionId == .radialMenu {
            let modifiers = NSEvent.modifierFlags
            RadialMenuController.shared.show(modifiers: modifiers)
            Task { @MainActor in
                let urls = FinderSelection.currentSelection()
                RadialMenuController.shared.updateURLs(urls)
                AppLog.shared.log("圆环预载选中项 \(urls.count) 个", category: "Dispatcher")
            }
            return
        }

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
            case .videoQuick:
                guard !urls.isEmpty else {
                    AppLog.shared.log("videoQuick 无选中文件，发通知", category: "Dispatcher", level: .warn)
                    AppNotification.send(title: "未检测到选中文件", body: "请先在 Finder 中选中视频再按快捷键")
                    return
                }
                AppLog.shared.log("开始快速视频压缩 \(urls.count) 个文件", category: "Dispatcher")
                await runQuickVideoCompress(urls: urls)
            case .radialMenu:
                // 已在方法开头处理（需要即时响应，不走 0.1s 延迟）
                break
            case .datefolderInteractive:
                AppLog.shared.log("显示新建文件夹弹窗 urls=\(urls.count)", category: "Dispatcher")
                showInteractivePopover(urls: urls, module: "datefolder")
            case .quickRename:
                guard !urls.isEmpty else {
                    AppNotification.send(title: "未检测到选中文件", body: "请先在 Finder 中选中文件再按快捷键")
                    return
                }
                if urls.count > 1 {
                    AppLog.shared.log("显示批量重命名弹窗 urls=\(urls.count)", category: "Dispatcher")
                    showInteractivePopover(urls: urls, module: "quickrenamebatch")
                } else {
                    AppLog.shared.log("显示快速改名弹窗 urls=\(urls.count)", category: "Dispatcher")
                    showInteractivePopover(urls: urls, module: "quickrename")
                }
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

    /// 服务菜单转发来的视频压缩请求
    func dispatchVideoQuickWithUrls(urls: [URL]) {
        AppLog.shared.log("服务菜单转发视频压缩 urls=\(urls.count)", category: "Dispatcher", level: .hot)
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            await runQuickVideoCompress(urls: urls)
        }
    }

    /// 服务菜单转发来的交互弹窗请求（urls 已知，不读 FinderSelection）
    func dispatchInteractiveWithUrls(urls: [URL], actionId: HotKeyActionId) {
        AppLog.shared.log("服务菜单转发交互弹窗 actionId=\(actionId.rawValue) urls=\(urls.count)", category: "Dispatcher", level: .hot)
        let module: String
        switch actionId {
        case .compressInteractive: module = "compress"
        case .datefolderInteractive: module = "datefolder"
        case .quickRename:
            module = urls.count > 1 ? "quickrenamebatch" : "quickrename"
        default: return
        }
        showInteractivePopover(urls: urls, module: module)
    }

    // MARK: - 快速压缩

    /// 快速压缩统一入口（快捷键 + 服务菜单都走这里）
    ///
    /// 与旧实现的关键差异：
    /// - 选中的非图片文件（视频/文档）在预检阶段就跳过，不再交给 sips 报错
    /// - 全程显示浮动进度面板，可取消
    /// - 失败文件逐个记录原因，结束后弹结果窗口并落盘报告
    func runQuickCompress(urls: [URL]) async {
        let defaults = UserDefaults.standard
        let qualityRaw = defaults.string(forKey: "quickQuality") ?? QualityLevel.high.rawValue
        let quality = QualityLevel(rawValue: qualityRaw) ?? .high
        let keepOriginal = defaults.object(forKey: "quickKeepOriginal") as? Bool ?? true
        let fmtRaw = defaults.string(forKey: "quickFormat") ?? CompressionFormat.jpeg.rawValue
        let format = CompressionFormat(rawValue: fmtRaw) ?? .jpeg

        let imageURLs = urls.filter { ImageItem.isSupportedImage($0) }
        let videoURLs = urls.filter { VideoItem.isSupportedVideo($0) }
        let otherURLs = urls.filter {
            !ImageItem.isSupportedImage($0) && !VideoItem.isSupportedVideo($0)
        }

        // 只选了视频：直接走视频压缩，别让用户以为功能坏了
        if imageURLs.isEmpty && !videoURLs.isEmpty {
            AppLog.shared.log("选中项全是视频，转交视频压缩 \(videoURLs.count) 个", category: "Dispatcher")
            await runQuickVideoCompress(urls: videoURLs)
            return
        }

        guard !imageURLs.isEmpty else {
            let body: String
            if !videoURLs.isEmpty {
                body = "选中项是视频，请使用「视频·压缩」"
            } else {
                body = "请先在 Finder 中选中图片再按快捷键"
            }
            AppLog.shared.log("compressQuick 没有可压缩的图片，发通知", category: "Dispatcher", level: .warn)
            AppNotification.send(title: "未检测到图片", body: body)
            return
        }

        let resolver = ToolResolver()
        AppLog.shared.log("快速压缩开始 图片=\(imageURLs.count) 视频=\(videoURLs.count) 其他=\(otherURLs.count) keepOriginal=\(keepOriginal)", category: "Dispatcher")
        AppLog.shared.log("ToolResolver toolsDir=\(resolver.toolsDir) libExists=\(resolver.libExists)", category: "Dispatcher")

        let engine = CompressionEngine()
        let items = imageURLs.map { ImageItem(url: $0) }
        let totalCount = urls.count

        await MainActor.run {
            QuickCompressHUDController.shared.begin(
                title: "正在压缩图片",
                total: totalCount,
                onCancel: { [weak self] in self?.cancelQuickWork?() }
            )
        }

        let work = Task {
            await engine.compress(
                items: items,
                format: format,
                quality: quality,
                keepOriginal: keepOriginal,
                onProgress: { progress in
                    Task { @MainActor in
                        QuickCompressHUDController.shared.update(progress)
                    }
                }
            )
        }
        cancelQuickWork = { work.cancel() }
        let outcome = await work.value
        cancelQuickWork = nil

        // 非图片项并入「跳过」，让最终汇总与用户选中的文件数对得上
        var skipped = outcome.report.skipped
        if !videoURLs.isEmpty {
            skipped.append(CompressionFailure(
                fileName: videoURLs.count == 1 ? videoURLs[0].lastPathComponent : "\(videoURLs.count) 个视频",
                path: videoURLs.first?.path ?? "",
                reason: "视频请使用「视频·压缩」（快捷键 ⌥⇧V）",
                detail: ""
            ))
        }
        if !otherURLs.isEmpty {
            skipped.append(CompressionFailure(
                fileName: otherURLs.count == 1 ? otherURLs[0].lastPathComponent : "\(otherURLs.count) 个其他文件",
                path: otherURLs.first?.path ?? "",
                reason: "不是图片文件，已跳过",
                detail: ""
            ))
        }

        let report = CompressionReport(
            startedAt: outcome.report.startedAt,
            finishedAt: Date(),
            total: totalCount,
            succeeded: outcome.report.succeeded,
            failures: outcome.report.failures,
            skipped: skipped,
            cancelled: outcome.report.cancelled
        )

        AppLog.shared.log("快速压缩完成 \(report.summaryLine)", category: "Dispatcher",
                          level: report.failedCount > 0 ? .warn : .success)

        if report.failedCount > 0 {
            report.writeToDisk()
        }

        await MainActor.run {
            QuickCompressHUDController.shared.finish(
                summary: report.summaryLine,
                failedCount: report.failedCount,
                autoDismissAfter: report.failedCount > 0 ? 0.6 : 1.8
            )
        }

        AppNotification.send(
            title: report.failedCount > 0 ? "压缩完成，有文件失败" : "压缩完成",
            body: report.notificationBody
        )

        if report.failedCount > 0 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                CompressionResultWindowController.shared.show(report: report)
            }
        }
    }

    /// 视频快速压缩（无窗口，带浮动进度）
    func runQuickVideoCompress(urls: [URL]) async {
        let defaults = UserDefaults.standard
        let quality = VideoQuality(rawValue: defaults.string(forKey: "videoQuality") ?? "") ?? .balanced
        let resolution = VideoResolution(rawValue: defaults.string(forKey: "videoResolution") ?? "") ?? .original
        let codec = VideoCodec(rawValue: defaults.string(forKey: "videoCodec") ?? "") ?? .h264

        let videoURLs = urls.filter { VideoItem.isSupportedVideo($0) }
        guard !videoURLs.isEmpty else {
            AppNotification.send(title: "未检测到视频", body: "请先在 Finder 中选中 mp4/mov 等视频文件")
            return
        }

        AppLog.shared.log("视频快速压缩开始 \(videoURLs.count) 个 quality=\(quality.rawValue) resolution=\(resolution.rawValue) codec=\(codec.rawValue)", category: "Dispatcher")

        let engine = VideoCompressionEngine()
        let items = videoURLs.map { VideoItem(url: $0) }

        await MainActor.run {
            QuickCompressHUDController.shared.begin(
                title: "正在压缩视频",
                total: items.count,
                onCancel: { [weak self] in self?.cancelQuickWork?() }
            )
        }

        let work = Task {
            await engine.compress(
                items: items,
                quality: quality,
                resolution: resolution,
                codec: codec,
                onProgress: { progress in
                    Task { @MainActor in
                        QuickCompressHUDController.shared.update(progress)
                    }
                }
            )
        }
        cancelQuickWork = { work.cancel() }
        let outcome = await work.value
        cancelQuickWork = nil

        let report = outcome.report
        AppLog.shared.log("视频快速压缩完成 \(report.summaryLine)", category: "Dispatcher",
                          level: report.failedCount > 0 ? .warn : .success)
        if report.failedCount > 0 { report.writeToDisk() }

        await MainActor.run {
            QuickCompressHUDController.shared.finish(
                summary: report.summaryLine,
                failedCount: report.failedCount,
                autoDismissAfter: report.failedCount > 0 ? 0.6 : 1.8
            )
        }

        AppNotification.send(
            title: report.failedCount > 0 ? "视频压缩完成，有文件失败" : "视频压缩完成",
            body: report.notificationBody
        )

        if report.failedCount > 0 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                CompressionResultWindowController.shared.show(report: report)
            }
        }
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
        } else if module == "quickrenamebatch" {
            openStandaloneWindow(view: QuickRenameBatchPopover().environment(state))
        } else {
            openStandaloneWindow(view: DateFolderPopover().environment(state))
        }
    }

    /// 当前唯一允许存在的弹窗。连点快捷键 / 服务与快捷键同时触发时，
    /// 只靠「遍历 NSApp.windows 按 level 过滤」会漏掉刚创建还没上屏的那个，于是叠出两块。
    private static weak var currentPopup: NSWindow?

    /// 唤起弹窗前的前台 App（一般是 Finder）。弹窗关掉后把前台还给它，
    /// 否则本 App 仍是 active，焦点会落到主窗口上，看起来就是「关掉弹窗又冒出主界面」。
    private static var previousFrontmost: NSRunningApplication?

    private static func restoreFrontmost(_ app: NSRunningApplication?) {
        guard let app,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !app.isTerminated else { return }
        app.activate(options: [])
    }

    private func openStandaloneWindow<V: View>(view: V) {
        // 先收掉上一块（不管是哪条路径创建的）
        if let previous = Self.currentPopup {
            previous.orderOut(nil)
            previous.close()
            Self.currentPopup = nil
        }
        for stale in NSApp.windows where stale.identifier?.rawValue == "InteractivePopup" {
            stale.orderOut(nil)
            stale.close()
        }

        // 弹窗是「即用即走」的：先把主窗口收起来，保证屏幕上只有一块弹窗。
        // 之前主窗口一直留在原地，弹窗淡入后看着就是两个窗口。
        let mainWindows = NSApp.windows.filter { $0.level == .normal && $0.isVisible }
        if !mainWindows.isEmpty {
            for window in mainWindows { window.orderOut(nil) }
            if NSApp.activationPolicy() == .regular {
                NSApp.setActivationPolicy(.accessory)
            }
            AppLog.shared.log("弹窗显示前收起主窗口 \(mainWindows.count) 个", category: "Dispatcher")
        }

        // 记录前台 App（必须在 NSApp.activate 之前）
        Self.previousFrontmost = NSWorkspace.shared.frontmostApplication

        // 系统窗口阴影对无边框窗口是按内容 alpha 生成的，半径固定，压在这块薄面板上显得很重。
        // 关掉窗口阴影，改由 SwiftUI 自绘一圈淡阴影；四周留出 24pt 透明边距给阴影落位。
        let shadowInset: CGFloat = 24
        let content = view
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
            .padding(shadowInset)

        let hosting = NSHostingController(rootView: content)
        let window = PopupWindow(contentViewController: hosting)
        // 无边框：之前用 .titled 保留红色关闭按钮，但会带一条系统标题栏，观感很突兀。
        // 关闭由右上角关闭按钮 / Esc 负责（见 PopoverCloseButton、PopupWindow.cancelOperation）。
        window.styleMask = [.borderless, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 标记为弹窗窗口（windowWillClose 用此判断）
        window.identifier = NSUserInterfaceItemIdentifier("InteractivePopup")
        Self.currentPopup = window

        // 去掉标题栏后没有红色关闭按钮了，Esc 是唯一的取消方式。
        // 只靠 NSWindow.cancelOperation 不够稳（焦点在输入框或 SwiftUI 视图里会被吃掉），
        // 这里再挂一个本地按键监听，窗口关闭时摘掉。
        let escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, window.isKeyWindow else { return event }
            window.close()
            return nil
        }
        // 唤起弹窗前的前台 App。弹窗关掉后把前台还给它——
        // 否则 App 仍是 active，焦点会落到主窗口上，用户看到的就是「关掉弹窗又冒出主界面」。
        let previousApp = Self.previousFrontmost
        if let escMonitor {
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                   object: window,
                                                   queue: .main) { _ in
                NSEvent.removeMonitor(escMonitor)
                Self.restoreFrontmost(previousApp)
            }
        }

        // 先设置内容大小，确保 frame 计算正确
        let fitting = hosting.view.fittingSize
        window.setContentSize(fitting)
        AppLog.shared.log("独立窗口创建 size=\(Int(fitting.width))x\(Int(fitting.height))", category: "Dispatcher")

        // 定位到 Finder 窗口附近
        FinderSelection.positionWindowNearFinder(window)

        // 关键：不切换 activationPolicy（切到 regular 会唤出 SwiftUI WindowGroup 主窗口）
        // accessory 模式下也能显示独立 NSWindow，靠 NSApp.activate + screenSaver level 置顶
        window.level = .screenSaver
        Motion.present(window)
        NSApp.activate(ignoringOtherApps: true)
        // 再次激活确保置顶（macOS 有时需要两次）
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        AppLog.shared.log("独立窗口已显示 level=screenSaver（未切 activationPolicy）", category: "Dispatcher", level: .success)

        // 诊断：把此刻所有窗口的标识/层级/尺寸/可见性打进日志。
        // 「唤起两个弹窗」只能靠这个定位——是残留的旧弹窗，还是主窗口被一起抬起来了。
        let snapshot = NSApp.windows.map { w -> String in
            let id = w.identifier?.rawValue ?? "main"
            let size = "\(Int(w.frame.width))x\(Int(w.frame.height))"
            return "\(id)|L\(w.level.rawValue)|\(size)|\(w.isVisible ? "V" : "H")|a\(String(format: "%.2f", w.alphaValue))"
        }
        AppLog.shared.log("窗口快照[\(snapshot.count)] \(snapshot.joined(separator: " , "))",
                          category: "Dispatcher")
    }
}

/// 无边框弹窗窗口。
///
/// `.borderless` 的 NSWindow 默认 `canBecomeKey == false`，里面的输入框会完全收不到键盘，
/// 所以必须显式放开；同时接管 Esc 关闭——去掉标题栏后用户没有红色关闭按钮可点。
final class PopupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
