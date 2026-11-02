import SwiftUI
import AppKit

/// 批量压缩结果浮层：失败与跳过逐个列出（文件名 + 原因 + 路径）。
///
/// 视觉与「新建文件夹」「压缩参数」等弹窗保持一致——无标题栏、圆角毛玻璃外壳、
/// 右上角关闭按钮 + Esc，内容区 24pt 内边距。原先用带标题栏的系统窗口，
/// 与 App 内其它弹窗是两套观感。
struct CompressionResultView: View {
    let report: CompressionReport
    var onClose: () -> Void

    @State private var copied = false

    /// 与功能弹窗同宽（480~580 区间），列表行有足够宽度展示路径
    private let panelSize = CGSize(width: 560, height: 480)

    var body: some View {
        VStack(spacing: 16) {
            headerArea
            Divider().padding(.horizontal, -24)
            content
            footer
        }
        .padding(24)
        .frame(width: panelSize.width, height: panelSize.height)
        .background(Color.applePopupCanvas)
    }

    // MARK: - 标题

    private var headerArea: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.appleInk)

            Spacer(minLength: 8)

            Text(report.summaryLine)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .lineLimit(1)

            PopoverCloseButton()
        }
    }

    private var title: String {
        if report.cancelled { return "压缩已取消" }
        return report.failedCount > 0 ? "部分文件压缩失败" : "压缩结果"
    }

    // MARK: - 明细

    private var content: some View {
        VStack(spacing: 0) {
            if report.failures.isEmpty && report.skipped.isEmpty {
                successState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !report.failures.isEmpty {
                            sectionTitle("失败 \(report.failures.count)")
                            ForEach(Array(report.failures.enumerated()), id: \.element.id) { index, item in
                                detailRow(item, isFailure: true)
                                if index < report.failures.count - 1 {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                        if !report.skipped.isEmpty {
                            sectionTitle("跳过 \(report.skipped.count)")
                            ForEach(Array(report.skipped.enumerated()), id: \.element.id) { index, item in
                                detailRow(item, isFailure: false)
                                if index < report.skipped.count - 1 {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .background(Color.appleSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appleDivider, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxHeight: .infinity)
            }
        }
        // 撑满标题与底部按钮之间的全部空间：结果条数少时卡片也铺满，
        // 不会在底部留出一大块空白
        .frame(maxHeight: .infinity)
    }

    private var successState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30))
                .foregroundStyle(Color.appleSuccess)
            Text("全部 \(report.succeeded) 个文件压缩成功")
                .font(.system(size: 13))
                .foregroundStyle(Color.appleSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.appleSoft)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func detailRow(_ item: CompressionFailure, isFailure: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isFailure ? "xmark.circle.fill" : "minus.circle")
                .font(.system(size: 12))
                .foregroundStyle(isFailure ? Color.red.opacity(0.8) : Color.appleMuted)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(isFailure ? Color.red.opacity(0.85) : Color.appleSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.path)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appleMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("在 Finder 中显示")
            .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - 底部操作

    private var footer: some View {
        HStack(spacing: 10) {
            secondaryButton(copied ? "已复制" : "复制清单") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.plainText(), forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            }

            secondaryButton("保存报告") {
                if let url = report.writeToDisk() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }

            if !report.failures.isEmpty {
                secondaryButton("定位失败文件") {
                    let urls = report.failures.map { URL(fileURLWithPath: $0.path) }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Text("完成")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 32)
                    .background(Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.appleSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 980))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 窗口控制

@MainActor
final class CompressionResultWindowController {
    static let shared = CompressionResultWindowController()

    private var window: NSWindow?
    private var escMonitor: Any?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    var isShowing: Bool { window?.isVisible ?? false }

    func show(report: CompressionReport) {
        // 先收掉上一块，避免连点叠窗口
        close()

        let size = CGSize(width: 560, height: 480)
        let view = CompressionResultView(report: report) { [weak self] in
            self?.close()
        }
        let window = HotKeyDispatcher.makePopupStyledWindow(content: view, size: size)
        // 与功能弹窗同层级：从「压缩参数」弹窗（screenSaver）里打开时不能被自己盖住
        window.level = .screenSaver
        window.center()

        // 无边框窗口没有红色关闭按钮，Esc 与右上角 × 是仅有的两种退出方式
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard event.keyCode == 53, window?.isKeyWindow == true else { return event }
            self?.close()
            return nil
        }
        // 右上角 × 走 PopoverCloseButton 直接 close()，不经过本控制器，这里统一收尾
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.teardown()
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window?.close()
        teardown()
    }

    /// 只清理引用与监听，不关窗口（窗口已在关闭流程中时调用）
    private func teardown() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        window = nil
    }
}
