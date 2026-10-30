import SwiftUI
import AppKit

/// 滚动轴向：横向（渠道标签行）/ 纵向（列表与网格）
enum ScrollAxis {
    case horizontal
    case vertical
}

/// 滚动几何：`offset` 为 0 表示起点（最左/最顶）。
/// 用「长度」而不是宽高，横向与纵向共用同一套字段。
struct ScrollEdgeGeom: Equatable {
    var offset: CGFloat = 0
    var contentLength: CGFloat = 0
    var viewportLength: CGFloat = 0
}

/// 滚动边界观察器：macOS 14 的 SwiftUI preference 在滚动过程中不更新，
/// 改用 AppKit 通知直读 NSScrollView；横向滚动时顺带把竖向滚轮转成横向滚动。
final class ScrollEdgeObserverView: NSView {
    var axis: ScrollAxis = .vertical
    var onChange: ((ScrollEdgeGeom) -> Void)?
    private var observingClip = false
    private var observingDoc = false
    private var monitor: Any?
    private var lastGeom: ScrollEdgeGeom?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startObservingIfNeeded()
            if axis == .horizontal {
                installWheelMonitorIfNeeded()
            } else {
                removeWheelMonitor()
            }
        } else {
            removeWheelMonitor()
        }
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        guard window != nil else { return }
        startObservingIfNeeded()
        // 布局完成后重读一次（等值守卫防循环）：标签增删、懒加载行都会改变内容长度
        DispatchQueue.main.async { [weak self] in
            self?.scrollChanged()
        }
    }

    deinit {
        removeWheelMonitor()
    }

    private func startObservingIfNeeded() {
        if !observingClip,
           let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollChanged),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
            observingClip = true
        }
        // 内容长度变化（标签增删 / 懒网格展开）不触发 clip bounds 通知，需单独监听 documentView 的 frame 变化
        if !observingDoc,
           let doc = enclosingScrollView?.documentView {
            doc.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollChanged),
                name: NSView.frameDidChangeNotification,
                object: doc
            )
            observingDoc = true
        }
        scrollChanged()
    }

    @objc private func scrollChanged() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let isHorizontal = axis == .horizontal
        let geom = ScrollEdgeGeom(
            offset: isHorizontal ? clip.bounds.origin.x : clip.bounds.origin.y,
            contentLength: isHorizontal
                ? (clip.documentView?.frame.width ?? 0)
                : (clip.documentView?.frame.height ?? 0),
            viewportLength: isHorizontal ? clip.bounds.width : clip.bounds.height
        )
        // 值未变化时不再回写，避免 viewWillDraw → 状态更新 → 重绘 的循环
        guard geom != lastGeom else { return }
        lastGeom = geom
        onChange?(geom)
    }

    // macOS 横向 ScrollView 不响应竖向滚轮（触控板横向滑动原生支持），鼠标用户需转换
    private func installWheelMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  let clip = self.enclosingScrollView?.contentView,
                  event.window === self.window,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
            else { return event }
            // 仅当内容超宽（可横向滚动）且光标在滚动区内时接管
            let contentWidth = clip.documentView?.frame.width ?? 0
            guard contentWidth > clip.bounds.width + 1 else { return event }
            let clipFrame = clip.convert(clip.bounds, to: nil)
            guard clipFrame.contains(event.locationInWindow) else { return event }
            let maxX = contentWidth - clip.bounds.width
            let newX = min(max(clip.bounds.origin.x - event.scrollingDeltaY, 0), maxX)
            clip.scroll(to: NSPoint(x: newX, y: 0))
            return nil
        }
    }

    private func removeWheelMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

struct ScrollEdgeObserver: NSViewRepresentable {
    var axis: ScrollAxis
    var onChange: (ScrollEdgeGeom) -> Void

    func makeNSView(context: Context) -> ScrollEdgeObserverView {
        let view = ScrollEdgeObserverView()
        view.axis = axis
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ScrollEdgeObserverView, context: Context) {
        view.axis = axis
        view.onChange = onChange
    }
}
