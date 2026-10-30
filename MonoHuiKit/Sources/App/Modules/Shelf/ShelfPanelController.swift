import AppKit
import SwiftUI

/// 中转站面板生命周期管理：显示/隐藏/自动隐藏/最小化状态机
final class ShelfPanelController {
    static let shared = ShelfPanelController()

    var panel: ShelfPanel?
    private var hostingController: NSHostingController<ShelfView>?

    /// 最小化横条 panel（10pt 宽）
    var minimizedPanel: ShelfMinimizedPanel?
    private var minimizedHosting: NSHostingController<ShelfMinimizedBar>?

    /// 是否处于最小化模式（横条显示，主 panel 隐藏）
    private(set) var isMinimized: Bool = false

    /// 最小化模式下是否临时展开（peek）
    private(set) var isPeeking: Bool = false

    /// peekCollapse 防抖时间戳：避免鼠标在横条边缘抖动导致 peek/collapse 循环
    private var lastPeekCollapseTime: Date = .distantPast

    /// 横条宽度（固定 10pt）
    let minimizedBarWidth: CGFloat = 10

    /// 自动隐藏延迟（秒）— 从 UserDefaults 读取，下限 0.3s 避免异常值
    private var autoHideDelay: TimeInterval {
        let raw = UserDefaults.standard.object(forKey: "shelf_auto_hide_delay") as? Double ?? 1.5
        return max(0.3, raw)
    }

    /// 面板宽度（显示状态）— 从 UserDefaults 读取，默认 140
    var panelWidth: CGFloat = 140 {
        didSet {
            UserDefaults.standard.set(Double(panelWidth), forKey: "shelf_panel_width")
        }
    }

    /// 隐藏时露出的边缘条宽度
    private let edgeBarWidth: CGFloat = 4

    /// 拖动触发显示的热区宽度：等于面板宽度，拖动到屏幕左侧 panelWidth 范围内即触发显示
    let dropHotZoneWidth: CGFloat = 140

    /// 屏幕切换防抖时间戳（鼠标监听 extension 使用）
    var lastScreenSwitchTime: Date = .distantPast

    /// 自动隐藏定时器
    private var autoHideTimer: Timer?

    /// 全局鼠标移动监听（用于检测鼠标靠近左边缘）
    var globalMouseMonitor: Any?

    /// 本地鼠标移动监听（用于检测鼠标离开面板）
    var localMouseMonitor: Any?

    /// 全局拖动监听（拖动文件到左边缘时显示面板）
    var globalDragMonitor: Any?

    /// 本地拖动监听（app 前台时拖动也能检测）
    var localDragMonitor: Any?

    /// 全局右键拖动监听（借鉴 Yoink：右键拖动也能唤起）
    var globalRightDragMonitor: Any?

    /// 全局鼠标松开监听（用于标记拖动结束，重置文件拖动判定）
    var globalMouseUpMonitor: Any?

    /// 当前拖动是否为文件拖动
    /// 每次 leftMouseUp 重置为 false，只有检测到 changeCount 变化且有文件 UTI 才置 true
    /// 这样能避免「上次拖动残留数据」被下次普通鼠标拖动误读
    var currentDragIsFile: Bool = false

    /// 上次记录的 drag pasteboard changeCount
    /// changeCount 变化 = 有新数据写入；不变 = 普通鼠标拖动（残留数据）
    var lastDragChangeCount: Int = 0

    /// 面板是否已显示
    private(set) var isShown: Bool = false

    /// 是否启用中转站
    private(set) var isEnabled: Bool = false

    /// 是否处于拖入中（拖入时暂停自动隐藏）
    var isDraggingOver: Bool = false {
        didSet {
            if isDraggingOver {
                cancelAutoHide()
            } else {
                scheduleAutoHide()
            }
        }
    }

    /// 隐藏动画 token：hidePanel 动画启动时记录，showPanel 时自增使旧隐藏回调失效
    private var hideAnimationToken: Int = 0

    /// 当前面板所在的屏幕
    var currentScreen: NSScreen?

    /// 当前是否正在从暂存箱内部拖动文件（区分内部拖动与外部拖入）
    /// 内部拖动时全局/本地拖动监听不应触发 showPanel，避免唤起新窗口
    /// 由 ShelfItemDragNSView.startDragSession 设置为 true，mouseUp/draggingSession 结束时重置
    var isDraggingFromSelf: Bool = false

    private init() {}

    // MARK: - 启用/禁用

    /// 当前面板在屏幕坐标系下的 frame（供外部弹窗定位用）
    /// 面板不存在或未显示时返回 nil
    var panelScreenFrame: NSRect? {
        guard let panel = panel, panel.isVisible else { return nil }
        return panel.frame
    }

    /// 启用中转站：创建面板但默认隐藏，仅拖动文件到左边缘时显示
    func enable() {
        guard !isEnabled else {
            AppLog.shared.log("中转站 enable() 被调用但已启用，跳过", category: "Shelf")
            return
        }
        isEnabled = true
        // 从 UserDefaults 读取用户配置的宽高
        if let storedW = UserDefaults.standard.object(forKey: "shelf_panel_width") as? Double {
            panelWidth = CGFloat(storedW)
        }
        // 初始化 drag pasteboard changeCount，避免首次普通鼠标拖动误触发
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        AppLog.shared.log("中转站 enable() 开始创建面板, activationPolicy=\(NSApp.activationPolicy().rawValue) panelWidth=\(panelWidth)", category: "Shelf")
        createPanel()
        // 默认隐藏（仅露边缘条），等待拖动触发显示
        hidePanel(animated: false)
        installMouseMonitors()
        installDragMonitors()
        AppLog.shared.log("中转站已启用，面板默认隐藏，isShown=\(isShown) panelWidth=\(panelWidth)", category: "Shelf")
    }

    /// 禁用中转站：隐藏并销毁面板
    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        uninstallMouseMonitors()
        uninstallDragMonitors()
        // 退出最小化状态
        isMinimized = false
        isPeeking = false
        hidePanel(animated: false)
        destroyPanel()
        AppLog.shared.log("中转站已禁用", category: "Shelf")
    }

    /// 切换启用状态
    func toggle() {
        if isEnabled { disable() } else { enable() }
    }

    /// 设置变化时重新调整面板（宽高等）
    /// 关键：setFrame 会触发 NSHostingView.updateConstraints → 反推窗口 frame → 再触发 setFrame，
    /// 形成无限递归崩溃。修复：先设置 hosting.preferredContentSize 为目标尺寸，
    /// 这样 SwiftUI 不会反推窗口 frame；然后用 NSAnimationContext 禁用动画后 setFrame
    func refreshPanel() {
        // 从 UserDefaults 同步最新宽高
        if let storedW = UserDefaults.standard.object(forKey: "shelf_panel_width") as? Double {
            panelWidth = CGFloat(storedW)
        }
        guard isEnabled, let panel = panel else { return }
        guard let screen = currentScreen ?? NSScreen.main else {
            AppLog.shared.log("refreshPanel: 无可用屏幕，跳过", category: "Shelf", level: .warn)
            return
        }
        let screenFrame = screen.visibleFrame
        // 从 UserDefaults 同步高度
        var height: CGFloat = 400
        if let storedH = UserDefaults.standard.object(forKey: "shelf_panel_height") as? Double {
            height = CGFloat(storedH)
        }
        height = min(height, screenFrame.height * 0.9)
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let newFrame = NSRect(x: screenFrame.origin.x, y: y, width: panelWidth, height: height)

        // 先设置 preferredContentSize 防止 SwiftUI 反推窗口尺寸
        if let hosting = hostingController {
            hosting.preferredContentSize = NSSize(width: panelWidth, height: height)
        }

        // 用 NSAnimationContext 禁用动画，避免 setFrame 动画过程中触发额外布局
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.setFrame(newFrame, display: true)
        }
        AppLog.shared.log("refreshPanel: 宽度=\(panelWidth) 高度=\(height)", category: "Shelf")
    }

    // MARK: - 面板创建

    /// 当前面板高度（从 UserDefaults 读取，默认 400）
    var currentPanelHeight: CGFloat {
        let stored = UserDefaults.standard.object(forKey: "shelf_panel_height") as? Double ?? 400
        return CGFloat(stored)
    }

    private func createPanel() {
        guard panel == nil else {
            AppLog.shared.log("createPanel: panel 已存在，跳过", category: "Shelf")
            return
        }
        // 关键：App 启动时使用主屏幕（包含菜单栏的屏幕，即 origin 为 (0,0) 的屏幕）创建面板
        // NSScreen.screens[0] 不一定是主屏幕，需要明确查找
        // 后续 showPanel 时会根据鼠标所在屏幕动态切换
        let screen = mainScreen()
        currentScreen = screen
        let screenFrame = screen.visibleFrame
        // 高度限制不超过屏幕高度的 90%
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        // 关键：初始 frame 直接设置为隐藏位置（屏幕外），避免先显示在可见位置再移走导致闪烁
        // 根据屏幕位置决定滑出方向，避免跨屏穿过
        let rect = calcHiddenFrame(for: screen, height: height)

        AppLog.shared.log("createPanel: screenFrame=\(screenFrame) rect=\(rect) height=\(height) panelWidth=\(panelWidth) screen=\(screen.localizedName)", category: "Shelf")

        let panel = ShelfPanel(contentRect: rect)
        let store = ShelfStore.shared
        let view = ShelfView(store: store)
        let hosting = NSHostingController(rootView: view)
        // 关键：设置 preferredContentSize 防止 SwiftUI 反推窗口尺寸为 0
        hosting.preferredContentSize = NSSize(width: panelWidth, height: height)
        panel.contentViewController = hosting
        // 强制设置 frame 为隐藏位置
        panel.setFrame(rect, display: true)
        // 关键：不调用 orderFrontRegardless，面板不进入窗口服务器，完全不可见
        // 之前 orderFrontRegardless 后即使 frame 在屏幕外，SwiftUI 异步反推或多显示器 origin 偏移
        // 会导致面板部分可见在错误位置（如另一个屏幕的右侧）
        // 等 showPanel 时再 orderFrontRegardless 显示
        self.panel = panel
        self.hostingController = hosting
        panel.clipScreen = screen
        isShown = false  // 初始即为隐藏状态
        AppLog.shared.log("createPanel: 面板已创建（未 orderFront，完全不可见），finalFrame=\(panel.frame)", category: "Shelf")
    }

    /// 查找主屏幕（包含菜单栏的屏幕，origin 为 (0,0)）
    private func mainScreen() -> NSScreen {
        // 打印所有屏幕信息便于调试
        for (idx, s) in NSScreen.screens.enumerated() {
            AppLog.shared.log("  screen[\(idx)] = \(s.localizedName) frame=\(s.frame) visibleFrame=\(s.visibleFrame)", category: "Shelf")
        }
        // 主屏幕的 frame.origin 通常是 (0, 0)
        if let main = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return main
        }
        // 兜底：screens[0]，再兜底 NSScreen.main
        return NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
    }

    private func destroyPanel() {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        minimizedPanel?.orderOut(nil)
        minimizedPanel = nil
        minimizedHosting = nil
    }

    // MARK: - 显示/隐藏（带动画）

    /// 显示面板（从左侧滑出）
    func showPanel(animated: Bool = true) {
        guard let panel = panel, isEnabled else {
            AppLog.shared.log("showPanel: 跳过（panel=\(panel == nil ? "nil" : "ok") isEnabled=\(isEnabled)）", category: "Shelf", level: .warn)
            return
        }
        // 使进行中的隐藏动画回调失效：若此前 hidePanel 动画尚未完成，其 completion
        // 不会再 orderOut 面板，避免「清空后立即隐藏 → 马上拖入 → 隐藏回调把新显示的面板又关掉」
        hideAnimationToken += 1
        cancelAutoHide()

        // 跟随当前鼠标所在屏幕（多显示器支持）
        let screen = mouseScreen() ?? currentScreen ?? NSScreen.main ?? mainScreen()
        currentScreen = screen
        panel.clipScreen = screen
        let screenFrame = screen.visibleFrame

        // 始终使用 UserDefaults 高度作为高度（避免 panel.frame.height 为 0 的bug）
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let targetFrame = NSRect(
            x: screenFrame.origin.x,
            y: y,
            width: panelWidth,
            height: height
        )

        AppLog.shared.log("showPanel: animated=\(animated) targetFrame=\(targetFrame) screen=\(screen.localizedName) height=\(height) panelWidth=\(panelWidth) isVisible=\(panel.isVisible)", category: "Shelf")

        // 关键：面板可能被 orderOut 完全隐藏，需要先 orderFrontRegardless 到隐藏位置，再动画滑出
        // 这样无论是跨屏切换还是从 orderOut 状态唤醒，都有从左侧滑出的动画效果
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        // 先无动画定位到隐藏位置（屏幕外），alphaValue=0 为淡入做准备
        // 用 CATransaction 确保 setFrame 立即生效，避免面板从旧屏幕滑到新屏幕
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(hiddenFrame, display: true, animate: false)
        panel.alphaValue = 0
        CATransaction.commit()
        // 先显示窗口（此时在屏幕外 + 透明，用户看不到）
        panel.orderFrontRegardless()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // 再用动画从隐藏位置滑出到显示位置，同步淡入
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.caDuration(Motion.Duration.standard * 1.45)
                ctx.timingFunction = Motion.caEnter
                panel.animator().setFrame(targetFrame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(targetFrame, display: true)
            panel.alphaValue = 1
        }
        isShown = true
        // 借鉴 Yoink：显示面板时清理已不存在的文件（可能被移到废纸篓）
        Task { @MainActor in
            ShelfStore.shared.cleanupMissingItems()
        }
        AppLog.shared.log("showPanel: 完成，isShown=true isVisible=\(panel.isVisible) finalFrame=\(panel.frame) itemsCount=\(ShelfStore.shared.items.count)", category: "Shelf")

        // 有文件时固定显示不隐藏；无文件时启动 1.5s 自动隐藏倒计时
        if !isDraggingOver {
            scheduleAutoHide()
        }
    }

    /// 隐藏面板（完全隐藏，不露边缘条）
    /// 无文件时完全 orderOut，拖动到左侧热区时由 handleDragEvent 触发 showPanel
    func hidePanel(animated: Bool = true) {
        guard let panel = panel, isEnabled else { return }
        // 最小化模式下由横条 panel 接管，不执行主 panel 隐藏
        if isMinimized { return }
        // 清空 pending 的自动隐藏 timer，避免清空后还有延迟隐藏干扰（如用户看到的"等 1.5s 才消失"）
        cancelAutoHide()

        let screen = currentScreen ?? NSScreen.main ?? mainScreen()
        panel.clipScreen = screen
        let screenFrame = screen.visibleFrame
        // 始终使用 currentPanelHeight 计算高度，避免 frame.height 为 0 时面板被压缩
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        // 完全移到屏幕外（不留边缘条），根据屏幕位置决定滑出方向
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        AppLog.shared.log("hidePanel: animated=\(animated) hiddenFrame=\(hiddenFrame) height=\(height) panelWidth=\(panelWidth)", category: "Shelf")

        // 与 showPanel 完全对称的滑出动画：0.35s 同时滑出 + 淡出，完成后隐藏
        if animated {
            let token = hideAnimationToken
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
                ctx.timingFunction = Motion.caStandard
                panel.animator().setFrame(hiddenFrame, display: true)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                // 若期间 showPanel 被调用（token 自增），不再 orderOut，避免关闭刚显示的面板
                guard self.hideAnimationToken == token else {
                    AppLog.shared.log("hidePanel: 隐藏动画期间面板被重新显示，跳过 orderOut", category: "Shelf")
                    return
                }
                panel.orderOut(nil)
                panel.alphaValue = 1
            })
        } else {
            panel.setFrame(hiddenFrame, display: true)
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
        isShown = false
    }

    // MARK: - 自动隐藏

    /// 启动自动隐藏倒计时（有文件时不隐藏，保持固定显示）
    func scheduleAutoHide() {
        cancelAutoHide()
        guard isShown, !isDraggingOver else {
            AppLog.shared.log("scheduleAutoHide: 跳过 isShown=\(isShown) isDraggingOver=\(isDraggingOver)", category: "Shelf", level: .warn)
            return
        }
        // 最小化模式下不启动自动隐藏（由横条 panel 接管）
        if isMinimized { return }
        // 有文件时固定显示，不启动隐藏
        if !ShelfStore.shared.items.isEmpty {
            AppLog.shared.log("scheduleAutoHide: 跳过（有 \(ShelfStore.shared.items.count) 个文件）", category: "Shelf")
            return
        }
        AppLog.shared.log("scheduleAutoHide: 启动 \(autoHideDelay)s 倒计时", category: "Shelf")
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                AppLog.shared.log("autoHideTimer: 触发，执行 hidePanel", category: "Shelf")
                self?.hidePanel(animated: true)
            }
        }
        // 关键：把 timer 加到 common 模式，避免 modal/session RunLoop 模式下不触发
        RunLoop.main.add(autoHideTimer!, forMode: .common)
    }

    func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    // MARK: - 最小化 / 临时展开 / 固定

    /// 最小化：主 panel 滑回 + orderOut，显示横条 panel
    /// 仅在有文件时允许（调用方应已检查）
    func minimize() {
        guard let panel = panel, isEnabled, !isMinimized else { return }
        guard !ShelfStore.shared.items.isEmpty else {
            AppLog.shared.log("minimize: 无文件，跳过", category: "Shelf", level: .warn)
            return
        }
        isMinimized = true
        isPeeking = false
        cancelAutoHide()
        // 通知 ShelfView 切换右上角按钮图标
        NotificationCenter.default.post(name: .shelfMinimizedChanged, object: nil)

        let screen = currentScreen ?? NSScreen.main ?? mainScreen()
        panel.clipScreen = screen
        // 用主面板实际 frame 高度，确保横条高度与面板完全一致
        let height = panel.frame.height
        let y = panel.frame.origin.y

        // 竖条等主面板滑出去之后再显示。
        // 之前是「动画一开始就显示」，于是主面板还在滑、右边边缘的竖条已经立在那儿了，看着很怪。
        // 现在放在 completion 里，和 orderOut 同一个 runloop，不会出现"面板没了 → 空白 → 竖条"的空窗。
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
            ctx.timingFunction = Motion.caStandard
            panel.animator().setFrame(hiddenFrame, display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.showMinimizedBar(screen: screen, y: y, height: height)
                panel.orderOut(nil)
                self?.isShown = false
                AppLog.shared.log("minimize: 已最小化为横条 height=\(height)", category: "Shelf")
            }
        })
    }

    /// 取消最小化：横条 panel 隐藏，主 panel 固定滑出
    func unminimize() {
        guard isEnabled, isMinimized else { return }
        let wasPeeking = isPeeking
        isMinimized = false
        isPeeking = false
        cancelAutoHide()
        // 通知 ShelfView 切换右上角按钮图标
        NotificationCenter.default.post(name: .shelfMinimizedChanged, object: nil)

        // 横条 panel 隐藏
        minimizedPanel?.orderOut(nil)

        if wasPeeking {
            // peek 状态下主 panel 已可见，直接固定在正确位置，无动画避免闪烁
            // 用 CATransaction 禁用隐式动画，防止中断 peekCollapse 残留动画导致闪烁
            isShown = true
            if let panel = panel {
                let screen = currentScreen ?? NSScreen.main ?? mainScreen()
                panel.clipScreen = screen
                let screenFrame = screen.visibleFrame
                let height = min(currentPanelHeight, screenFrame.height * 0.9)
                let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
                let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: panelWidth, height: height)

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                panel.setFrame(targetFrame, display: true, animate: false)
                panel.alphaValue = 1
                CATransaction.commit()

                if !panel.isVisible { panel.orderFrontRegardless() }
            }
        } else {
            // 非 peek 状态：主 panel 从屏幕外滑出
            showPanel(animated: true)
        }
        AppLog.shared.log("unminimize: 已固定显示 wasPeeking=\(wasPeeking)", category: "Shelf")
    }

    /// 最小化模式下临时展开（鼠标悬停横条触发）
    func peekExpand() {
        guard let panel = panel, isEnabled, isMinimized, !isPeeking else { return }
        // 防抖：peekCollapse 后 0.3s 内不响应 peekExpand
        let now = Date()
        if now.timeIntervalSince(lastPeekCollapseTime) < 0.3 { return }
        isPeeking = true
        // 通知 ShelfView 切换为 pin icon
        NotificationCenter.default.post(name: .shelfMinimizedChanged, object: nil)

        // 横条 panel 隐藏（主 panel 滑出会覆盖横条位置）
        minimizedPanel?.orderOut(nil)

        let screen = currentScreen ?? NSScreen.main ?? mainScreen()
        panel.clipScreen = screen
        let screenFrame = screen.visibleFrame
        // 用横条 panel 的实际高度（与主面板一致）
        let height = minimizedPanel?.frame.height ?? panel.frame.height
        let y = minimizedPanel?.frame.origin.y ?? panel.frame.origin.y
        let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: panelWidth, height: height)
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        // 先无动画定位到隐藏位置，再动画滑出，同步淡入
        panel.setFrame(hiddenFrame, display: true, animate: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isShown = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.caDuration(Motion.Duration.standard * 1.45)
            ctx.timingFunction = Motion.caEnter
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }
        AppLog.shared.log("peekExpand: 临时展开 height=\(height)", category: "Shelf")
    }

    /// 最小化模式下临时展开后缩回（鼠标离开主 panel 触发）
    func peekCollapse() {
        guard let panel = panel, isEnabled, isMinimized, isPeeking else { return }
        isPeeking = false
        lastPeekCollapseTime = Date()
        // 通知 ShelfView 切换回最小化按钮图标（但仍在最小化模式）
        NotificationCenter.default.post(name: .shelfMinimizedChanged, object: nil)

        let screen = currentScreen ?? NSScreen.main ?? mainScreen()
        panel.clipScreen = screen
        // 用主面板实际高度和位置
        let height = panel.frame.height
        let y = panel.frame.origin.y
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        // 竖条等主面板滑出去之后再显示（同 minimize）。
        // 之前动画一开始就显示，面板还在往左滑、右边边缘的竖条已经立着了，很突兀。
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
            ctx.timingFunction = Motion.caStandard
            panel.animator().setFrame(hiddenFrame, display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.showMinimizedBar(screen: screen, y: y, height: height)
                panel.orderOut(nil)
                self?.isShown = false
                AppLog.shared.log("peekCollapse: 缩回横条 height=\(height)", category: "Shelf")
            }
        })
    }

    /// 最小化模式下切换屏幕：横条 panel 或 peek 主 panel 跟随到新屏幕
    /// 纯滑动跨屏（保持旧屏 clipScreen 直到 Phase 2），与 relocatePanel 逻辑一致
    func relocateMinimized(to screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y

        if isPeeking, let panel = panel {
            // peek 中：主 panel A 屏滑出 → B 屏滑入
            let oldScreen = currentScreen
            currentScreen = screen
            if let oldScreen = oldScreen, oldScreen !== screen, panel.isVisible {
                // Phase 1：保持旧屏 clipScreen，主面板向左滑出旧屏
                panel.clipScreen = oldScreen
                let oldHeight = panel.frame.height
                let oldHiddenFrame = calcHiddenFrame(for: oldScreen, height: oldHeight)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
                    ctx.timingFunction = Motion.caStandard
                    panel.animator().setFrame(oldHiddenFrame, display: true)
                }, completionHandler: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Phase 2：切到新屏，无动画定位到隐藏位置，再滑入
                        panel.orderOut(nil)
                        panel.clipScreen = screen
                        let hiddenFrame = self.calcHiddenFrame(for: screen, height: height)
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        panel.setFrame(hiddenFrame, display: true, animate: false)
                        CATransaction.commit()
                        panel.orderFrontRegardless()
                        let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: self.panelWidth, height: height)
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = Motion.caDuration(Motion.Duration.standard * 1.45)
                            ctx.timingFunction = Motion.caEnter
                            panel.animator().setFrame(targetFrame, display: true)
                        }
                    }
                })
            } else {
                let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: panelWidth, height: height)
                panel.clipScreen = screen
                panel.setFrame(targetFrame, display: true, animate: false)
            }
        } else if let barPanel = minimizedPanel {
            // 横条模式：A 屏滑出 → B 屏滑入
            let oldScreen = currentScreen
            currentScreen = screen
            if let oldScreen = oldScreen, oldScreen !== screen, barPanel.isVisible {
                // Phase 1：保持旧屏 clipScreen，竖条向左滑出旧屏
                barPanel.clipScreen = oldScreen
                let oldHeight = barPanel.frame.height
                let oldHiddenFrame = calcMinimizedHiddenFrame(for: oldScreen, height: oldHeight)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
                    ctx.timingFunction = Motion.caStandard
                    barPanel.animator().setFrame(oldHiddenFrame, display: true)
                }, completionHandler: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Phase 2：切到新屏，无动画定位到隐藏位置，再滑入
                        barPanel.orderOut(nil)
                        barPanel.clipScreen = screen
                        let hiddenFrame = self.calcMinimizedHiddenFrame(for: screen, height: height)
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        barPanel.setFrame(hiddenFrame, display: true, animate: false)
                        CATransaction.commit()
                        barPanel.orderFrontRegardless()
                        let barFrame = NSRect(x: screenFrame.origin.x, y: y, width: self.minimizedBarWidth, height: height)
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = Motion.caDuration(Motion.Duration.standard * 1.45)
                            ctx.timingFunction = Motion.caEnter
                            barPanel.animator().setFrame(barFrame, display: true)
                        }
                    }
                })
            } else {
                let barFrame = NSRect(x: screenFrame.origin.x, y: y, width: minimizedBarWidth, height: height)
                barPanel.clipScreen = screen
                barPanel.setFrame(barFrame, display: true, animate: false)
            }
        }
    }

    /// 显示横条 panel（懒创建）
    private func showMinimizedBar(screen: NSScreen, y: CGFloat, height: CGFloat) {
        let screenFrame = screen.visibleFrame
        let barFrame = NSRect(x: screenFrame.origin.x, y: y, width: minimizedBarWidth, height: height)

        if let existing = minimizedPanel {
            existing.clipScreen = screen
            existing.setFrame(barFrame, display: true)
            if !existing.isVisible {
                existing.orderFrontRegardless()
            }
        } else {
            let bar = ShelfMinimizedPanel(contentRect: barFrame)
            bar.clipScreen = screen
            let view = ShelfMinimizedBar()
            let hosting = NSHostingController(rootView: view)
            hosting.preferredContentSize = NSSize(width: minimizedBarWidth, height: height)
            bar.contentViewController = hosting
            bar.setFrame(barFrame, display: true)
            minimizedPanel = bar
            minimizedHosting = hosting
            bar.orderFrontRegardless()
        }
    }
}
