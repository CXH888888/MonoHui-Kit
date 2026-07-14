import SwiftUI
import ApplicationServices
import UserNotifications

struct SettingsView: View {
    @State private var installedActions: Set<String> = []
    @State private var operationInProgress = false
    @State private var hasAccessibilityPermission = false
    @State private var hasNotificationPermission = false
    @State private var showDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                permissionSection
                serviceMenuSection
                aboutSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appleCanvas)
        .onAppear {
            refreshStatus()
            refreshPermissions()
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }

    // MARK: - 顶部条：标题 + 诊断日志按钮

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Text("管理权限、服务菜单与诊断日志")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            Spacer()
            Button {
                showDiagnostics = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 13, weight: .regular))
                    Text("诊断日志")
                        .font(.system(size: 13, weight: .regular))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Color.appleBlue)
                .clipShape(RoundedRectangle(cornerRadius: 980))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 权限（surface 卡片）

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("权限")
            VStack(spacing: 8) {
                permissionRow(
                    name: "辅助功能",
                    description: "用于日期文件夹自动进入重命名模式",
                    granted: hasAccessibilityPermission,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                permissionRow(
                    name: "通知",
                    description: "用于压缩完成通知",
                    granted: hasNotificationPermission,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.notifications"
                )
            }
        }
    }

    private func permissionRow(name: String, description: String, granted: Bool, settingsURL: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .frame(width: 16, height: 16)
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            Spacer()
            Button("去设置") {
                if let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.appleBlue)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 服务菜单（surface 卡片 + 内部分组卡片）

    private var serviceMenuSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("服务菜单")
            Text("每个服务项可独立安装或移除，安装后出现在 Finder 右键 → 服务中")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)

            // 分组：图片
            serviceGroup(title: "图片", actions: CompressModule.serviceActions)

            // 分组：文件夹
            serviceGroup(title: "文件夹", actions: DateFolderModule.serviceActions)

            HStack(spacing: 10) {
                Button(action: installAll) {
                    Text("全部安装")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Color.appleBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 980))
                }
                .buttonStyle(.plain)
                .disabled(operationInProgress)

                Button(action: uninstallAll) {
                    Text("全部移除")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.appleInk)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Color.appleSurface2)
                        .clipShape(RoundedRectangle(cornerRadius: 980))
                }
                .buttonStyle(.plain)
                .disabled(operationInProgress)
            }
            .padding(.top, 4)
        }
    }

    private func serviceGroup(title: String, actions: [ServiceAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appleSoft)
            ForEach(actions, id: \.id) { action in
                serviceRow(action)
            }
        }
        .padding(14)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func serviceRow(_ action: ServiceAction) -> some View {
        let isInstalled = installedActions.contains(action.id)
        return HStack(spacing: 10) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .frame(width: 14, height: 14)
                .foregroundStyle(isInstalled ? .green : Color.appleMuted)
            Text(action.menuName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Spacer()
            if isInstalled {
                Button("移除") { uninstallAction(action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.red.opacity(0.8))
                    .disabled(operationInProgress)
            } else {
                Button("安装") { installAction(action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleBlue)
                    .disabled(operationInProgress)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.appleCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 关于（surface 卡片）

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("关于")
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("QuickActions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appleInk)
                    Text("快捷右键工具箱")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                    Text("版本 \(appVersion)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.appleMuted)
                }
            }
            .padding(14)
            .background(Color.appleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Section header（micro 样式：11/500/uppercase/0.066em tracking）

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color.appleMuted)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
    }

    private func refreshStatus() {
        installedActions = Set(ModuleRegistry.allActions.filter { ServiceMenuInstaller.isInstalled($0) }.map { $0.id })
    }

    private func refreshPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                hasNotificationPermission = settings.authorizationStatus == .authorized
            }
        }
    }

    private func installAction(_ action: ServiceAction) {
        operationInProgress = true
        Task {
            do {
                try await Task.detached { try ServiceMenuInstaller.install(actions: [action]) }.value
                await MainActor.run {
                    refreshStatus()
                    operationInProgress = false
                }
            } catch {
                await MainActor.run { operationInProgress = false }
            }
        }
    }

    private func uninstallAction(_ action: ServiceAction) {
        operationInProgress = true
        Task {
            do {
                try await Task.detached { try ServiceMenuInstaller.uninstall(actions: [action]) }.value
                await MainActor.run {
                    refreshStatus()
                    operationInProgress = false
                }
            } catch {
                await MainActor.run { operationInProgress = false }
            }
        }
    }

    private func installAll() {
        operationInProgress = true
        Task {
            do {
                try await Task.detached { try ServiceMenuInstaller.install(actions: ModuleRegistry.allActions) }.value
                await MainActor.run {
                    refreshStatus()
                    operationInProgress = false
                }
            } catch {
                await MainActor.run { operationInProgress = false }
            }
        }
    }

    private func uninstallAll() {
        operationInProgress = true
        Task {
            do {
                try await Task.detached { try ServiceMenuInstaller.uninstall(actions: ModuleRegistry.allActions) }.value
                await MainActor.run {
                    refreshStatus()
                    operationInProgress = false
                }
            } catch {
                await MainActor.run { operationInProgress = false }
            }
        }
    }
}
