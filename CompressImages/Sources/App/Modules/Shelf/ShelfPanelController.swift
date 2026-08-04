import AppKit
import SwiftUI

/// 中转站面板生命周期管理：显示/隐藏/自动隐藏/最小化状态机
final class ShelfPanelController {
    static let shared = ShelfPanelController()

    private var panel: ShelfPanel?
    private var hostingController: NSHostingController<ShelfView>?

    /// 最小化横条 panel（10pt 宽）
    private var minimizedPanel: ShelfMinimizedPanel?
    private var minimizedHosting: NSHostingController<ShelfMinimizedBar>?

    /// 是否处于最小化模式（横条显示，主 panel 隐藏）
    private(set) var isMinimized: Bool = false

    /// 最小化模式下是否临时展开（peek）
    private(set) var isPeeking: Bool = false

    /// peekCollapse 防抖时间戳：避免鼠标在横条边缘抖动导致 peek/collapse 循环
    private var lastPeekCollapseTime: Date = .distantPast

    /// 横条宽度（固定 10pt）
    private let minimizedBarWidth: CGFloat = 10

    /// 自动隐藏延迟（秒）— 从 UserDefaults 读取
    private var autoHideDelay: TimeInterval {
        UserDefaults.standard.object(forKey: "shelf_auto_hide_delay") as? Double ?? 1.5
    }

    /// 面板宽度（显示状态）— 从 UserDefaults 读取，默认 140
    private var panelWidth: CGFloat = 140 {
        didSet {
            UserDefaults.standard.set(Double(panelWidth), forKey: "shelf_panel_width")
        }
    }

    /// 隐藏时露出的边缘条宽度
    private let edgeBarWidth: CGFloat = 4

    /// 拖动触发显示的热区宽度：等于面板宽度，拖动到屏幕左侧 panelWidth 范围内即触发显示
    private let dropHotZoneWidth: CGFloat = 140

    /// 自动隐藏定时器
    private var autoHideTimer: Timer?

    /// 全局鼠标移动监听（用于检测鼠标靠近左边缘）
    private var globalMouseMonitor: Any?

    /// 本地鼠标移动监听（用于检测鼠标离开面板）
    private var localMouseMonitor: Any?

    /// 全局拖动监听（拖动文件到左边缘时显示面板）
    private var globalDragMonitor: Any?

    /// 本地拖动监听（app 前台时拖动也能检测）
    private var localDragMonitor: Any?

    /// 全局右键拖动监听（借鉴 Yoink：右键拖动也能唤起）
    private var globalRightDragMonitor: Any?

    /// 全局鼠标松开监听（用于标记拖动结束，重置文件拖动判定）
    private var globalMouseUpMonitor: Any?

    /// 当前拖动是否为文件拖动
    /// 每次 leftMouseUp 重置为 false，只有检测到 changeCount 变化且有文件 UTI 才置 true
    /// 这样能避免「上次拖动残留数据」被下次普通鼠标拖动误读
    private var currentDragIsFile: Bool = false

    /// 上次记录的 drag pasteboard changeCount
    /// changeCount 变化 = 有新数据写入；不变 = 普通鼠标拖动（残留数据）
    private var lastDragChangeCount: Int = 0

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

    /// 当前面板所在的屏幕
    private var currentScreen: NSScreen?

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
    private var currentPanelHeight: CGFloat {
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
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
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
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
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

        let screen = currentScreen ?? NSScreen.main ?? mainScreen()
        panel.clipScreen = screen
        let screenFrame = screen.visibleFrame
        // 始终使用 currentPanelHeight 计算高度，避免 frame.height 为 0 时面板被压缩
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        // 完全移到屏幕外（不留边缘条），根据屏幕位置决定滑出方向
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        AppLog.shared.log("hidePanel: animated=\(animated) hiddenFrame=\(hiddenFrame) height=\(height) panelWidth=\(panelWidth)", category: "Shelf")

        // alpha 快速淡出（0.2s）让面板在滑出屏幕边缘前就消失
        // frame 慢慢滑出（0.35s）保留滑动动效，两个动画并行
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                panel.animator().alphaValue = 0
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                panel.animator().setFrame(hiddenFrame, display: true)
            }, completionHandler: {
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
        guard isShown, !isDraggingOver else { return }
        // 最小化模式下不启动自动隐藏（由横条 panel 接管）
        if isMinimized { return }
        // 有文件时固定显示，不启动隐藏
        if !ShelfStore.shared.items.isEmpty {
            return
        }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hidePanel(animated: true)
            }
        }
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
        let screenFrame = screen.visibleFrame
        // 用主面板实际 frame 高度，确保横条高度与面板完全一致
        let height = panel.frame.height
        let y = panel.frame.origin.y

        // 主 panel 向左滑出屏幕（mask 同步机制裁剪跨屏部分，不淡出 alpha 让滑动可见）
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(hiddenFrame, display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                panel.orderOut(nil)
                self?.isShown = false
                self?.showMinimizedBar(screen: screen, y: y, height: height)
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
    private func peekExpand() {
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
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }
        AppLog.shared.log("peekExpand: 临时展开 height=\(height)", category: "Shelf")
    }

    /// 最小化模式下临时展开后缩回（鼠标离开主 panel 触发）
    private func peekCollapse() {
        guard let panel = panel, isEnabled, isMinimized, isPeeking else { return }
        isPeeking = false
        lastPeekCollapseTime = Date()
        // 通知 ShelfView 切换回最小化按钮图标（但仍在最小化模式）
        NotificationCenter.default.post(name: .shelfMinimizedChanged, object: nil)

        let screen = currentScreen ?? NSScreen.main ?? mainScreen()
        panel.clipScreen = screen
        let screenFrame = screen.visibleFrame
        // 用主面板实际高度和位置
        let height = panel.frame.height
        let y = panel.frame.origin.y
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        // 主 panel 向左滑出屏幕（mask 同步机制裁剪跨屏部分，不淡出 alpha 让滑动可见）
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(hiddenFrame, display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                panel.orderOut(nil)
                self?.isShown = false
                self?.showMinimizedBar(screen: screen, y: y, height: height)
                AppLog.shared.log("peekCollapse: 缩回横条 height=\(height)", category: "Shelf")
            }
        })
    }

    /// 最小化模式下切换屏幕：横条 panel 或 peek 主 panel 跟随到新屏幕
    private func relocateMinimized(to screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y

        if isPeeking, let panel = panel {
            // peek 中：主 panel A 屏滑出 → B 屏滑入
            let oldScreen = currentScreen
            currentScreen = screen
            if let oldScreen = oldScreen, oldScreen !== screen, panel.isVisible {
                // A 屏先滑出隐藏（alpha 快速淡出 0.2s，frame 慢慢滑出 0.25s）
                let oldHeight = panel.frame.height
                let oldHiddenFrame = calcHiddenFrame(for: oldScreen, height: oldHeight)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                    panel.animator().alphaValue = 0
                }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                    panel.animator().setFrame(oldHiddenFrame, display: true)
                }, completionHandler: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        panel.orderOut(nil)
                        panel.alphaValue = 1
                        let hiddenFrame = self.calcHiddenFrame(for: screen, height: height)
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        panel.setFrame(hiddenFrame, display: true, animate: false)
                        panel.alphaValue = 0
                        CATransaction.commit()
                        panel.orderFrontRegardless()
                        let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: self.panelWidth, height: height)
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.35
                            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                            panel.animator().setFrame(targetFrame, display: true)
                            panel.animator().alphaValue = 1
                        }
                    }
                })
            } else {
                let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: panelWidth, height: height)
                panel.setFrame(targetFrame, display: true, animate: false)
            }
        } else if let barPanel = minimizedPanel {
            // 横条模式：A 屏滑出 → B 屏滑入
            let oldScreen = currentScreen
            currentScreen = screen
            if let oldScreen = oldScreen, oldScreen !== screen, barPanel.isVisible {
                // A 屏横条先滑出隐藏（alpha 快速淡出 0.2s，frame 慢慢滑出 0.25s）
                let oldHeight = barPanel.frame.height
                let oldHiddenFrame = calcMinimizedHiddenFrame(for: oldScreen, height: oldHeight)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                    barPanel.animator().alphaValue = 0
                }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                    barPanel.animator().setFrame(oldHiddenFrame, display: true)
                }, completionHandler: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        barPanel.orderOut(nil)
                        barPanel.alphaValue = 1
                        let hiddenFrame = self.calcMinimizedHiddenFrame(for: screen, height: height)
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        barPanel.setFrame(hiddenFrame, display: true, animate: false)
                        barPanel.alphaValue = 0
                        CATransaction.commit()
                        barPanel.orderFrontRegardless()
                        let barFrame = NSRect(x: screenFrame.origin.x, y: y, width: self.minimizedBarWidth, height: height)
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.35
                            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                            barPanel.animator().setFrame(barFrame, display: true)
                            barPanel.animator().alphaValue = 1
                        }
                    }
                })
            } else {
                let barFrame = NSRect(x: screenFrame.origin.x, y: y, width: minimizedBarWidth, height: height)
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

    // MARK: - 鼠标监听

    /// 屏幕切换防抖时间戳
    private var lastScreenSwitchTime: Date = .distantPast

    private func installMouseMonitors() {
        // 全局鼠标移动监听：检测鼠标所在屏幕变化，面板显示且有文件时跟随切换
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleGlobalMouseMoved(event: event)
        }
        // 本地鼠标移动监听：检测鼠标离开面板后启动隐藏 + 屏幕切换
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleLocalMouseMoved(event: event)
            return event
        }
        AppLog.shared.log("installMouseMonitors: 全局+本地鼠标监听已安装（屏幕跟随+离开隐藏）", category: "Shelf")
    }

    private func uninstallMouseMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    /// 全局鼠标移动：检测鼠标所在屏幕变化，面板显示且有文件时跟随切换到新屏幕
    private func handleGlobalMouseMoved(event: NSEvent) {
        guard isEnabled else { return }
        // 最小化模式下：先处理屏幕跟随，再处理 peek hover
        if isMinimized {
            // 屏幕跟随：鼠标所在屏幕变化时，横条/peek panel 跟随到新屏幕
            if !ShelfStore.shared.items.isEmpty {
                let now = Date()
                if now.timeIntervalSince(lastScreenSwitchTime) >= 0.5 {
                    if let newScreen = mouseScreen(), currentScreen !== newScreen {
                        lastScreenSwitchTime = now
                        currentScreen = newScreen
                        relocateMinimized(to: newScreen)
                        AppLog.shared.log("最小化模式切换屏幕：→ \(newScreen.localizedName)", category: "Shelf")
                    }
                }
            }
            handleMinimizedHover()
            return
        }
        guard isShown else { return }
        // 无文件时不跟随（隐藏中或即将隐藏）
        guard !ShelfStore.shared.items.isEmpty else { return }
        // 拖动中不切换（由 handleDragEvent 接管）
        guard !isDraggingOver else { return }
        // 防抖：500ms 内只切换一次，避免鼠标在屏幕边界抖动反复切换
        let now = Date()
        if now.timeIntervalSince(lastScreenSwitchTime) < 0.5 { return }

        guard let newScreen = mouseScreen() else { return }
        // 仅当鼠标所在屏幕与当前面板所在屏幕不同时切换
        guard currentScreen !== newScreen else { return }

        lastScreenSwitchTime = now
        relocatePanel(to: newScreen, animated: true)
        AppLog.shared.log("鼠标切换屏幕：\(currentScreen?.localizedName ?? "nil") → \(newScreen.localizedName)", category: "Shelf")
    }

    /// 本地鼠标移动：检测鼠标离开面板区域 + 屏幕跟随
    private func handleLocalMouseMoved(event: NSEvent) {
        guard isEnabled else { return }
        // 最小化模式下优先处理 peek 触发/缩回
        if isMinimized {
            handleMinimizedHover()
            return
        }
        guard isShown, !isDraggingOver else { return }
        guard let panel = panel else { return }
        let mouseLoc = NSEvent.mouseLocation

        // 屏幕跟随（本地事件也能触发，覆盖 app 内鼠标移动场景）
        if !ShelfStore.shared.items.isEmpty {
            let now = Date()
            if now.timeIntervalSince(lastScreenSwitchTime) >= 0.5 {
                if let newScreen = mouseScreen(), currentScreen !== newScreen {
                    lastScreenSwitchTime = now
                    relocatePanel(to: newScreen, animated: true)
                    AppLog.shared.log("本地鼠标切换屏幕：\(currentScreen?.localizedName ?? "nil") → \(newScreen.localizedName)", category: "Shelf")
                    return
                }
            }
        }

        let panelFrame = panel.frame
        if !NSMouseInRect(mouseLoc, panelFrame, false) {
            // 鼠标离开面板，启动自动隐藏倒计时（内部会判断文件数）
            scheduleAutoHide()
        } else {
            // 鼠标在面板内，取消自动隐藏
            cancelAutoHide()
        }
    }

    /// 最小化模式下的鼠标 hover 处理：
    /// - 鼠标在横条 frame 内且未 peek → peekExpand
    /// - 鼠标离开主 panel frame 且离开横条 frame 且正在 peek → peekCollapse
    private func handleMinimizedHover() {
        let mouseLoc = NSEvent.mouseLocation
        if !isPeeking {
            // 横条显示中，鼠标进入横条 → peek 展开
            if let barPanel = minimizedPanel, NSMouseInRect(mouseLoc, barPanel.frame, false) {
                peekExpand()
            }
        } else {
            // peek 展开中，鼠标离开主 panel 且离开横条 → peek 缩回
            guard let panel = panel else { return }
            let inMain = NSMouseInRect(mouseLoc, panel.frame, false)
            let inBar: Bool
            if let barPanel = minimizedPanel {
                inBar = NSMouseInRect(mouseLoc, barPanel.frame, false)
            } else {
                inBar = false
            }
            if !inMain && !inBar {
                peekCollapse()
            }
        }
    }

    /// 把面板重新定位到指定屏幕
    /// 跨屏切换：A 屏先滑出隐藏（动画向左滑出屏幕）→ 再在 B 屏滑入出现（从左侧滑出）
    /// 整个过程面板不出现在屏幕间区域，避免闪烁
    private func relocatePanel(to screen: NSScreen, animated: Bool) {
        guard let panel = panel else { return }
        let oldScreen = currentScreen
        currentScreen = screen

        let screenFrame = screen.visibleFrame
        let height = min(currentPanelHeight, screenFrame.height * 0.9)
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let targetFrame = NSRect(x: screenFrame.origin.x, y: y, width: panelWidth, height: height)
        let hiddenFrame = calcHiddenFrame(for: screen, height: height)

        if !animated {
            // 无动画：直接定位
            panel.clipScreen = screen
            panel.setFrame(hiddenFrame, display: true, animate: false)
            panel.orderFrontRegardless()
            panel.setFrame(targetFrame, display: true)
            return
        }

        // Phase 1：A 屏先滑出隐藏（alpha 快速淡出 0.2s，frame 慢慢滑出 0.25s）
        if let oldScreen = oldScreen, oldScreen !== screen, panel.isVisible {
            // 关键：Phase 1 期间保持 clipScreen 为旧屏
            // 面板向左滑出旧屏时，会进入新屏的右侧边界区域
            // 若此时 clipScreen 已切到新屏，mask 会显示这部分，造成新屏右侧残影
            // 保持旧屏 clipScreen 可让 mask 裁掉超出旧屏的部分
            panel.clipScreen = oldScreen

            let oldHeight = panel.frame.height
            let oldHiddenFrame = calcHiddenFrame(for: oldScreen, height: oldHeight)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                panel.animator().alphaValue = 0
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                panel.animator().setFrame(oldHiddenFrame, display: true)
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // Phase 2：orderOut 隐藏，切换 clipScreen 到新屏，无动画定位到新屏隐藏位置
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                    panel.clipScreen = screen
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    panel.setFrame(hiddenFrame, display: true, animate: false)
                    panel.alphaValue = 0
                    CATransaction.commit()
                    panel.orderFrontRegardless()
                    // Phase 3：新屏滑入出现（同步淡入）
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.35
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                        panel.animator().setFrame(targetFrame, display: true)
                        panel.animator().alphaValue = 1
                    }
                    AppLog.shared.log("relocatePanel: A 屏滑出 → B 屏滑入 \(screen.localizedName)", category: "Shelf")
                }
            })
        } else {
            // 同屏或首次：先 orderOut 隐藏（避免可见时 setFrame 跨屏飞行），再无动画定位到隐藏位置，再滑入
            panel.clipScreen = screen
            if panel.isVisible {
                panel.orderOut(nil)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.setFrame(hiddenFrame, display: true, animate: false)
            panel.alphaValue = 0
            CATransaction.commit()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                panel.animator().setFrame(targetFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }
    }

    // MARK: - 拖动监听

    private func installDragMonitors() {
        guard globalDragMonitor == nil else { return }
        // 全局左键拖动监听（其他 app 拖动时检测）
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
        }
        // 本地左键拖动监听（本 app 拖动时也检测）
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDragEvent(event)
            return event
        }
        // 全局右键拖动监听（借鉴 Yoink：右键拖动也能唤起中转站）
        globalRightDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
        }
        // 全局鼠标松开监听：拖动结束后重置状态
        // - 重置 currentDragIsFile 为 false，避免残留数据误触发
        // - 重置 isDraggingOver 为 false，让文件已全部拖出时能启动自动隐藏
        // - 若暂存箱已无文件，主动触发自动隐藏倒计时
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            self.currentDragIsFile = false
            // 重置内部拖动标志，确保下次外部拖入能正常触发
            self.isDraggingFromSelf = false
            if self.isDraggingOver {
                self.isDraggingOver = false
                // 拖动结束且暂存箱已空：触发自动隐藏
                if ShelfStore.shared.items.isEmpty {
                    self.scheduleAutoHide()
                }
            }
        }
        AppLog.shared.log("installDragMonitors: 全局+本地+右键拖动+鼠标松开监听已安装", category: "Shelf")
    }

    private func uninstallDragMonitors() {
        if let monitor = globalDragMonitor {
            NSEvent.removeMonitor(monitor)
            globalDragMonitor = nil
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
            localDragMonitor = nil
        }
        if let monitor = globalRightDragMonitor {
            NSEvent.removeMonitor(monitor)
            globalRightDragMonitor = nil
        }
        if let monitor = globalMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseUpMonitor = nil
        }
    }

    private func handleDragEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        // 内部拖动（从暂存箱拖出文件到压缩区/AirDrop区等）不触发 showPanel
        // 避免拖动文件时误唤起新窗口
        guard !isDraggingFromSelf else { return }
        // 精细化判定：仅当拖动粘贴板包含明确的文件/图像/PDF 类型 UTI 时才触发
        // 避免按空格拖动画板、纯文本拖动、pasteboard 残留数据等场景误触发面板
        // 普通鼠标拖动（无文件）的 pasteboard 类型通常不包含强信号文件 UTI
        guard isFileDrag() else { return }

        let mouseLoc = NSEvent.mouseLocation
        if isAtLeftEdge(mouseLoc) {
            if !isShown {
                // 最小化模式下拖动到左边缘：先取消最小化，让主 panel 滑出接收文件
                if isMinimized {
                    unminimize()
                } else {
                    AppLog.shared.log("handleDragEvent: 拖动到左边缘，显示面板", category: "Shelf")
                    showPanel(animated: true)
                }
            }
            isDraggingOver = true
        } else if isShown && isDraggingOver {
            // 拖动离开左边缘热区，但仍在面板范围内则保持
            guard let panel = panel else { return }
            if !NSMouseInRect(mouseLoc, panel.frame, false) {
                isDraggingOver = false
                // 拖动离开面板且暂存箱为空：启动自动隐藏
                if ShelfStore.shared.items.isEmpty {
                    scheduleAutoHide()
                }
            }
        }
    }

    /// 判断当前拖动是否为文件/图像/PDF 拖动
    /// 核心机制：用 pasteboard.changeCount 区分「新拖动写入的数据」和「上次拖动残留的数据」
    /// - 文件拖动：拖动源在 drag session 开始时写入 drag pasteboard，changeCount 递增
    /// - 普通鼠标拖动（无数据）：不写入 drag pasteboard，changeCount 不变
    /// - 残留数据：上次拖动结束后 pasteboard 数据不清空，但 changeCount 不会再变
    ///
    /// 每次 leftMouseDragged 都检查 changeCount：
    /// - 变化 = 有新数据写入 → 重新判定 UTI 白名单，更新 currentDragIsFile
    /// - 不变 = 无新数据 → 复用 currentDragIsFile（已被 leftMouseUp 重置为 false）
    ///
    /// 这样 PS/AI 等应用即使写入数据晚于第一个 drag 事件，也能在后续事件中被检测到
    private func isFileDrag() -> Bool {
        let dragPboard = NSPasteboard(name: .drag)
        let currentChangeCount = dragPboard.changeCount

        // changeCount 变化 = 有新数据写入，重新判定文件类型
        if currentChangeCount != lastDragChangeCount {
            lastDragChangeCount = currentChangeCount
            currentDragIsFile = checkFileUTIs(dragPboard)
        }
        // changeCount 不变 = 无新数据，复用 currentDragIsFile
        // leftMouseUp 已将 currentDragIsFile 重置为 false，所以普通鼠标拖动返回 false
        return currentDragIsFile
    }

    /// 检查 drag pasteboard 是否包含强信号文件 UTI
    private func checkFileUTIs(_ pboard: NSPasteboard) -> Bool {
        guard let types = pboard.types, !types.isEmpty else { return false }

        // 强信号文件 UTI 白名单：明确的文件/图像/PDF/目录类型
        let strongFileUTIs: Set<String> = [
            "public.file-url",                  // Finder 拖文件（最核心）
            "public.url",                       // PS/AI/Figma 拖出设计内容
            "public.image",                     // 通用图像
            "public.png",
            "public.jpeg",
            "public.tiff",
            "com.compuserver.gif",
            "public.svg-image",                 // SVG 文件
            "image/svg+xml",
            "com.adobe.pdf",                    // PDF
            "com.adobe.illustrator.ai-image",   // AI 文件
            "com.adobe.photoshop-image",        // PSD 文件
            "public.zip-archive",               // ZIP 压缩包
            "public.folder",                    // 文件夹
            "public.directory",                 // 目录
        ]

        let isFile = types.contains { strongFileUTIs.contains($0.rawValue) }
        if !isFile {
            AppLog.shared.log("checkFileUTIs: changeCount 变化但非文件 UTI，UTIs=\(types.map { $0.rawValue })", category: "Shelf", level: .info)
        }
        return isFile
    }

    /// 判断鼠标是否在任意屏幕的左边缘热区内
    private func isAtLeftEdge(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens {
            let frame = screen.visibleFrame
            if point.x >= frame.origin.x - 2 &&
               point.x <= frame.origin.x + dropHotZoneWidth &&
               point.y >= frame.origin.y &&
               point.y <= frame.origin.y + frame.height {
                return true
            }
        }
        return false
    }

    /// 获取鼠标所在的屏幕
    private func mouseScreen() -> NSScreen? {
        let mouseLoc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLoc, screen.frame, false) {
                return screen
            }
        }
        return nil
    }

    /// 计算主面板在指定屏幕上的隐藏 frame（总是向左滑出）
    /// 动画过程同步 alphaValue 淡出避免穿过相邻屏幕
    private func calcHiddenFrame(for screen: NSScreen, height: CGFloat) -> NSRect {
        let screenFrame = screen.visibleFrame
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let hiddenX = screenFrame.origin.x - panelWidth
        return NSRect(x: hiddenX, y: y, width: panelWidth, height: height)
    }

    /// 计算横条面板在指定屏幕上的隐藏 frame（总是向左滑出）
    private func calcMinimizedHiddenFrame(for screen: NSScreen, height: CGFloat) -> NSRect {
        let screenFrame = screen.visibleFrame
        let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
        let hiddenX = screenFrame.origin.x - minimizedBarWidth
        return NSRect(x: hiddenX, y: y, width: minimizedBarWidth, height: height)
    }

    // MARK: - 鼠标进出面板（供 ShelfView 调用）

    /// 鼠标进入面板区域：取消自动隐藏
    func handleMouseEntered() {
        cancelAutoHide()
    }

    /// 鼠标离开面板区域：启动自动隐藏
    func handleMouseExited() {
        scheduleAutoHide()
    }
}
