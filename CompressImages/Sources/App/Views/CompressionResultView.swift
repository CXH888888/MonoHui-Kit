import SwiftUI
import AppKit

/// 批量压缩结果窗口：失败文件逐个列出（文件名 + 原因 + 路径），
/// 解决「提示失败 3 个但不知道是哪 3 个、为什么」。
struct CompressionResultView: View {
    let report: CompressionReport
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 520)
        .background(Color.appleCanvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(report.failedCount > 0 ? Color.orange : Color.appleSuccess)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.cancelled ? "压缩已取消" : (report.failedCount > 0 ? "部分文件压缩失败" : "压缩完成"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Text("\(report.summaryLine) · 耗时 \(report.elapsedText)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appleSoft)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if report.failures.isEmpty && report.skipped.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.appleSuccess)
                Text("全部 \(report.succeeded) 个文件压缩成功")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appleSoft)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !report.failures.isEmpty {
                        sectionTitle("失败 \(report.failures.count)")
                        ForEach(report.failures) { failure in
                            failureRow(failure, isFailure: true)
                            Divider().padding(.leading, 16)
                        }
                    }
                    if !report.skipped.isEmpty {
                        sectionTitle("跳过 \(report.skipped.count)")
                        ForEach(report.skipped) { item in
                            failureRow(item, isFailure: false)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.appleSoft)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func failureRow(_ failure: CompressionFailure, isFailure: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isFailure ? "xmark.circle.fill" : "minus.circle")
                .font(.system(size: 13))
                .foregroundStyle(isFailure ? Color.red.opacity(0.8) : Color.appleMuted)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(failure.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(failure.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(isFailure ? Color.red.opacity(0.85) : Color.appleSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Text(failure.path)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appleMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: failure.path)])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appleSoft)
            }
            .buttonStyle(.plain)
            .help("在 Finder 中显示")
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.plainText(), forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Text(copied ? "已复制" : "复制清单")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
            }
            .buttonStyle(.plain)

            Button {
                if let url = report.writeToDisk() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Text("保存报告")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
            }
            .buttonStyle(.plain)

            if !report.failures.isEmpty {
                Button {
                    let urls = report.failures.map { URL(fileURLWithPath: $0.path) }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                } label: {
                    Text("定位失败文件")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleInk)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Color.appleSurface2)
                        .clipShape(RoundedRectangle(cornerRadius: 980))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: onClose) {
                Text("完成")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 32)
                    .background(Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.appleSurface)
    }
}

@MainActor
final class CompressionResultWindowController {
    static let shared = CompressionResultWindowController()

    private var window: NSWindow?

    private init() {}

    var isShowing: Bool { window?.isVisible ?? false }

    func show(report: CompressionReport) {
        window?.close()

        let view = CompressionResultView(report: report) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "压缩结果"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
