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
