import SwiftUI
import AppKit

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    private let log = AppLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    manualTestSection
                    logListSection
                }
                .padding(24)
            }
        }
        .frame(width: 760, height: 620)
        .background(Color.appleCanvas)
    }

    // MARK: - 标题区（弹窗顶部，title-lg 21/600）

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("诊断日志")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Text("快捷键与服务菜单触发会记录到这里。点下方按钮模拟触发，看链路是否通。")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("清空") { log.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
                Button("复制全部") { log.copyToPasteboard() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appleSoft)
                        .frame(width: 28, height: 28)
                        .background(Color.appleSurface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(20)
        .background(Color.appleSurface)
    }

    // MARK: - 手动测试（surface 卡片包裹）

    private var manualTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手动触发测试")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            HStack(spacing: 8) {
                testButton("快速压缩", action: .compressQuick)
                testButton("压缩为…", action: .compressInteractive)
                testButton("新建文件夹弹窗", action: .datefolderInteractive)
                Spacer()
            }

            HStack(spacing: 8) {
                utilityButton("读 Finder 选中项") {
                    let urls = FinderSelection.currentSelection()
                    log.log("手动读取 Finder 选中项：\(urls.count) 个 \(urls.prefix(3).map { $0.lastPathComponent }.joined(separator: ", "))", category: "Finder")
                }
                utilityButton("读 Finder 当前目录") {
                    if let dir = FinderSelection.currentFinderDirectory() {
                        log.log("手动读取 Finder 当前目录：\(dir.path)", category: "Finder")
                    } else {
                        log.log("手动读取 Finder 当前目录失败", category: "Finder", level: .warn)
                    }
                }
                utilityButton("重新注册热键") {
                    HotKeyManager.shared.registerAllFromSettings()
                    log.log("手动触发重新注册热键完成", category: "HotKey")
                }
            }
        }
        .padding(16)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func testButton(_ title: String, action: HotKeyActionId) -> some View {
        Button(title) {
            log.log("手动触发：\(action.displayName)", category: "Dispatcher", level: .hot)
            HotKeyDispatcher.shared.dispatch(actionId: action)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(Color.appleInk)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color.appleCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.appleBorder, lineWidth: 1)
        )
    }

    private func utilityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.appleBlue)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.appleCanvas)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                .stroke(Color.appleBorder, lineWidth: 1)
            )
    }

    // MARK: - 日志列表（surface 卡片包裹）

    private var logListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("日志")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Text("最近 \(log.entries.count) 条，倒序")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.entries.reversed()) { entry in
                        logRow(entry)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
            .background(Color.black.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func logRow(_ entry: AppLog.Entry) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatter.string(from: entry.timestamp))
                .foregroundStyle(Color.appleMuted)
            Text("[\(entry.category)]")
                .foregroundStyle(Color.appleSoft)
            Text(entry.level.rawValue)
                .foregroundStyle(levelColor(entry.level))
            Text(entry.message)
                .foregroundStyle(Color.appleInk)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
    }

    private func levelColor(_ level: AppLog.Entry.Level) -> Color {
        switch level {
        case .error: return .red
        case .warn: return .orange
        case .success: return .green
        case .hot: return Color.appleBlue
        default: return Color.appleSoft
        }
    }
}
