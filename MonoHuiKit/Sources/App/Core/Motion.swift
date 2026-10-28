import SwiftUI
import QuartzCore

/// 动效令牌 —— 取自设计规范 `foundations/motion.html`（`tokens/motion.css` + `arc-motion-tokens.ts`）。
///
/// 规范要点：
/// - 时长：instant 120 / fast 160 / exit 180 / standard 240 / considered 480（毫秒）
/// - 缓动：standard `(0.22,1,0.36,1)` 为 UI 默认；enter `(0.16,1,0.3,1)` 入场；
///   exit `(0.7,0,0.84,0)` 退场；in-out `(0.65,0,0.35,1)` 屏内移动
/// - 弹簧：snappy / smooth / morph / responsive / gentle
/// - 错峰：char 16ms / word 40ms / line 80ms / item 35ms，总错峰封顶 `standard`
/// - 模糊：subtle 2 / soft 4 / text 8
///
/// 所有令牌返回 `Animation?`：系统「减弱动效」开启时统一返回 nil，
/// 调用方照常写 `.animation(Motion.xxx, value:)` / `withAnimation(Motion.xxx)`，
/// 无需各自判断——规范要求减弱动效时保留终态、去掉位移与模糊。
///
/// 调用点一律用这里的令牌，不要再写裸数字。
enum Motion {

    // MARK: - 时长

    enum Duration {
        /// 极短的状态确认反馈
        static let instant: Double = 0.12
        /// hover、颜色、小状态变化
        static let fast: Double = 0.16
        /// 退场
        static let exit: Double = 0.18
        /// 面板、菜单（UI 默认）
        static let standard: Double = 0.24
        /// 罕见的介绍性揭示
        static let considered: Double = 0.48
    }

    // MARK: - 缓动控制点（cubic-bezier）

    struct Curve {
        let x1: Double, y1: Double, x2: Double, y2: Double

        /// UI 默认
        static let standard = Curve(x1: 0.22, y1: 1.0, x2: 0.36, y2: 1.0)
        /// 元素入场
        static let enter = Curve(x1: 0.16, y1: 1.0, x2: 0.30, y2: 1.0)
        /// 退场
        static let exit = Curve(x1: 0.70, y1: 0.0, x2: 0.84, y2: 0.0)
        /// 屏内元素移动
        static let inOut = Curve(x1: 0.65, y1: 0.0, x2: 0.35, y2: 1.0)
    }

    // MARK: - 减弱动效

    /// 系统「辅助功能 → 显示 → 减弱动态效果」
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - SwiftUI 缓动

    static func ease(_ curve: Curve, _ duration: Double) -> Animation? {
        reduceMotion ? nil : .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: duration)
    }

    /// 状态确认（120ms，standard 曲线）
    static var easeInstant: Animation? { ease(.standard, Duration.instant) }
    /// 颜色 / 小状态变化（160ms）
    static var easeFast: Animation? { ease(.standard, Duration.fast) }
    /// 面板 / 菜单（240ms）
    static var easeStandard: Animation? { ease(.standard, Duration.standard) }
    /// 入场（240ms + ease.enter）
    static var enter: Animation? { ease(.enter, Duration.standard) }
    /// 退场（180ms + ease.exit）
    static var leave: Animation? { ease(.exit, Duration.exit) }
    /// 屏内位移（240ms + ease.in-out）
    static var move: Animation? { ease(.inOut, Duration.standard) }
    /// 小幅位移 / 淡入淡出（160ms + ease.in-out）
    static var moveFast: Animation? { ease(.inOut, Duration.fast) }
    /// 进度条这类连续量：线性短过渡，避免逐帧缓动造成的滞后
    static var progress: Animation? { reduceMotion ? nil : .linear(duration: Duration.instant) }

    // MARK: - 弹簧

    /// 按压、开关、thumb、小指示器（visualDuration .26 · bounce .12）
    static var snappy: Animation? { reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.12) }
    /// 面板、高度变化、布局位移，不过冲（visualDuration .4 · bounce 0）
    static var smooth: Animation? { reduceMotion ? nil : .spring(duration: 0.40, bounce: 0) }
    /// 形变、共享高亮、跟随内容的宽度（visualDuration .42 · bounce .16）
    static var morph: Animation? { reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.16) }
    /// 直接操纵、紧跟指针（stiffness 520 · damping 38）
    static var responsive: Animation? {
        reduceMotion ? nil : .interpolatingSpring(stiffness: 520, damping: 38)
    }
    /// 大布局变化，平静（stiffness 340 · damping 34）
    static var gentle: Animation? {
        reduceMotion ? nil : .interpolatingSpring(stiffness: 340, damping: 34)
    }

    // MARK: - 错峰

    enum Stagger {
        /// 逐字符
        static let char: Double = 0.016
        /// 逐词
        static let word: Double = 0.040
        /// 逐行
        static let line: Double = 0.080
        /// 逐项
        static let item: Double = 0.035

        /// 第 index 项的延迟，总错峰封顶 `Duration.standard`（规范：封顶 240ms）
        static func delay(_ index: Int, step: Double = item) -> Double {
            min(Double(index) * step, Duration.standard)
        }
    }

    // MARK: - 模糊（交叉淡入时的半径，收尾必须回 0）

    enum Blur {
        static let subtle: CGFloat = 2
        static let soft: CGFloat = 4
        static let text: CGFloat = 8
    }

    // MARK: - AppKit / CoreAnimation

    /// `NSAnimationContext.timingFunction` 用
    static func caCurve(_ curve: Curve) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(curve.x1), Float(curve.y1),
                              Float(curve.x2), Float(curve.y2))
    }

    static var caEnter: CAMediaTimingFunction { caCurve(.enter) }
    static var caExit: CAMediaTimingFunction { caCurve(.exit) }
    static var caStandard: CAMediaTimingFunction { caCurve(.standard) }
    static var caMove: CAMediaTimingFunction { caCurve(.inOut) }

    /// AppKit 动画时长：减弱动效时坍缩为 0，直接落位
    static func caDuration(_ duration: Double) -> Double {
        reduceMotion ? 0 : duration
    }

    /// 弹窗入场：先透明、再淡入（规范：面板 standard 240ms + ease.enter）。
    /// 之前几个 Popover 直接 `makeKeyAndOrderFront`，窗口是硬切的，这是观感「不丝滑」的主要来源之一。
    /// 窗口本来就可见时（复用实例再次置前）不做淡入，避免闪一下。
    static func present(_ window: NSWindow, duration: Double = Duration.standard) {
        let wasVisible = window.isVisible
        guard !reduceMotion, !wasVisible else {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            return
        }
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = caEnter
            window.animator().alphaValue = 1
        }
    }
}
