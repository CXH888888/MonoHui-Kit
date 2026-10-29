import SwiftUI
import AppKit

/// 侧栏的毛玻璃底。
///
/// 原来是 `NavigationSplitView` 自带的那层 `NSVisualEffectView(material: .sidebar)`，
/// 换成自绘两栏后得自己垫回来。
///
/// 为什么这里不会再像之前那样卡：侧栏内容（含这层玻璃）**固定 200 宽**，
/// 折叠/展开只改外层 `.frame(width:)` + `.clipped()` 的裁剪范围，
/// 玻璃层自身的 frame 全程不变，不会每帧重新采样背后的画面。
struct SidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        // 不要用 .followsWindowActiveState：窗口在「活跃/非活跃」之间切换时，
        // 整块玻璃要按两种状态各渲染一次，实测每次 App 激活主线程要花 100~190ms。
        // 固定 .active，观感差别很小，但激活不再重算。
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 让承载它的窗口变成非不透明。
///
/// `.behindWindow` 的毛玻璃要采样**窗口背后的桌面**，前提是窗口在该区域是透明的；
/// 否则 AppKit 只能拿窗口自身的底色去模糊，看起来就是一块死灰。
struct WindowTransparency: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 标题栏那一条的拖拽区。
///
/// 自绘两栏后内容整体上移到窗口顶（y=0），标题栏区域被 SwiftUI 内容盖住，
/// AppKit 收不到 mouseDown，窗口就拖不动了。这里垫一个空 NSView，
/// `mouseDownCanMoveWindow` 交还给窗口，拖动它等于拖窗口。
struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Strip() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Strip: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { self }
    }
}

/// 把原生红绿灯挪到左上角的指定边距，并把实际布局回报给 SwiftUI。
///
/// 系统没有公开的位置 API，做法和 Electron 的 `trafficLightPosition` 一致：
/// 先把标题栏容器撑高到「按钮高 + 上下边距」，再把三颗按钮摆进容器。
/// 只改按钮 frame 不行——按钮会被 28pt 高的标题栏容器裁掉，画面上直接消失。
///
/// 回传两个值：
/// - `sidebarInset`：侧栏内容要往下让出多少（红绿灯底边 + 8pt）
/// - `trailingEdge`：最右那颗按钮的右边缘（拖拽区从它右边开始）
struct TitlebarLayout: NSViewRepresentable {
    /// 红绿灯距窗口左、上边缘的边距
    static let margin: CGFloat = 16

    let onUpdate: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onUpdate: onUpdate) }

    func makeNSView(context: Context) -> NSView {
        let probe = Probe()
        probe.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator {
        private let onUpdate: (CGFloat, CGFloat) -> Void
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var lastReport: (CGFloat, CGFloat)?

        init(onUpdate: @escaping (CGFloat, CGFloat) -> Void) {
            self.onUpdate = onUpdate
        }

        func attach(to window: NSWindow?) {
            guard window !== self.window else { return }
            detach()
            guard let window else { return }
            self.window = window

            apply()
            // 视图挂上时 SwiftUI 还没排完版，稍后再落一次，避免被首轮布局覆盖
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.apply() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.apply() }

            let center = NotificationCenter.default
            // AppKit 在窗口激活 / 缩放 / 退出全屏时会重排标题栏，位置得跟着补
            for name in [NSWindow.didBecomeKeyNotification,
                         NSWindow.didResizeNotification,
                         NSWindow.didExitFullScreenNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.apply()
                })
            }
            observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.apply()
            })
        }

        private func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            window = nil
        }

        private func apply() {
            // 全屏时按钮由系统接管，别去改；退出全屏会收到通知再补
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
            guard buttons.count == 3,
                  let container = buttons[0].superview?.superview else { return }

            let buttonSize = buttons[0].frame.size
            // 按钮间距沿用系统当前值，别写死
            let gap = max(0, buttons[1].frame.minX - buttons[0].frame.maxX)

            var containerFrame = container.frame
            containerFrame.size.height = buttonSize.height + TitlebarLayout.margin * 2
            containerFrame.origin.y = window.frame.height - containerFrame.height
            if container.frame != containerFrame {
                container.frame = containerFrame
            }

            var x = TitlebarLayout.margin
            let y = (containerFrame.height - buttonSize.height) / 2
            for button in buttons {
                let origin = NSPoint(x: x, y: y)
                if button.frame.origin != origin {
                    button.setFrameOrigin(origin)
                }
                x += buttonSize.width + gap
            }

            report(from: window)
        }

        private func report(from window: NSWindow) {
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
            guard let close = buttons.first else { return }

            // NSView 转窗口坐标：原点在左下，y 要翻过来
            let closeRect = close.convert(close.bounds, to: nil)
            let centerY = window.frame.height - closeRect.midY
            let trailingEdge = buttons
                .map { $0.convert($0.bounds, to: nil).maxX }
                .max() ?? 74
            let sidebarInset = max(28, centerY + closeRect.height / 2 + 8)

            if let last = lastReport,
               abs(last.0 - sidebarInset) < 0.5,
               abs(last.1 - trailingEdge) < 0.5 {
                return
            }
            lastReport = (sidebarInset, trailingEdge)
            DispatchQueue.main.async { [onUpdate] in
                onUpdate(sidebarInset, trailingEdge)
            }
        }
    }
}
