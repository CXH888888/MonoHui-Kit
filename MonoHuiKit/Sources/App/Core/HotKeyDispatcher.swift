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

        if report.hasIssues {
            report.writeToDisk()
        }

        await MainActor.run {
            // 成功 1.8s 收起；有失败或跳过时留 5s，够用户点「查看明细」
            QuickCompressHUDController.shared.finish(report: report)
        }

        AppNotification.send(
            title: report.failedCount > 0 ? "压缩完成，有文件失败" : "压缩完成",
            body: report.notificationBody
        )

        // 明细只由用户点面板上的「查看明细」触发（见 QuickCompressHUD），这里不自动弹窗。
        // 早先失败时是自动弹的，结果用户没点也会冒出结果窗口。
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
        if report.hasIssues { report.writeToDisk() }

        await MainActor.run {
            // 成功 1.8s 收起；有失败或跳过时留 5s，够用户点「查看明细」
            QuickCompressHUDController.shared.finish(report: report)
        }

        AppNotification.send(
            title: report.failedCount > 0 ? "视频压缩完成，有文件失败" : "视频压缩完成",
            body: report.notificationBody
        )

        // 与图片链路一致：明细只在用户点「查看明细」时弹出，不自动打扰
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

    /// 当前弹窗窗口。弹窗视图在 onAppear 里必须用这个精确定位自己所在的窗口——
    /// 不能用 `NSApp.windows.first(where: { $0.level == .screenSaver })`：
    /// 被 close() 的旧窗口仍留在 NSApp.windows 里（isReleasedWhenClosed = false），
    /// 那个 first 很可能拿到旧的，再 makeKeyAndOrderFront 就把它重新显示出来，
    /// 于是屏幕上出现两块一模一样的弹窗（日志里 0.6s 后 弹窗=2 就是这么来的）。
    static var popupWindow: NSWindow? { currentPopup }

    /// 弹窗窗口校准（固定尺寸）：按内容尺寸 + 四周阴影边距设窗口大小。
    /// 各弹窗 `onAppear` 统一走这里，避免同串窗口设置在多处复制。
    static func calibratePopupWindow(fixedSize size: CGSize) {
        DispatchQueue.main.async {
            guard let window = popupWindow else { return }
            window.setContentSize(NSSize(width: size.width + 2 * Motion.popupShadowInset,
                                         height: size.height + 2 * Motion.popupShadowInset))
            presentPopupWindow(window)
        }
    }

    /// 弹窗窗口校准（自适应高度）：只给宽和高度上下限，高度由 SwiftUI 内容撑开。
    static func calibratePopupWindow(width: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) {
        DispatchQueue.main.async {
            guard let window = popupWindow else { return }
            window.contentMinSize = NSSize(width: width + 2 * Motion.popupShadowInset,
                                           height: minHeight + 2 * Motion.popupShadowInset)
            window.contentMaxSize = NSSize(width: width + 2 * Motion.popupShadowInset,
                                           height: maxHeight + 2 * Motion.popupShadowInset)
            presentPopupWindow(window)
        }
    }

    /// 尺寸设定完后的公共收尾：不可调整大小、贴 Finder 定位、置顶并激活。
    private static func presentPopupWindow(_ window: NSWindow) {
        window.styleMask.remove(.resizable)
        window.isMovableByWindowBackground = true
        FinderSelection.positionWindowNearFinder(window)
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 唤起弹窗前的前台 App（一般是 Finder）。弹窗关掉后把前台还给它，
    /// 否则本 App 仍是 active，焦点会落到主窗口上，看起来就是「关掉弹窗又冒出主界面」。
    private static var previousFrontmost: NSRunningApplication?

    /// 弹窗期间临时收起的主窗口，弹窗关闭后原样恢复。
    /// 弹窗要拿键盘焦点就必须 `NSApp.activate`，而激活会把 App 的所有窗口一起抬到前台，
    /// 用户正开着的主界面就会跟着跳到最前面——只能先把它收起来，关弹窗时再放回去。
    private static var suspendedWindows: [NSWindow] = []

    private static func suspendMainWindows() {
        let targets = NSApp.windows.filter { $0.level == .normal && $0.isVisible }
        guard !targets.isEmpty else { return }
        suspendedWindows = targets
        for window in targets { window.orderOut(nil) }
        AppLog.shared.log("弹窗期间临时收起主窗口 \(targets.count) 个", category: "Dispatcher")
    }

    private static func restoreSuspendedWindows() {
        guard !suspendedWindows.isEmpty else { return }
        for window in suspendedWindows { window.orderFront(nil) }
        suspendedWindows = []
    }

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

        // 不收起主窗口：用户可能正开着设置界面，弹窗只是叠在上面。
        // （之前为了消除「两个窗口」把它 orderOut 了，但真因是旧弹窗被 onAppear 复活，
        //   现在那个已经修掉，没必要再动用户的窗口，也不该切 activationPolicy 把 Dock 图标藏了。）

        // 记录前台 App（必须在 NSApp.activate 之前）
        Self.previousFrontmost = NSWorkspace.shared.frontmostApplication
        Self.suspendMainWindows()

        // 系统窗口阴影对无边框窗口是按内容 alpha 生成的，半径固定，压在这块薄面板上显得很重。
        // 关掉窗口阴影，改由 SwiftUI 自绘一圈淡阴影；四周留出 24pt 透明边距给阴影落位。
        // 最外圈再补一道 0.5pt 描边：只有阴影时面板边缘会糊进背景，加一条 hairline 才有「边界」。
        let shadowInset = PopupChrome.inset
        let shape = RoundedRectangle(cornerRadius: PopupChrome.corner, style: .continuous)
        // 阴影和毛玻璃都交给 PopupChrome（AppKit）画在内容下面：
        // 透明 + screenSaver 层级的窗口里，SwiftUI 的 material 拿不到窗口背后的采样
        // （圆环菜单踩过同样的坑），所以毛玻璃必须用 NSVisualEffectView。
        let content = view
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.appleDivider, lineWidth: 0.5))
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

        // 内容搬进容器，容器最底层放「阴影 + 毛玻璃」
        if let oldContent = window.contentView {
            let hostView = oldContent
            let container = NSView(frame: hostView.bounds)
            container.wantsLayer = true
            hostView.removeFromSuperview()
            hostView.frame = container.bounds
            hostView.autoresizingMask = [.width, .height]
            let chrome = PopupChrome(frame: container.bounds)
            chrome.autoresizingMask = [.width, .height]
            container.addSubview(chrome)
            container.addSubview(hostView)
            window.contentView = container
        }

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
                Self.restoreSuspendedWindows()
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

        // 再补一拍：创建瞬间的快照可能漏掉「稍后才冒出来的第二个窗口」
        // （SwiftUI 场景恢复、旧窗口延迟 orderFront 都发生在下一个 runloop）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let visible = NSApp.windows.filter { $0.isVisible }
            let popups = visible.filter { $0.identifier?.rawValue == "InteractivePopup" }
            AppLog.shared.log("0.6s 后可见窗口=\(visible.count) 弹窗=\(popups.count) "
                              + visible.map { "\($0.identifier?.rawValue ?? "main")@L\($0.level.rawValue)" }
                                        .joined(separator: ","),
                              category: "Dispatcher")
        }
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

extension HotKeyDispatcher {
    /// 创建一块与各功能弹窗外观一致的独立浮层窗口：
    /// 无标题栏、圆角毛玻璃、自绘阴影、Esc 关闭。
    ///
    /// 与 `openStandaloneWindow` 的区别在于**不带弹窗互斥与前台恢复逻辑**——
    /// 那个是「一次只允许一个功能弹窗」的入口守卫，而这里给的是压缩结果这类
    /// 由其他入口弹出的次级窗口：它不该顺手关掉调用它的压缩弹窗，也不该改前台 App。
    static func makePopupStyledWindow<V: View>(content: V, size: CGSize) -> NSWindow {
        let inset = PopupChrome.inset
        let shape = RoundedRectangle(cornerRadius: PopupChrome.corner, style: .continuous)
        let framed = content
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.appleDivider, lineWidth: 0.5))
            .padding(inset)

        let hosting = NSHostingController(rootView: framed)
        let window = PopupWindow(contentViewController: hosting)
        window.styleMask = [.borderless, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 内容搬进容器，容器最底层放「阴影 + 毛玻璃」，与功能弹窗同一套外壳
        if let oldContent = window.contentView {
            let hostView = oldContent
            let container = NSView(frame: hostView.bounds)
            container.wantsLayer = true
            hostView.removeFromSuperview()
            hostView.frame = container.bounds
            hostView.autoresizingMask = [.width, .height]
            let chrome = PopupChrome(frame: container.bounds)
            chrome.autoresizingMask = [.width, .height]
            container.addSubview(chrome)
            container.addSubview(hostView)
            window.contentView = container
        }

        window.setContentSize(NSSize(width: size.width + 2 * inset,
                                     height: size.height + 2 * inset))
        return window
    }
}

/// 弹窗的外壳：一层自绘阴影 + 一层 NSVisualEffectView 毛玻璃，垫在 SwiftUI 内容下面。
///
/// 为什么不用 SwiftUI 的 `.ultraThinMaterial`：这个窗口是透明 + `.screenSaver` 层级，
/// material 拿不到窗口背后的采样，只会渲染成半透明灰（圆环菜单踩过同一个坑）。
final class PopupChrome: NSView {
    /// 窗口四周留出的透明边距，给阴影落位
    static let inset: CGFloat = 24
    static let corner: CGFloat = 12

    private let shadowHost = NSView()
    private let effect = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.22
        shadowHost.layer?.shadowRadius = 16
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -6)
        addSubview(shadowHost)

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.corner
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        addSubview(effect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: Self.inset, dy: Self.inset)
        guard rect.width > 0, rect.height > 0 else { return }
        shadowHost.frame = rect
        shadowHost.layer?.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: rect.size),
            cornerWidth: Self.corner,
            cornerHeight: Self.corner,
            transform: nil
        )
        effect.frame = rect
    }
}
