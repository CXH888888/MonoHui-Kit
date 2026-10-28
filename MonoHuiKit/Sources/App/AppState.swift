import Foundation
import Observation
import SwiftUI

@Observable
final class AppState {
    var preloadedURLs: [URL] = []
    var module: String = ""
    var moduleArgs: [String: String] = [:]
    /// 菜单栏功能项点击后记录目标页面，MainSplitView 挂载/刷新时消费
    var pendingSidebarItem: SidebarItem?
    var selectedFormat: CompressionFormat = .jpeg {
        didSet { UserDefaults.standard.set(selectedFormat.rawValue, forKey: "format") }
    }
    var selectedQuality: QualityLevel = .high {
        didSet { UserDefaults.standard.set(selectedQuality.rawValue, forKey: "quality") }
    }
    var keepOriginalFormat: Bool = true {
        didSet { UserDefaults.standard.set(keepOriginalFormat, forKey: "keepOriginalFormat") }
    }

    // 快速压缩独立参数（右键"图片·快速压缩"使用，与主界面分离）
    var quickQuality: QualityLevel = .high {
        didSet { UserDefaults.standard.set(quickQuality.rawValue, forKey: "quickQuality") }
    }
    var quickFormat: CompressionFormat = .jpeg {
        didSet { UserDefaults.standard.set(quickFormat.rawValue, forKey: "quickFormat") }
    }
    var quickKeepOriginal: Bool = true {
        didSet { UserDefaults.standard.set(quickKeepOriginal, forKey: "quickKeepOriginal") }
    }

    // 视频压缩参数
    var videoQuality: VideoQuality = .balanced {
        didSet { UserDefaults.standard.set(videoQuality.rawValue, forKey: "videoQuality") }
    }
    var videoResolution: VideoResolution = .original {
        didSet { UserDefaults.standard.set(videoResolution.rawValue, forKey: "videoResolution") }
    }
    var videoCodec: VideoCodec = .h264 {
        didSet { UserDefaults.standard.set(videoCodec.rawValue, forKey: "videoCodec") }
    }

    // 全局快捷键开关。启用后 App 驻留菜单栏，监听全局热键。
    var hotKeyEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(hotKeyEnabled, forKey: "hotkey_enabled")
            applyHotKeyEnabled()
        }
    }

    init() {
        // 必须在读取任何 UserDefaults / 初始化 AppLog 之前完成旧版迁移
        LegacyMigration.runIfNeeded()

        UserDefaults.standard.register(defaults: [
            "quality": QualityLevel.high.rawValue,
            "format": CompressionFormat.jpeg.rawValue,
            "keepOriginalFormat": true,
            "quickQuality": QualityLevel.high.rawValue,
            "quickFormat": CompressionFormat.jpeg.rawValue,
            "quickKeepOriginal": true,
            "videoQuality": VideoQuality.balanced.rawValue,
            "videoResolution": VideoResolution.original.rawValue,
            "videoCodec": VideoCodec.h264.rawValue
        ])
        if let raw = UserDefaults.standard.string(forKey: "format"),
           let fmt = CompressionFormat(rawValue: raw) {
            selectedFormat = fmt
        }
        if let raw = UserDefaults.standard.string(forKey: "quality"),
           let ql = QualityLevel(rawValue: raw) {
            selectedQuality = ql
        }
        keepOriginalFormat = UserDefaults.standard.object(forKey: "keepOriginalFormat") as? Bool ?? true

        if let raw = UserDefaults.standard.string(forKey: "quickFormat"),
           let fmt = CompressionFormat(rawValue: raw) {
            quickFormat = fmt
        }
        if let raw = UserDefaults.standard.string(forKey: "quickQuality"),
           let ql = QualityLevel(rawValue: raw) {
            quickQuality = ql
        }
        quickKeepOriginal = UserDefaults.standard.object(forKey: "quickKeepOriginal") as? Bool ?? true

        if let raw = UserDefaults.standard.string(forKey: "videoQuality"),
           let value = VideoQuality(rawValue: raw) { videoQuality = value }
        if let raw = UserDefaults.standard.string(forKey: "videoResolution"),
           let value = VideoResolution(rawValue: raw) { videoResolution = value }
        if let raw = UserDefaults.standard.string(forKey: "videoCodec"),
           let value = VideoCodec(rawValue: raw) { videoCodec = value }

        // 注意：hotKeyEnabled 在 AppDelegate.applicationDidFinishLaunching 中按需启用，
        // 不在 init 里启用——避免服务菜单触发（即用即走）时也意外驻留。
        hotKeyEnabled = UserDefaults.standard.object(forKey: "hotkey_enabled") as? Bool ?? false

        // 提前解析启动参数，确保 ContentView 第一次渲染时就能拿到正确的 module/mode
        parseLaunchArgs()
    }

    /// 应用快捷键启用状态：注册/注销热键 + 菜单栏图标
    /// 激活策略（regular/accessory）由窗口生命周期管理，不在此处切换：
    /// - 主窗口打开时保持 regular（Dock 有图标）
    /// - 主窗口关闭时若热键启用则切 accessory（Dock 隐藏，菜单栏常驻）
    func applyHotKeyEnabled() {
        AppLog.shared.log("applyHotKeyEnabled hotKeyEnabled=\(hotKeyEnabled) module=\(module)", category: "App")
        if hotKeyEnabled {
            // 启用 Finder 激活/失活监听：Finder 激活时注册全部热键，其他 App 激活时只保留全局热键
            HotKeyManager.shared.installFinderWatcher()
            HotKeyManager.shared.refreshForFrontmostApp()
            StatusBarController.shared.show()
        } else {
            HotKeyManager.shared.unregisterAll()
            StatusBarController.shared.hide()
        }
        StatusBarController.shared.refreshMenu()
    }

    private func parseLaunchArgs() {
        let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--module":
                i += 1
                if i < args.count { module = args[i] }
            case "--mode":
                i += 1
                if i < args.count { moduleArgs["mode"] = args[i] }
            case "--format":
                i += 1
                if i < args.count { moduleArgs["format"] = args[i] }
            default:
                if !args[i].hasPrefix("-") {
                    let url = URL(fileURLWithPath: args[i])
                    if FileManager.default.fileExists(atPath: url.path) {
                        preloadedURLs.append(url)
                    }
                }
            }
            i += 1
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    /// 全局共享引用。SwiftUI 用 @NSApplicationDelegateAdaptor 时，
    /// NSApp.delegate 不是 AppDelegate 类型，无法用 NSApp.delegate as? AppDelegate 获取。
    /// 这里在初始化时赋值给 shared，便于 HotKeyDispatcher 等非 UI 代码访问 AppState。
    static weak var shared: AppDelegate?

    /// 标记本进程是否由服务菜单启动（即用即走）。
    /// - true：本进程是 macOS 为服务菜单新启动的，弹窗完成后必须 terminate
    /// - false：本进程是用户主动启动的主进程（常驻），弹窗完成后关窗口回 accessory
    /// 注意：快捷键触发时 HotKeyDispatcher 也会设置 appState.module，但那是运行时设置，
    /// 不影响此标志——此标志只在 applicationDidFinishLaunching 时根据初始 module 判断。
    var isLaunchedByServiceMenu: Bool = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let module = appState.module
        let moduleArgs = appState.moduleArgs
        let urls = appState.preloadedURLs

        // 记录是否由服务菜单启动：启动时 module 已通过命令行参数设置
        isLaunchedByServiceMenu = !module.isEmpty

        AppLog.shared.log("App 启动 module=\(module) args=\(moduleArgs) urls=\(urls.count) hotKeyEnabled=\(appState.hotKeyEnabled) isLaunchedByServiceMenu=\(isLaunchedByServiceMenu)", category: "App")

        // --install / --uninstall 在 parseLaunchArgs 中未处理，这里单独检查
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--install") {
            NSApp.setActivationPolicy(.prohibited)
            do {
                try ServiceMenuInstaller.install(actions: ModuleRegistry.allActions)
                print("✅ 服务菜单已启用")
            } catch {
                print("❌ 服务菜单安装失败：\(error.localizedDescription)")
                AppLog.shared.log("服务菜单安装失败：\(error)", category: "Service", level: .error)
            }
            NSApp.terminate(nil)
            return
        }
        if args.contains("--uninstall") {
            NSApp.setActivationPolicy(.prohibited)
            do {
                try ServiceMenuInstaller.uninstall(actions: ModuleRegistry.allActions)
                print("✅ 服务菜单已禁用")
            } catch {
                print("❌ 服务菜单移除失败：\(error.localizedDescription)")
                AppLog.shared.log("服务菜单移除失败：\(error)", category: "Service", level: .error)
            }
            NSApp.terminate(nil)
            return
        }

        // 服务菜单启动的新进程：如果主进程已运行，转发请求并退出，避免多进程冲突
        if isLaunchedByServiceMenu {
            if ServiceBridge.tryForwardToMain(module: module, args: moduleArgs, urls: urls) {
                // 已转发给主进程，本进程退出
                NSApp.terminate(nil)
                return
            }
            // 主进程没运行，本进程自己处理（即用即走模式）
            AppLog.shared.log("主进程未运行，本进程自行处理请求", category: "Service")
        }

        // --install / --uninstall 已在前面处理

        if module == "compress" && moduleArgs["mode"] == "quick" {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await AppNotification.requestAuthorization()
                await HotKeyDispatcher.shared.runQuickCompress(urls: urls)
                await Self.waitForResultWindowIfNeeded()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { NSApp.terminate(nil) }
            }
        } else if module == "video" && moduleArgs["mode"] == "quick" {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await AppNotification.requestAuthorization()
                await HotKeyDispatcher.shared.runQuickVideoCompress(urls: urls)
                await Self.waitForResultWindowIfNeeded()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { NSApp.terminate(nil) }
            }
        } else if module == "radial" && moduleArgs["mode"] == "preview" {
            // 调试/演示入口：在光标处展示圆环 3 秒后退出，不执行任何动作
            NSApp.setActivationPolicy(.prohibited)
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { RadialMenuController.shared.preview() }
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await MainActor.run { NSApp.terminate(nil) }
            }
        } else if module == "datefolder" && moduleArgs["mode"] == "interactive" {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            Task { await AppNotification.requestAuthorization() }
        } else if module == "datefolder" {
            NSApp.setActivationPolicy(.prohibited)
            let format = moduleArgs["format"] ?? "yyMMdd"
            DateFolderEngine.run(urls: urls, format: format)
            Task {
                await AppNotification.requestAuthorization()
                let prefix = UserDefaults.standard.string(forKey: "datefolder_prefix") ?? ""
                let suffix = UserDefaults.standard.string(forKey: "datefolder_suffix") ?? "-"
                let name = DateFolderEngine.formatName(format: format, prefix: prefix, suffix: suffix)
                AppNotification.send(title: "文件夹已创建", body: name)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { NSApp.terminate(nil) }
            }
        } else if module == "compress" && moduleArgs["mode"] == "interactive" {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            Task { await AppNotification.requestAuthorization() }
        }

        let launchedByService = isLaunchedByServiceMenu
        // 登录项自启：无「打开」AppleEvent 且开启了热键常驻 → 只驻留菜单栏，不弹主窗口
        // SMAppService.mainApp 自启不会携带打开事件（Dock/启动台/`open -a` 都会带 kAEOpenApplication）
        let isLoginAutoLaunch = module.isEmpty
            && appState.hotKeyEnabled
            && NSAppleEventManager.shared().currentAppleEvent == nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 交互弹窗模式：把弹窗窗口置顶 + 居中
            let isInteractive = (module == "compress" && moduleArgs["mode"] == "interactive")
                || (module == "datefolder" && moduleArgs["mode"] == "interactive")
            if isInteractive {
                if launchedByService {
                    // 服务菜单新进程：主窗口就是弹窗（ContentView 根据 module 显示弹窗视图），无 identifier
                    // 直接把所有窗口设成 screenSaver
                    for window in NSApplication.shared.windows {
                        window.center()
                        window.level = .screenSaver
                        window.makeKeyAndOrderFront(nil)
                    }
                } else {
                    // 主进程已驻留：只动独立弹窗窗口（identifier=InteractivePopup），不动主窗口
                    for window in NSApplication.shared.windows where window.identifier?.rawValue == "InteractivePopup" {
                        window.center()
                        window.level = .screenSaver
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
            // 登录项自启：关掉 WindowGroup 默认弹出的主窗口，驻留菜单栏，不抢占前台
            if isLoginAutoLaunch {
                NSApp.setActivationPolicy(.accessory)
                for window in NSApplication.shared.windows where window.level == .normal {
                    window.close()
                }
                return
            }
            NSApp.activate(ignoringOtherApps: true)
        }

        // 恢复快捷键常驻状态：仅当非服务菜单触发（module 为空）时
        // 服务菜单触发（module 非空）时保持即用即走，不启用常驻
        if module.isEmpty && appState.hotKeyEnabled {
            appState.applyHotKeyEnabled()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // 监听窗口成为 key：设置主窗口 hidesOnDeactivate = false
        // SwiftUI WindowGroup 主窗口默认 hidesOnDeactivate 可能在 accessory 模式下为 true，
        // 导致切到其他 app 时主窗口消失。手动设置 false 确保主窗口常驻。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        // 监听菜单栏功能项点击：打开主窗口并跳转对应页面
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSidebarItemFromStatusBar(_:)),
            name: .openSidebarItemFromStatusBar,
            object: nil
        )

        // 主进程订阅服务菜单转发通知：服务菜单新进程把请求转发过来，由主进程处理
        ServiceBridge.subscribe { [weak self] module, args, urls in
            guard let self = self else { return }
            self.handleServiceBridgeRequest(module: module, args: args, urls: urls)
        }

        // 改名后服务菜单 workflow 里仍指向旧可执行文件，主进程启动时自动修复一次
        if !isLaunchedByServiceMenu {
            ServiceMenuInstaller.repairIfNeeded(actions: ModuleRegistry.allActions)
        }

        // 恢复中转站面板：仅当非服务菜单触发（module 为空）且用户已启用时
        if module.isEmpty {
            let shelfEnabled = UserDefaults.standard.object(forKey: "shelf_enabled") as? Bool ?? false
            if shelfEnabled {
                ShelfPanelController.shared.enable()
                AppLog.shared.log("中转站面板已恢复", category: "Shelf")
            }
        }
    }

    /// 服务菜单转发来的请求（主进程收到后调 HotKeyDispatcher）
    private func handleServiceBridgeRequest(module: String, args: [String: String], urls: [URL]) {
        AppLog.shared.log("处理转发请求 module=\(module) args=\(args) urls=\(urls.count)", category: "Service")
        let actionId: HotKeyActionId
        switch (module, args["mode"]) {
        case ("compress", "quick"):
            actionId = .compressQuick
        case ("compress", "interactive"):
            actionId = .compressInteractive
        case ("video", "quick"):
            actionId = .videoQuick
        case ("datefolder", "interactive"):
            actionId = .datefolderInteractive
        case ("quickrename", "interactive"):
            actionId = .quickRename
        case ("quickrenamebatch", "interactive"):
            actionId = .quickRename
        default:
            AppLog.shared.log("未知的转发请求 module=\(module) args=\(args)", category: "Service", level: .warn)
            return
        }
        // 把 urls 设置到 state，HotKeyDispatcher 会读取 FinderSelection，但这里我们直接用转发来的 urls
        appState.preloadedURLs = urls
        // 通过 HotKeyDispatcher 触发对应动作
        Task { @MainActor in
            // 对于 compressQuick，HotKeyDispatcher 会再读 FinderSelection，可能读不到（因为 Finder 不在前台）
            // 所以直接调用内部逻辑
            switch actionId {
            case .compressQuick:
                HotKeyDispatcher.shared.dispatchQuickWithUrls(urls: urls)
            case .videoQuick:
                HotKeyDispatcher.shared.dispatchVideoQuickWithUrls(urls: urls)
            default:
                // compressInteractive / datefolderInteractive：直接弹窗，用转发来的 urls
                HotKeyDispatcher.shared.dispatchInteractiveWithUrls(urls: urls, actionId: actionId)
            }
        }
    }

    /// 服务菜单即用即走模式下，若压缩失败弹出了结果窗口，先等用户看完再退出进程
    private static func waitForResultWindowIfNeeded() async {
        let showing = await MainActor.run { CompressionResultWindowController.shared.isShowing }
        guard showing else { return }
        await MainActor.run {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        while true {
            let stillShowing = await MainActor.run {
                CompressionResultWindowController.shared.isShowing
            }
            if !stillShowing { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    /// 打开主窗口并切到指定功能页（圆环菜单等外部入口使用）
    func openModule(_ item: SidebarItem, urls: [URL] = []) {
        appState.preloadedURLs = urls
        appState.module = ""
        appState.moduleArgs = [:]
        appState.pendingSidebarItem = item
        showMainWindow()
    }

    /// 点击 Dock 图标 / 启动台重新打开 App 时：确保主窗口出现。
    /// 系统默认只激活「已有窗口」——中转站面板（常驻 NSPanel）存在时被判定为已有窗口，
    /// 不会新建主窗口，表现为 Dock 只亮点、无窗口可唤起。这里显式查找/新建主窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 交互弹窗显示中不重置 module，避免打断正在进行的操作
        let hasPopup = NSApp.windows.contains { $0.identifier?.rawValue == "InteractivePopup" && $0.isVisible }
        if !hasPopup {
            appState.preloadedURLs = []
            appState.module = ""
            appState.moduleArgs = [:]
        }
        showMainWindow()
        return true
    }

    @objc private func openSidebarItemFromStatusBar(_ note: Notification) {
        let raw = note.userInfo?["item"] as? String ?? ""
        guard let item = SidebarItem(rawValue: raw) else { return }
        appState.preloadedURLs = []
        appState.module = ""
        appState.moduleArgs = [:]
        appState.pendingSidebarItem = item
        showMainWindow()
    }

    /// 激活 App 并显示主窗口：已有则置前（含最小化还原），没有则新建
    private func showMainWindow() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = findMainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        createMainWindow()
    }

    /// 查找主窗口：normal 层级且可见（或最小化到 Dock），排除中转站面板/横条/交互弹窗
    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard window.isVisible || window.isMiniaturized else { return false }
            guard window.level == .normal else { return false }
            let id = window.identifier?.rawValue ?? ""
            return id != "ShelfPanel" && id != "ShelfMinimizedPanel" && id != "InteractivePopup"
        }
    }

    private func createMainWindow() {
        let hosting = NSHostingController(rootView: ContentView().environment(appState))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 1000, height: 800))
        window.styleMask = [.titled, .fullSizeContentView, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        if closingWindow.level == .screenSaver {
            // 弹窗窗口关闭：服务菜单进程 terminate / 主进程重置状态
            if isLaunchedByServiceMenu {
                AppLog.shared.log("服务菜单进程关窗口 → terminate", category: "App")
                NSApp.terminate(nil)
            } else {
                AppLog.shared.log("常驻主进程关弹窗 → 重置状态（保持 accessory）", category: "App")
                appState.preloadedURLs = []
                appState.module = ""
                appState.moduleArgs = [:]
            }
            return
        }

        // 主窗口（.normal level）关闭：
        // - 热键启用：切 accessory 模式（Dock 隐藏，菜单栏常驻作为入口）
        // - 热键未启用：保持 regular（Dock 保留图标，作为再次打开入口）
        if !isLaunchedByServiceMenu && NSApp.activationPolicy() == .regular {
            if appState.hotKeyEnabled {
                AppLog.shared.log("主窗口关闭 → 切回 accessory 模式（Dock 隐藏，菜单栏保留）", category: "App")
                NSApp.setActivationPolicy(.accessory)
            } else {
                AppLog.shared.log("主窗口关闭 → 保持 regular（热键未启用，Dock 保留入口）", category: "App")
            }
        }
    }

    /// 窗口成为 key 时设置 hidesOnDeactivate = false
    /// 确保主窗口在切到其他 app 时保持显示（用户手动打开设置后不应消失）
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let id = window.identifier?.rawValue ?? ""
        // 只处理主窗口（非 Shelf 面板/横条/弹窗）
        if id != "ShelfPanel" && id != "ShelfMinimizedPanel" && id != "InteractivePopup" && window.level == .normal {
            if window.hidesOnDeactivate {
                window.hidesOnDeactivate = false
                AppLog.shared.log("主窗口 hidesOnDeactivate 设为 false（切 app 时保持显示）", category: "App")
            }
        }
    }

    /// 防止最后一个窗口关闭时 App 自动退出（accessory 模式需要常驻）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// App 退出时清理中转站临时文件
    func applicationWillTerminate(_ notification: Notification) {
        let cleanupOnExit = UserDefaults.standard.object(forKey: "shelf_cleanup_on_exit") as? Bool ?? true
        if cleanupOnExit {
            ShelfStore.shared.cleanupUnlockedOnExit()
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        DispatchQueue.main.async {
            // 服务菜单启动时（module 非空）：文件已通过命令行参数传入，
            // openFiles 可能是 macOS 重复调用，不能覆盖 preloadedURLs
            //
            // 另外两种情况必须忽略，否则会同时出现「弹窗 + 主窗口」两块界面：
            // 1) 命令行带 --module —— 说明这次是服务/快捷键唤起，界面应该是弹窗
            // 2) 已经有弹窗在屏上 —— 说明弹窗流程已经在走，别再拉主窗口
            let launchedAsService = ProcessInfo.processInfo.arguments.contains("--module")
            let popupVisible = NSApp.windows.contains {
                $0.identifier?.rawValue == "InteractivePopup" && $0.isVisible
            }
            if self.appState.module.isEmpty && !launchedAsService && !popupVisible {
                self.appState.preloadedURLs = urls
                self.appState.module = "compress"
                self.appState.moduleArgs = ["mode": "interactive"]
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
