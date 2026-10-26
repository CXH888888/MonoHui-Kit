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
    /// 当前文件内部进度（视频转码这类长任务）
    var currentFraction: Double = 0

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, (Double(completed) + currentFraction) / Double(total))
    }
}

struct CompressHUDView: View {
    let model: CompressHUDModel
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if model.phase == .running {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else if model.phase == .finished {
                    Image(systemName: model.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(model.failedCount > 0 ? Color.orange : Color.appleSuccess)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleSoft)
                }

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
                }
            }

            // 自绘胶囊进度条：比 ProgressView 更贴合整体视觉
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appleSurface3)
                    Capsule()
                        .fill(model.failedCount > 0 && model.phase == .finished ? Color.orange : Color.appleBlue)
                        .frame(width: max(0, geo.size.width * model.fraction))
                        .animation(.easeOut(duration: 0.18), value: model.fraction)
                }
            }
            .frame(height: 4)

            Text(model.phase == .running
                 ? (model.currentFileName.isEmpty ? "准备中…" : model.currentFileName)
                 : "\(model.completed) 个文件已处理")
                .font(.system(size: 11))
                .foregroundStyle(Color.appleMuted)
                .lineLimit(1)
                .truncationMode(.middle)
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
    }
}

@MainActor
final class QuickCompressHUDController {
    static let shared = QuickCompressHUDController()

    private var panel: NSPanel?
    private var model: CompressHUDModel?
    private var cancelHandler: (() -> Void)?

    private init() {}

    func begin(title: String, total: Int, onCancel: @escaping () -> Void) {
        dismiss(animated: false)

        let model = CompressHUDModel()
        model.title = title
        model.total = total
        self.model = model
        self.cancelHandler = onCancel

        let view = CompressHUDView(model: model) { [weak self] in
            self?.model?.phase = .cancelled
            self?.model?.summary = "正在取消…"
            self?.cancelHandler?()
        }
        let hosting = NSHostingView(rootView: view)
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
        if let screen = NSScreen.main {
            let size = hosting.fittingSize
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 48
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func update(_ progress: CompressionProgress) {
        guard let model else { return }
        model.completed = progress.completed
        model.total = progress.total
        model.currentFileName = progress.currentFileName
        model.currentFraction = progress.currentFraction
    }

    func finish(summary: String, failedCount: Int, autoDismissAfter delay: TimeInterval = 1.8) {
        guard let model else { return }
        model.phase = .finished
        model.summary = summary
        model.failedCount = failedCount
        model.completed = model.total
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.dismiss(animated: true)
            }
        }
    }

    func dismiss(animated: Bool) {
        guard let panel else { return }
        self.panel = nil
        self.model = nil
        self.cancelHandler = nil
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
        }
    }
}
