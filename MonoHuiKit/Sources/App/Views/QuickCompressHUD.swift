import SwiftUI
import AppKit
import Observation

/// 快速压缩（无窗口模式）的浮动进度面板。
/// 几百个文件时用户必须能看到「还要多久、卡在哪个文件」，否则只能干等。
@MainActor
@Observable
final class CompressHUDModel {
    enum Phase {
        case running
        case finished
        case cancelled
    }

    var title: String = "正在压缩"
    var total: Int = 0
    var completed: Int = 0
    var currentFileName: String = ""
    var phase: Phase = .running
    var summary: String = ""
    var failedCount: Int = 0
    var skippedCount: Int = 0
    /// 距离自动收起还剩几秒；0 表示不显示（运行中或已取消）
    var countdown: Int = 0
    /// 当前文件内部进度（视频转码这类长任务）
    var currentFraction: Double = 0

    /// 有失败或跳过时才提供明细入口，全成功不打扰
    var hasIssues: Bool { failedCount > 0 || skippedCount > 0 }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, (Double(completed) + currentFraction) / Double(total))
    }
}

/// 非激活面板（.nonactivatingPanel）默认会吞掉第一次点击用于激活窗口，
/// 覆写后点击立刻生效——否则「点面板展开明细」要点两下才有反应。
private final class HUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct CompressHUDView: View {
    let model: CompressHUDModel
    var onCancel: () -> Void
    var onOpenDetail: () -> Void
    var onClose: () -> Void

    private var canOpenDetail: Bool { model.phase == .finished && model.hasIssues }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            progressBar
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appleDivider, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if canOpenDetail { onOpenDetail() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            icon

            Text(model.phase == .running ? model.title : model.summary)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appleInk)
                .lineLimit(1)

            Spacer(minLength: 8)

            if model.phase == .running {
                Text("\(model.completed)/\(model.total)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.appleSoft)
                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appleSoft)
            } else if model.phase == .finished {
                // 倒计时贴在关闭按钮左侧，颜色与关闭按钮同一档（appleSoft），
                // 让人知道这块面板会自己消失、还剩多久
                if model.countdown > 0 {
                    Text("\(model.countdown)s")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.appleSoft)
                        .monospacedDigit()
                }
                if canOpenDetail {
                    // 常驻面板必须有显式出口，否则只能等它自己被新任务顶掉
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.appleSoft)
                            .frame(width: 18, height: 18)
                            .background(Color.appleSurface3)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if model.phase == .running {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
        } else if model.phase == .finished {
            Image(systemName: model.hasIssues ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(model.hasIssues ? Color.orange : Color.appleSuccess)
        } else {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // 自绘胶囊进度条：比 ProgressView 更贴合整体视觉
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appleSurface3)
                Capsule()
                    .fill(barColor)
                    .frame(width: max(0, geo.size.width * model.fraction))
                    .animation(Motion.progress, value: model.fraction)
            }
        }
        .frame(height: 4)
    }

    private var barColor: Color {
        guard model.phase == .finished else { return Color.appleBlue }
        return model.hasIssues ? Color.orange : Color.appleBlue
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if model.phase == .running {
                Text(model.currentFileName.isEmpty ? "准备中…" : model.currentFileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if canOpenDetail {
                // 用 Button 而不是纯文字：非激活面板上 onTapGesture 可能被吞掉，
                // 按钮是保底入口，整块面板的点击只当增强
                Button(action: onOpenDetail) {
                    HStack(spacing: 4) {
                        Text("查看明细")
                            .foregroundStyle(Color.orange.opacity(0.95))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.appleMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            } else {
                Text("\(model.completed) 个文件已处理")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.appleMuted)
    }
}

@MainActor
final class QuickCompressHUDController {
    static let shared = QuickCompressHUDController()

    private var panel: NSPanel?
    private var model: CompressHUDModel?
    private var cancelHandler: (() -> Void)?
    /// 保留本轮报告，供「点击查看明细」使用
    private var report: CompressionReport?
    /// 倒计时链的世代标记，begin / dismiss 时更新，旧链随即失效
    private var countdownToken = UUID()

    private init() {}

    func begin(title: String, total: Int, onCancel: @escaping () -> Void) {
        dismiss(animated: false)

        let model = CompressHUDModel()
        model.title = title
        model.total = total
        self.model = model
        self.cancelHandler = onCancel

        let view = CompressHUDView(
            model: model,
            onCancel: { [weak self] in
                self?.model?.phase = .cancelled
                self?.model?.summary = "正在取消…"
                self?.cancelHandler?()
            },
            onOpenDetail: { [weak self] in
                guard let self, let report = self.report else { return }
                // 先让底部条退场，再弹明细：两块浮层同时压屏会互相抢焦点
                self.dismiss(animated: true) {
                    CompressionResultWindowController.shared.show(report: report)
                }
            },
            onClose: { [weak self] in self?.dismiss(animated: true) }
        )
        let hosting = HUDHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        // 屏幕底部居中，避开 Dock
        var targetOrigin = panel.frame.origin
        var hiddenOrigin = panel.frame.origin
        if let screen = NSScreen.main {
            let size = hosting.fittingSize
            let visible = screen.visibleFrame
            targetOrigin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 48)
            // 完全滑到屏幕下沿之外，入场时从下方滑上来（与暂存箱同一套位移 + 淡入）
            hiddenOrigin = NSPoint(x: targetOrigin.x, y: visible.minY - size.height)
        }

        // 先在隐藏位置就位并置全透明，此时窗口已在屏外，用户看不到
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(NSRect(origin: hiddenOrigin, size: panel.frame.size), display: false)
        panel.alphaValue = 0
        CATransaction.commit()

        panel.orderFrontRegardless()

        // 位移与透明度一起动：0.35s，ease-enter 出场
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.caDuration(Motion.Duration.standard * 1.45)
            ctx.timingFunction = Motion.caEnter
            panel.animator().setFrame(NSRect(origin: targetOrigin, size: panel.frame.size), display: true)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func update(_ progress: CompressionProgress) {
        guard let model else { return }
        model.completed = progress.completed
        model.total = progress.total
        model.currentFileName = progress.currentFileName
        model.currentFraction = progress.currentFraction
    }

    /// 结束本轮压缩。
    ///
    /// 无论成功与否都会自动收起，只是停留时长不同：全部成功 3 秒，
    /// 有失败或跳过 5 秒（留出点「查看明细」的时间）。
    /// 面板右上角会显示剩余秒数，避免「怎么突然没了」。
    ///
    /// - Parameters:
    ///   - successDismissAfter: 全部成功时的收起延时
    ///   - issueDismissAfter: 有失败或跳过时的收起延时
    func finish(report: CompressionReport,
                successDismissAfter: TimeInterval = 3,
                issueDismissAfter: TimeInterval = 5) {
        guard let model else { return }
        self.report = report
        model.phase = .finished
        model.summary = report.summaryLine
        model.failedCount = report.failedCount
        model.skippedCount = report.skippedCount
        model.completed = model.total

        resizeToFit()

        let seconds = Int((report.hasIssues ? issueDismissAfter : successDismissAfter).rounded())
        guard seconds > 0 else { return }
        // 必须先把新 token 写进 countdownToken 再启动，否则 startCountdown 的
        // 世代校验会立即失败，倒计时既不显示也不会触发自动收起
        let token = UUID()
        countdownToken = token
        startCountdown(remaining: seconds, token: token)
        AppLog.shared.log("浮层倒计时启动 \(seconds)s（失败 \(report.failedCount) / 跳过 \(report.skippedCount)）",
                          category: "Dispatcher")
    }

    /// 每秒递减一次，归零时收起。
    ///
    /// 用 token 而不是 Timer 持有：任何一次 begin / dismiss 都会换 token，
    /// 旧链自然失效，不会出现「新一轮面板被上一轮倒计时关掉」。
    private func startCountdown(remaining: Int, token: UUID) {
        guard token == countdownToken else { return }
        guard remaining > 0 else {
            AppLog.shared.log("浮层倒计时归零，自动收起", category: "Dispatcher")
            dismiss(animated: true)
            return
        }
        model?.countdown = remaining
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.startCountdown(remaining: remaining - 1, token: token)
        }
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        // 换 token 让尚未走完的倒计时链失效
        countdownToken = UUID()
        guard let panel else {
            completion?()
            return
        }
        self.panel = nil
        self.model = nil
        self.cancelHandler = nil
        self.report = nil

        guard animated else {
            panel.orderOut(nil)
            completion?()
            return
        }

        // 与暂存箱对称的退场：向下滑出 + 淡出，动画结束后才真正 orderOut
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var hiddenFrame = panel.frame
        hiddenFrame.origin.y = visible.minY - panel.frame.height

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.caDuration(Motion.Duration.exit * 1.4)
            ctx.timingFunction = Motion.caStandard
            panel.animator().setFrame(hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
            completion?()
        }
    }

    /// 结束后底部会多出一行明细入口，面板高度需跟着变。
    /// HUD 贴屏幕底部，所以保持底边不动、向上生长。
    private func resizeToFit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let hosting = panel.contentView else { return }
            hosting.layoutSubtreeIfNeeded()
            let target = hosting.fittingSize
            guard target.height > 0, abs(panel.frame.height - target.height) > 0.5 else { return }

            let bottom = panel.frame.minY
            var frame = panel.frame
            frame.size = NSSize(width: max(frame.width, target.width), height: target.height)
            frame.origin.y = bottom
            panel.setFrame(frame, display: true)
        }
    }
}
