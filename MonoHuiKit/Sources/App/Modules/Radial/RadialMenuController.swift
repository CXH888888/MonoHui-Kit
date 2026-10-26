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
        panel?.orderFrontRegardless()
        isOpen = true

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen else { return }
            self.model.isShown = true
        }
        startTimer()

        AppLog.shared.log("圆环唤出 扇区=\(model.actions.count) 修饰键=\(triggerModifiers.rawValue)", category: "Radial", level: .hot)
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
        model.selection = nil

        guard let panel else { return }
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                panel.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
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

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
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
