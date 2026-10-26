import AppKit
import SwiftUI

/// 圆环菜单的窗口与交互控制器。
///
/// 触发模型（零新增权限）：
/// 1. 按住快捷键 → Carbon 热键回调 → 在光标处淡入圆环
/// 2. 60Hz 轮询 `NSEvent.mouseLocation` 决定高亮扇区
/// 3. 松开快捷键的修饰键 → 执行；回到中心或按 Esc → 取消
///
/// 不用 CGEventTap，因此不需要「输入监控」授权；只读取全局鼠标位置与修饰键状态。
@MainActor
final class RadialMenuController {
    static let shared = RadialMenuController()

    private var panel: NSPanel?
    private var effectView: NSVisualEffectView?
    /// 用于取消上一次关闭过程中未跑完的材质淡出帧
    private var fadeToken = 0
    private let model = RadialMenuModel()
    private var metrics = RadialMenuMetrics.current()
    private var timer: Timer?
    private var urls: [URL] = []
    private var triggerModifiers: NSEvent.ModifierFlags = []
    private var initialMouse: CGPoint = .zero
    private var startedAt = Date()
    private var isOpen = false
    private var sessionID = UUID()

    private let relevantFlags: NSEvent.ModifierFlags = [.option, .shift, .command, .control]

    private init() {}

    var isShowing: Bool { isOpen }

    /// 唤出圆环。urls 随后通过 `updateURLs` 异步补上，避免等 AppleScript 读完选中项才显示。
    func show(modifiers: NSEvent.ModifierFlags, force: Bool = false) {
        guard force || RadialMenuSettings.shared.enabled else { return }
        // 长按快捷键时系统可能重复投递热键事件，已在显示中就直接忽略，避免圆环反复重建
        guard !isOpen else { return }

        sessionID = UUID()
        let settings = RadialMenuSettings.shared
        metrics = RadialMenuMetrics.current()
        model.actions = settings.activeActions
        model.selection = nil
        // 面板复用，字号/文字开关必须每次唤出时显式下发
        model.iconSize = CGFloat(settings.iconSize)
        model.titleSize = CGFloat(settings.textSize)
        urls = []
        triggerModifiers = modifiers.intersection(relevantFlags)
        startedAt = Date()
        initialMouse = NSEvent.mouseLocation

        ensurePanel(size: metrics.panelSize)
        positionPanel()
        model.isShown = false
        // 底板也要淡入：直接给 1 的话，面板一出现就是一块实心玻璃，内容才慢慢长出来
        effectView?.alphaValue = 0
        panel?.orderFrontRegardless()
        isOpen = true
        fadeInEffect(duration: 0.2)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen else { return }
            self.model.isShown = true
        }
        startTimer()

        AppLog.shared.log("圆环唤出 扇区=\(model.actions.count) 修饰键=\(triggerModifiers.rawValue) alpha=\(effectView?.alphaValue ?? -1) window=\(effectView?.window != nil) mask=\(effectView?.layer?.mask != nil)", category: "Radial", level: .hot)
    }

    func updateURLs(_ urls: [URL]) {
        guard isOpen else { return }
        self.urls = urls
    }

    /// 设置页「在光标处试一下」：展示 2.5 秒后自动收起，不执行任何动作
    func preview() {
        guard !isOpen else { return }
        show(modifiers: [], force: true)
        let session = sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.isOpen, self.sessionID == session else { return }
            self.close()
        }
    }

    // MARK: - 轮询

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard isOpen, let panel else { return }

        let mouse = NSEvent.mouseLocation
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        // 面板贴边时会向内夹取，圆心不再等于光标位置；此时若直接用圆心判定，
        // 一唤出就会误选中某个扇区。要求光标先移动超过 8pt 才开始选择。
        let moved = hypot(mouse.x - initialMouse.x, mouse.y - initialMouse.y) > 8
        let index = moved
            ? RadialMenuGeometry.index(for: mouse, center: center,
                                       count: model.actions.count, metrics: metrics)
            : nil

        if index != model.selection {
            model.selection = index
            if index != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }

        // Esc：Quartz 键态查询不需要事件监听权限
        if CGEventSource.keyState(.combinedSessionState, key: 53) {
            AppLog.shared.log("圆环 Esc 取消", category: "Radial")
            close()
            return
        }

        // 修饰键松开即提交。极短按（<120ms）先等一帧，避免误触
        guard !triggerModifiers.isEmpty else { return }
        let held = NSEvent.modifierFlags.intersection(relevantFlags)
        if !held.isSuperset(of: triggerModifiers) {
            if Date().timeIntervalSince(startedAt) < 0.12 { return }
            commit()
        }
    }

    // MARK: - 提交 / 关闭

    private func commit() {
        let action = model.selectedAction
        let targetURLs = urls.isEmpty ? FinderSelection.currentSelection() : urls
        close()

        guard let action else {
            AppLog.shared.log("圆环关闭：中心区，未执行", category: "Radial")
            return
        }
        AppLog.shared.log("圆环执行 \(action.id) urls=\(targetURLs.count)", category: "Radial", level: .success)
        perform(action, urls: targetURLs)
    }

    func close(animated: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        timer?.invalidate()
        timer = nil
        model.isShown = false
        // 这里不再清 selection：清空会让中心文字先跳回提示语、再跟着整体淡出，
        // 看起来像「收起来之前抖了一下」。下次 show() 会重置。

        guard let panel else { return }
        guard animated else {
            effectView?.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        // 底板是独立的 AppKit 视图，SwiftUI 的淡出管不到它，
        // 分帧把 alpha 降下去，与内容的 0.18s 淡出同步；等两边都走完再收面板
        fadeOutEffect(duration: 0.18)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            panel.orderOut(nil)
        }
    }

    /// 逐帧提高材质透明度，和内容的入场同步
    private func fadeInEffect(duration: Double) {
        fadeToken &+= 1
        let token = fadeToken
        let steps = 12
        let interval = duration / Double(steps)
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) { [weak self] in
                guard let self, self.fadeToken == token else { return }
                self.effectView?.alphaValue = CGFloat(step) / CGFloat(steps)
            }
        }
    }

    /// 逐帧降低材质透明度。
    /// NSAnimationContext + animator() 对 NSVisualEffectView 的 alpha 不可靠，
    /// 一旦动画没生效就整块不消失（或停在 0 不出现），所以自己控帧。
    private func fadeOutEffect(duration: Double) {
        fadeToken &+= 1
        let token = fadeToken
        let steps = 9
        let interval = duration / Double(steps)
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) { [weak self] in
                guard let self, self.fadeToken == token else { return }
                self.effectView?.alphaValue = 1 - CGFloat(step) / CGFloat(steps)
            }
        }
    }

    // MARK: - 动作分发

    private func perform(_ action: RadialAction, urls: [URL]) {
        switch action.id {
        case "compress.quick":
            Task { await HotKeyDispatcher.shared.runQuickCompress(urls: urls) }

        case "compress.interactive":
            HotKeyDispatcher.shared.dispatchInteractiveWithUrls(urls: urls, actionId: .compressInteractive)

        case "video.quick":
            Task { await HotKeyDispatcher.shared.runQuickVideoCompress(urls: urls) }

        case "format.convert":
            AppDelegate.shared?.openModule(.format, urls: urls)

        case "rename.quick":
            HotKeyDispatcher.shared.dispatchInteractiveWithUrls(urls: urls, actionId: .quickRename)

        case "datefolder.new":
            HotKeyDispatcher.shared.dispatchInteractiveWithUrls(urls: urls, actionId: .datefolderInteractive)

        case "shelf.add":
            guard !urls.isEmpty else {
                AppNotification.send(title: "没有可暂存的文件", body: "请先在 Finder 中选中文件")
                return
            }
            _ = ShelfStore.shared.addItems(urls: urls)
            ShelfPanelController.shared.showPanel()

        case "settings.open":
            AppDelegate.shared?.openModule(.settings)

        default:
            AppLog.shared.log("圆环未知动作 \(action.id)", category: "Radial", level: .warn)
        }
    }

    // MARK: - 窗口

    private func ensurePanel(size: CGFloat) {
        // 尺寸档位变化时重建面板；未变化则复用，保证第二次唤出没有构建延迟
        if let panel, panel.frame.width == size { return }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil

        let hosting = NSHostingView(rootView: RadialMenuView(model: model, metrics: metrics))
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        hosting.autoresizingMask = [.width, .height]
        // NSHostingView 的图层如果带底色，会把下面的材质整块盖住，看起来就是「没有毛玻璃」
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false

        // 背景模糊必须交给 AppKit：SwiftUI 的 .ultraThinMaterial 在这种透明、
        // 高层级 NSPanel 里拿不到窗口背后的采样，只会渲染成半透明灰。
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        container.wantsLayer = true

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.alphaValue = 1

        // 圆形遮罩用 CALayer 而不是 maskImage：maskImage 在 behindWindow 模式下
        // 有概率让整个材质退化掉，CALayer mask 只是合成期裁剪，不影响背景采样。
        effect.wantsLayer = true
        let diameter = metrics.backdropRadius * 2
        let inset = (size - diameter) / 2
        let mask = CAShapeLayer()
        mask.frame = container.bounds
        mask.path = CGPath(ellipseIn: CGRect(x: inset, y: inset,
                                             width: diameter, height: diameter),
                           transform: nil)
        effect.layer?.mask = mask

        container.addSubview(effect)
        container.addSubview(hosting)
        self.effectView = effect

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // 不能用 .screenSaver：层级过高时窗口服务器不会给 behindWindow 材质做背景采样，
        // 毛玻璃会退化成纯色（甚至完全透明）。.popUpMenu 足够盖住普通窗口与全屏 App。
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 固定深色外观：材质是 HUD 暗色，动态色也走暗色分支，文字和底子保持一致
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.contentView = container
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let size = metrics.panelSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main

        var origin = CGPoint(x: mouse.x - size / 2, y: mouse.y - size / 2)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size - 8)
        }
        panel.setFrameOrigin(origin)
    }
}
