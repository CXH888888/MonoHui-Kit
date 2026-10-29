import AppKit

/// 支持「屏幕裁剪」的面板基类
/// 面板只显示与 clipScreen 相交的部分：动画滑出/滑入时，落在其他屏幕可见区域内的部分
/// 会被 mask 裁掉，不会穿帮到相邻屏幕。这样所有屏幕都能统一从屏幕左边缘滑入。
class ShelfClipPanel: NSPanel {
    /// 裁剪目标屏幕（nil = 不裁剪，显示全部）
    weak var clipScreen: NSScreen? {
        didSet { updateClipMask() }
    }
    private var clipMaskLayer: CALayer?

    /// mask 同步定时器：panel 可见期间持续更新 mask，覆盖 animator().setFrame() 动画
    /// animator().setFrame() 不一定逐步调用 setFrame override，需要 Timer 主动同步
    private var maskSyncTimer: Timer?

    /// contentView 被替换时（如 contentViewController 设置后），重新配置 mask
    override var contentView: NSView? {
        didSet {
            // 重置 mask，下次 updateClipMask 会重新创建并挂到新 contentView 的 layer 上
            clipMaskLayer = nil
            updateClipMask()
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        updateClipMask()
    }

    /// panel 显示时启动 mask 同步（只覆盖动画那段时间），隐藏时停止
    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        startMaskSync()
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        stopMaskSync()
    }

    /// 启动 mask 同步定时器：每 1/60s 更新一次 mask
    /// 确保 animator().setFrame() 动画期间 mask 实时跟随 window frame
    ///
    /// 只在动画期间跑，跑完自动停。之前是「面板可见就一直跑」——书架常驻屏幕上时
    /// 等于常开一个 60fps 定时器每帧重算 CALayer mask，白白吃掉渲染预算，
    /// 其他动画跟着掉帧。
    private var maskSyncGeneration = 0

    private func startMaskSync() {
        stopMaskSync()
        updateClipMask()
        maskSyncGeneration += 1
        let generation = maskSyncGeneration
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateClipMask()
        }
        RunLoop.main.add(timer, forMode: .common)
        maskSyncTimer = timer
        // 动画最长约 0.4s，留点余量到 0.6s；期间再次启动会刷新 generation，
        // 旧的停止任务就不生效了
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.maskSyncGeneration == generation else { return }
            self.stopMaskSync()
        }
    }

    /// 停止 mask 同步定时器，并最终更新一次 mask
    private func stopMaskSync() {
        maskSyncTimer?.invalidate()
        maskSyncTimer = nil
        updateClipMask()
    }

    /// 更新裁剪 mask：mask 区域 = 窗口 frame ∩ clipScreen frame（窗口本地坐标）
    /// 面板超出所属屏幕的部分（例如右侧扩展屏向左滑出时落在左侧屏幕上的部分）完全不可见
    func updateClipMask() {
        guard let contentView = contentView else { return }
        contentView.wantsLayer = true
        // 关键修复：layer 可能为 nil（wantsLayer=true 不立即创建 layer），强制创建
        if contentView.layer == nil {
            contentView.layer = CALayer()
        }
        guard let layer = contentView.layer else { return }

        // mask 丢失或换了 layer，重新创建
        if clipMaskLayer == nil || clipMaskLayer?.superlayer !== layer {
            let mask = CALayer()
            mask.backgroundColor = NSColor.white.cgColor
            layer.mask = mask
            clipMaskLayer = mask
        }
        guard let mask = clipMaskLayer else { return }

        // 禁用 CALayer 隐式动画，确保 mask 立即生效（避免动画期间 mask 滞后于 window frame）
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if clipScreen == nil {
            mask.frame = contentView.bounds
            CATransaction.commit()
            return
        }
        guard let screen = clipScreen else {
            CATransaction.commit()
            return
        }
        // 窗口全局 frame 与屏幕全局 frame 的交集
        let visible = NSIntersectionRect(screen.frame, frame)
        if visible.isNull || visible.isEmpty {
            // 没有交集（面板完全在屏幕外），完全隐藏
            mask.frame = .zero
        } else {
            // 转换为 contentView 本地坐标（窗口左下角为原点）
            mask.frame = visible.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        CATransaction.commit()
    }
}

/// 中转站面板窗口（non-activating NSPanel，不抢前台但可接收点击）
final class ShelfPanel: ShelfClipPanel {
    // 必须允许成为 key 窗口，否则内部 SwiftUI 按钮不响应点击
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        // 关闭窗口阴影：阴影由窗口服务器绘制，不受 layer.mask 裁剪，
        // 会穿透到相邻屏幕形成残影
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.hidesOnDeactivate = false
        // 允许面板按需成为 key，从而接收键盘和点击事件
        self.becomesKeyOnlyIfNeeded = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = false
        self.appearance = NSAppearance(named: .vibrantDark)
        self.identifier = NSUserInterfaceItemIdentifier("ShelfPanel")
    }
}
