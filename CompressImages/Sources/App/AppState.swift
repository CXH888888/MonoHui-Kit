import Foundation
import Observation
import SwiftUI

@Observable
final class AppState {
    var preloadedURLs: [URL] = []
    var module: String = ""
    var moduleArgs: [String: String] = [:]
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

    // 全局快捷键开关。启用后 App 驻留菜单栏，监听全局热键。
    var hotKeyEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(hotKeyEnabled, forKey: "hotkey_enabled")
            applyHotKeyEnabled()
        }
    }

    init() {
        UserDefaults.standard.register(defaults: [
            "quality": QualityLevel.high.rawValue,
            "format": CompressionFormat.jpeg.rawValue,
            "keepOriginalFormat": true,
            "quickQuality": QualityLevel.high.rawValue,
            "quickFormat": CompressionFormat.jpeg.rawValue,
            "quickKeepOriginal": true
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

        // 注意：hotKeyEnabled 在 AppDelegate.applicationDidFinishLaunching 中按需启用，
        // 不在 init 里启用——避免服务菜单触发（即用即走）时也意外驻留。
        hotKeyEnabled = UserDefaults.standard.object(forKey: "hotkey_enabled") as? Bool ?? false

        // 提前解析启动参数，确保 ContentView 第一次渲染时就能拿到正确的 module/mode
        parseLaunchArgs()
    }

    /// 应用快捷键启用状态：注册/注销热键 + 菜单栏图标 + 激活策略
    func applyHotKeyEnabled() {
        AppLog.shared.log("applyHotKeyEnabled hotKeyEnabled=\(hotKeyEnabled) module=\(module)", category: "App")
        if hotKeyEnabled {
            // 启用 Finder 激活/失活监听：Finder 激活时注册热键，其他 App 激活时注销
            HotKeyManager.shared.installFinderWatcher()
            // 如果当前 Finder 已在前台，立即注册（installFinderWatcher 内部也会判断）
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
                HotKeyManager.shared.registerAllFromSettings()
            }
            StatusBarController.shared.show()
            // 仅当不是服务菜单触发（无 module）时才切换激活策略
            if module.isEmpty {
                NSApp.setActivationPolicy(.accessory)
                AppLog.shared.log("切换到 accessory 模式（Dock 图标隐藏）", category: "App")
            }
        } else {
            HotKeyManager.shared.unregisterAll()
            StatusBarController.shared.hide()
            if module.isEmpty {
                NSApp.setActivationPolicy(.regular)
                AppLog.shared.log("切换到 regular 模式", category: "App")
            }
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
                try? await Task.sleep(nanoseconds: 1_500_000_000)
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

        // 监听菜单栏"打开设置"通知：accessory 模式下重新打开主窗口
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsFromStatusBar),
            name: .openSettingsFromStatusBar,
            object: nil
        )

        // 主进程订阅服务菜单转发通知：服务菜单新进程把请求转发过来，由主进程处理
        ServiceBridge.subscribe { [weak self] module, args, urls in
            guard let self = self else { return }
            self.handleServiceBridgeRequest(module: module, args: args, urls: urls)
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

    /// 处理服务菜单转发来的请求（主进程收到后调 HotKeyDispatcher）
    private func handleServiceBridgeRequest(module: String, args: [String: String], urls: [URL]) {
        AppLog.shared.log("处理转发请求 module=\(module) args=\(args) urls=\(urls.count)", category: "Service")
        let actionId: HotKeyActionId
        switch (module, args["mode"]) {
        case ("compress", "quick"):
            actionId = .compressQuick
        case ("compress", "interactive"):
            actionId = .compressInteractive
        case ("datefolder", "interactive"):
            actionId = .datefolderInteractive
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
            if actionId == .compressQuick {
                HotKeyDispatcher.shared.dispatchQuickWithUrls(urls: urls)
            } else {
                // compressInteractive / datefolderInteractive：直接弹窗，用转发来的 urls
                HotKeyDispatcher.shared.dispatchInteractiveWithUrls(urls: urls, actionId: actionId)
            }
        }
    }

    @objc private func openSettingsFromStatusBar() {
        // 重置 module，让 ContentView 显示主界面
        appState.preloadedURLs = []
        appState.module = ""
        appState.moduleArgs = [:]

        // 如果已有窗口，直接激活
        if !NSApp.windows.isEmpty {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        // accessory 模式下无窗口：创建主窗口
        let hosting = NSHostingController(rootView: ContentView().environment(appState))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 1000, height: 800))
        window.styleMask = [.titled, .fullSizeContentView, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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

        // 主窗口（.normal level）关闭：切回 accessory 模式，保留菜单栏常驻
        // Dock 图标隐藏，但 App 不退出
        if !isLaunchedByServiceMenu && NSApp.activationPolicy() == .regular {
            AppLog.shared.log("主窗口关闭 → 切回 accessory 模式（Dock 隐藏，菜单栏保留）", category: "App")
            NSApp.setActivationPolicy(.accessory)
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
            if self.appState.module.isEmpty {
                self.appState.preloadedURLs = urls
                self.appState.module = "compress"
                self.appState.moduleArgs = ["mode": "interactive"]
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
