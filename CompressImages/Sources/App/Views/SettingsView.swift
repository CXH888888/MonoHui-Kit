import SwiftUI
import ApplicationServices
import UserNotifications

struct SettingsView: View {
    @State private var installedActions: Set<String> = []
    @State private var operationInProgress = false
    @State private var hasAccessibilityPermission = false
    @State private var hasNotificationPermission = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                permissionSection
                serviceMenuSection
                aboutSection
                DiagnosticsView()
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appleCanvas)
        .onAppear {
            refreshStatus()
            refreshPermissions()
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("权限")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.appleInk)

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

    private func permissionRow(name: String, description: String, granted: Bool, settingsURL: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            Spacer()
            Button("去设置") {
                if let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.appleBlue)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var serviceMenuSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("服务菜单")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            Text("每个服务项可独立安装或移除，安装后出现在 Finder 右键 → 服务中")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)

            VStack(alignment: .leading, spacing: 10) {
                Text("图片")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                ForEach(CompressModule.serviceActions, id: \.id) { action in
                    serviceRow(action)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("文件夹")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                ForEach(DateFolderModule.serviceActions, id: \.id) { action in
                    serviceRow(action)
                }
            }

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

    private func serviceRow(_ action: ServiceAction) -> some View {
        let isInstalled = installedActions.contains(action.id)
        return HStack(spacing: 10) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle")
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
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关于")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.appleInk)

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
        }
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
