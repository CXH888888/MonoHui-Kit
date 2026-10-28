import SwiftUI
import ApplicationServices
import UserNotifications

struct SettingsView: View {
    @State private var installedActions: Set<String> = []
    @State private var operationInProgress = false
    @State private var hasAccessibilityPermission = false
    @State private var hasAutomationPermission = false
    @State private var hasNotificationPermission = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                permissionSection
                serviceMenuSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
        .onAppear {
            refreshStatus()
            refreshPermissions()
        }
        // 从系统设置授权回来时刷新状态，否则权限行会一直停在旧的「未授权」
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    // MARK: - 顶部条：标题

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("管理权限与服务菜单")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // MARK: - 分隔线

    private var divider: some View { SectionDivider() }

    // MARK: - 权限（surface 卡片 + border，功能行用 divider 分隔）

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("权限")
            Text("点「去设置」后，系统设置窗口下方会贴出一块可拖拽的卡片：把里面的 App 图标拖进授权列表即可。卡片跟着系统设置窗口走，切到别的 App 会自动收起。")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -6)
            VStack(spacing: 0) {
                permissionRow(
                    name: "自动化（Finder）",
                    description: "读取 Finder 选中文件——快捷键与圆环的必需权限",
                    granted: hasAutomationPermission,
                    pane: .automation
                )
                divider
                permissionRow(
                    name: "辅助功能",
                    description: "用于日期文件夹自动进入重命名模式",
                    granted: hasAccessibilityPermission,
                    pane: .accessibility
                )
                divider
                permissionRow(
                    name: "通知",
                    description: "用于压缩完成通知",
                    granted: hasNotificationPermission,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.notifications"
                )
            }
            .padding(.vertical, 4)
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func permissionRow(
        name: String,
        description: String,
        granted: Bool,
        pane: PermissionPane? = nil,
        settingsURL: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            Spacer()
            Button("去设置") {
                if let pane {
                    // 系统设置的授权列表不一定显示本 App，跟着弹一块可拖拽的助手卡片
                    pane.openSettings()
                    let check: (() -> Bool)? = pane == .accessibility ? { AXIsProcessTrusted() } : nil
                    PermissionDragAssistant.shared.show(for: pane, grantedCheck: check)
                } else if let settingsURL, let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.appleBlue)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    // MARK: - 服务菜单（surface 卡片 + border，功能行用 divider 分隔）

    private var serviceMenuSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("服务菜单")
            Text("每个服务项可独立安装或移除，安装后出现在 Finder 右键 → 服务中")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .padding(.top, -6)

            VStack(alignment: .leading, spacing: 0) {
                // 分组：图片
                serviceGroup(title: "图片", actions: CompressModule.serviceActions)
                divider
                // 分组：文件夹
                serviceGroup(title: "文件夹", actions: DateFolderModule.serviceActions)
            }
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

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
            .padding(.top, 2)
        }
    }

    private func serviceGroup(title: String, actions: [ServiceAction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appleSoft)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                serviceRow(action)
                if index < actions.count - 1 {
                    divider
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func serviceRow(_ action: ServiceAction) -> some View {
        let isInstalled = installedActions.contains(action.id)
        return HStack(spacing: 12) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .frame(width: 18, height: 18)
                .foregroundStyle(isInstalled ? .green : Color.appleMuted)
            Text(action.menuName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Spacer()
            if isInstalled {
                Button("移除") { uninstallAction(action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.red.opacity(0.8))
                    .disabled(operationInProgress)
            } else {
                Button("安装") { installAction(action) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleBlue)
                    .disabled(operationInProgress)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - Section header（13/semibold，与功能行形成层次）

    private func sectionHeader(_ text: String) -> some View { SectionHeader(text) }

    private func refreshStatus() {
        installedActions = Set(ModuleRegistry.allActions.filter { ServiceMenuInstaller.isInstalled($0) }.map { $0.id })
    }

    private func refreshPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        // 会触发系统授权弹窗（首次），这正是想要的引导效果
        hasAutomationPermission = AutomationPermission.canControlFinder()
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
