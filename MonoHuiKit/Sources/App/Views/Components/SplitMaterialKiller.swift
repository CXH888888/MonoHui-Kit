import SwiftUI
import AppKit

/// 去掉 `NavigationSplitView` 侧栏底下的系统毛玻璃。
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
/// `.behindWindow` 的材质要在每次尺寸变化时重新采样**窗口背后的桌面**。
/// 侧栏折叠 / 展开时这一列宽度每帧都在变，于是每帧都要重做一次模糊 ——
/// 表现就是「点一下侧栏，画面卡一下」。
///
/// 我们的侧栏本来就是纯色底，这层模糊完全多余，所以：
/// - 有内容的材质层改成 `.windowBackground`（纯色填充，不采样背后）
/// - 没有内容的（分隔线那 1pt）直接隐藏
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
                if view is NSSplitView {
                    Self.neutralize(in: view)
                    return
                }
                node = view.superview
            }
        }

        private static func neutralize(in root: NSView) {
            for sub in root.subviews {
                if let effect = sub as? NSVisualEffectView {
                    if effect.subviews.isEmpty {
                        // 分隔线那层纯装饰，藏掉不留残影
                        effect.isHidden = true
                    } else {
                        effect.material = .windowBackground
                        effect.state = .followsWindowActiveState
                    }
                }
                neutralize(in: sub)
            }
        }
    }
}
