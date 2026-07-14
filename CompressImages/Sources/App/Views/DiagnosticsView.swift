import SwiftUI
import AppKit

struct DiagnosticsView: View {
    private let log = AppLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            manualTestSection
            logListSection
        }
        .padding(20)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 标题区

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("诊断日志")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Text("快捷键与服务菜单触发会记录到这里。点下方按钮模拟触发，看链路是否通。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("清空") { log.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button("复制全部") { log.copyToPasteboard() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - 手动测试按钮

    private var manualTestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手动触发测试")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.appleSoft)
            HStack(spacing: 8) {
                testButton("快速压缩", action: .compressQuick)
                testButton("压缩为…", action: .compressInteractive)
                testButton("新建文件夹弹窗", action: .datefolderInteractive)
                Spacer()
            }
            HStack(spacing: 8) {
                Button("读 Finder 选中项") {
                    let urls = FinderSelection.currentSelection()
                    log.log("手动读取 Finder 选中项：\(urls.count) 个 \(urls.prefix(3).map { $0.lastPathComponent }.joined(separator: ", "))", category: "Finder")
                }
                Button("读 Finder 当前目录") {
                    if let dir = FinderSelection.currentFinderDirectory() {
                        log.log("手动读取 Finder 当前目录：\(dir.path)", category: "Finder")
                    } else {
                        log.log("手动读取 Finder 当前目录失败", category: "Finder", level: .warn)
                    }
                }
                Button("重新注册热键") {
                    HotKeyManager.shared.registerAllFromSettings()
                    log.log("手动触发重新注册热键完成", category: "HotKey")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.appleBlue)
        }
        .padding(12)
        .background(Color.appleCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func testButton(_ title: String, action: HotKeyActionId) -> some View {
        Button(title) {
            log.log("手动触发：\(action.displayName)", category: "Dispatcher", level: .hot)
            HotKeyDispatcher.shared.dispatch(actionId: action)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(Color.appleInk)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 日志列表

    private var logListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日志（最近 \(log.entries.count) 条，倒序）")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                Spacer()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.entries.reversed()) { entry in
                        logRow(entry)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 360)
            .padding(8)
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
            Text(entry.message)
                .foregroundStyle(Color.appleInk)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
    }
}
