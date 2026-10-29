import SwiftUI
import AppKit

/// 把 `NavigationSplitView` 侧栏底下的系统材质换成不采样背后的纯色。
///
/// 实测视图树（macOS 26）：
///
///     NSSplitView
///       _NSSplitViewItemViewWrapper
///         NSVisualEffectView(material: .sidebar, blending: .behindWindow)   ← 侧栏底
///           NSHostingView<ColumnView>                                        ← 我们的内容
///       NSVibrantSplitDividerView
///         NSVisualEffectView                                                  ← 分隔线那 1pt
///
/// `.behindWindow` 的材质在尺寸变化时要重新采样**窗口背后的画面**，
/// 侧栏折叠/展开时这一列宽度每帧都在变，等于每帧重做一次模糊。
///
/// 注意：**只改材质，绝不隐藏**。侧栏那层材质是内容的父视图，
/// 一旦 `isHidden = true`，整块侧栏（连同所有按钮）都会消失——
/// 而且判断"有没有内容"也不可靠：视图刚挂上去时 SwiftUI 还没把内容塞进来，
/// 那一刻它看起来就是个空层。
struct SplitMaterialKiller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { KillerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KillerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // 侧栏刚建立时可能还没被塞进 split view，下一拍再补一次
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            var node: NSView? = superview
            while let view = node {
                if let split = view as? NSSplitView {
                    Self.neutralize(in: split)
                    return
                }
                node = view.superview
            }
        }

        private static func neutralize(in root: NSView) {
            for sub in root.subviews {
                if let effect = sub as? NSVisualEffectView {
                    effect.material = .windowBackground
                }
                neutralize(in: sub)
            }
        }
    }
}
