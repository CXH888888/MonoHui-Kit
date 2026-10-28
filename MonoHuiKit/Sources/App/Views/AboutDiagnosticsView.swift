import SwiftUI
import AppKit

struct AboutDiagnosticsView: View {
    @State private var showDiagnostics = false
    @State private var repoField = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                aboutSection
                updateSection
                diagnosticsSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }

    // MARK: - 顶部条

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("关于与诊断")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("应用信息与诊断日志")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View { SectionHeader(text) }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("关于")
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("MonoHui-Kit")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appleInk)
                    Text("快捷右键工具箱")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                    Text("版本 \(appVersion)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleMuted)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 软件更新

    private var updateSection: some View {
        let service = UpdateService.shared

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("软件更新")

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(updateTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appleInk)
                    Text(updateDetail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                        .lineLimit(2)

                    if case .downloading(let progress) = service.state {
                        ProgressView(value: progress)
                            .frame(width: 240)
                            .padding(.top, 4)
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.appleMuted)
                    }

                    if case .failed = service.state {
                        Button("在浏览器中手动下载") {
                            NSWorkspace.shared.open(UpdateService.releasePageURL)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appleBlue)
                        .padding(.top, 2)
                    }
                }
                Spacer()

                updateActionButton
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            updateSourceRow
        }
    }

    /// 更新源可改：换仓库/换账号测试时不必重新打包
    private var updateSourceRow: some View {
        HStack(spacing: 8) {
            Text("更新源")
                .font(.system(size: 12))
                .foregroundStyle(Color.appleSoft)

            TextField("owner/repo", text: $repoField)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.appleInk)
                .padding(.horizontal, 8)
                .frame(width: 220, height: 26)
                .background(Color.appleSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.appleDivider, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .onSubmit { saveRepoSlug() }

            Button("保存") { saveRepoSlug() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appleBlue)

            Button("恢复默认") {
                repoField = "\(UpdateService.defaultOwner)/\(UpdateService.defaultRepo)"
                saveRepoSlug()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color.appleMuted)

            Spacer()

            Text("支持粘贴仓库 URL，留空即默认")
                .font(.system(size: 11))
                .foregroundStyle(Color.appleMuted)
        }
        .onAppear { repoField = UpdateService.repoSlug }
    }

    private func saveRepoSlug() {
        UpdateService.shared.applyRepoSlug(repoField)
        repoField = UpdateService.repoSlug
    }

    private var updateTitle: String {
        switch UpdateService.shared.state {
        case .idle:                  return "检查更新"
        case .checking:              return "正在检查…"
        case .upToDate:              return "已是最新版本"
        case .available(let version): return "发现新版本 \(version)"
        case .downloading:           return "正在下载…"
        case .installing:            return "正在安装，应用即将重启"
        case .failed:                return "更新失败"
        }
    }

    private var updateDetail: String {
        switch UpdateService.shared.state {
        case .idle:                  return "当前版本 v\(UpdateService.shared.currentVersion)"
        case .checking:              return "正在连接 GitHub Releases"
        case .upToDate:              return "当前版本 v\(UpdateService.shared.currentVersion)"
        case .available:             return "点击右侧按钮自动下载并安装，完成后应用会自动重启"
        case .downloading:           return "下载完成后会自动挂载安装并重启"
        case .installing:            return "请不要关闭应用，替换完成后会自动重新启动"
        case .failed(let message):   return message
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch UpdateService.shared.state {
        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 88)
        default:
            Button(updateButtonLabel) {
                Task { await UpdateService.shared.handlePrimaryAction() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Color.appleBlue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var updateButtonLabel: String {
        switch UpdateService.shared.state {
        case .available: return "下载并安装"
        case .failed:    return "重试"
        default:         return "检查更新"
        }
    }

    // MARK: - 诊断日志

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("诊断")
            Text("查看运行日志与手动测试服务菜单触发")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .padding(.top, -6)

            Button {
                showDiagnostics = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 14, weight: .regular))
                    Text("打开诊断日志")
                        .font(.system(size: 14, weight: .regular))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Color.appleBlue)
                .clipShape(RoundedRectangle(cornerRadius: 980))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
