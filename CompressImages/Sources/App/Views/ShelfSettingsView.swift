import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 中转站设置页（主窗口右侧）
struct ShelfSettingsView: View {
    // 用 @AppStorage 替代 @State + didSet：
    // @State 的 didSet 不会触发（修改的是内部 storage），导致 UserDefaults 永远不写入
    // @AppStorage 自动双向同步 UserDefaults，UI 修改即时写入，外部修改即时更新 UI
    @AppStorage("shelf_enabled") private var shelfEnabled: Bool = false
    @AppStorage("shelf_auto_hide_delay") private var autoHideDelay: Double = 1.5
    @AppStorage("shelf_panel_width") private var panelWidth: Double = 140
    @AppStorage("shelf_panel_height") private var panelHeight: Double = 400
    @AppStorage("shelf_cleanup_on_exit") private var cleanupOnExit: Bool = true
    /// 移除方式：keep=放回原位 trash=移到 App 回收站（.history/）
    @AppStorage("shelf_remove_action") private var removeAction: String = "trash"
    @State private var rules: [AppRule] = AppRules.shared.rules
    /// 待添加的 App 信息（从 NSOpenPanel 选择后暂存，等待用户选格式确认）
    @State private var pendingApp: (name: String, bundleId: String)? = nil
    /// 新规则输入：输出格式
    @State private var newOutputFormat: String = "png"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                mainSwitchSection
                displaySection
                removeActionSection
                rulesSection
                cleanupSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
        .onAppear {
            // 监听中转站面板的「设置」按钮
            NotificationCenter.default.addObserver(
                forName: .openShelfSettings,
                object: nil,
                queue: .main
            ) { _ in
                // 主窗口已显示此页，无需额外操作
            }
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("文件暂存箱")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("左侧贴边的文件暂存区，支持拖拽与快速预览")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // MARK: - 总开关

    private var mainSwitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("总开关")
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用文件暂存箱")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.appleInk)
                        Text("在屏幕左侧显示贴边面板")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appleSoft)
                    }
                    Spacer()
                    Toggle("", isOn: $shelfEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: shelfEnabled) { _ in
                            applyShelfEnabled()
                        }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 显示设置

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("显示")
            VStack(spacing: 0) {
                HStack {
                    Text("自动隐藏延迟")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                    Spacer()
                    Text(String(format: "%.1f 秒", autoHideDelay))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleSoft)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                SectionDivider()

                Slider(value: $autoHideDelay, in: 0.5...5.0, step: 0.5) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("0.5s").font(.system(size: 10)).foregroundStyle(Color.appleSoft)
                } maximumValueLabel: {
                    Text("5s").font(.system(size: 10)).foregroundStyle(Color.appleSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                SectionDivider()

                HStack {
                    Text("面板高度")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                    Spacer()
                    Text("\(Int(panelHeight)) pt")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleSoft)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                SectionDivider()

                Slider(value: $panelHeight, in: 300...800, step: 20) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("300").font(.system(size: 10)).foregroundStyle(Color.appleSoft)
                } maximumValueLabel: {
                    Text("800").font(.system(size: 10)).foregroundStyle(Color.appleSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: panelHeight) { _ in
                    ShelfPanelController.shared.refreshPanel()
                }

                SectionDivider()

                HStack {
                    Text("面板宽度")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                    Spacer()
                    Text("\(Int(panelWidth)) pt")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleSoft)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                SectionDivider()

                Slider(value: $panelWidth, in: 120...240, step: 20) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("120").font(.system(size: 10)).foregroundStyle(Color.appleSoft)
                } maximumValueLabel: {
                    Text("240").font(.system(size: 10)).foregroundStyle(Color.appleSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: panelWidth) { _ in
                    ShelfPanelController.shared.refreshPanel()
                }
            }
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 移除方式

    private var removeActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("移除方式")
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("关闭/清空文件时")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.appleInk)
                        Text("本地文件的处理方式（缓存文件/文件夹始终进 App 回收站）")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appleSoft)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                SectionDivider()

                // 两个选项
                HStack(spacing: 8) {
                    removeOptionButton(
                        title: "放回原位",
                        subtitle: "仅从中转站移除，不动文件",
                        icon: "arrow.uturn.backward",
                        action: "keep"
                    )
                    removeOptionButton(
                        title: "移到 App 回收站",
                        subtitle: "进入 App 回收站，超量自动清理",
                        icon: "trash",
                        action: "trash"
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 移除方式选项按钮
    private func removeOptionButton(title: String, subtitle: String, icon: String, action: String) -> some View {
        let isSelected = removeAction == action
        return Button {
            removeAction = action
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.appleSoft)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.appleBlue.opacity(0.12) : Color.appleSurface2.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.appleBlue : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.appleBlue : Color.appleInk)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 清理

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("清理")
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("退出时自动清理")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.appleInk)
                        Text("App 退出时清除未锁定的临时文件")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appleSoft)
                    }
                    Spacer()
                    Toggle("", isOn: $cleanupOnExit)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                SectionDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("查看缓存文件夹")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.appleInk)
                        Text("误关闭后可手动删除残留的暂存图片")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appleSoft)
                    }
                    Spacer()
                    Button {
                        openCacheFolder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("在 Finder 中打开")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appleBlue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 在 Finder 中打开缓存文件夹
    private func openCacheFolder() {
        let url = ShelfStore.cacheDirectory
        // 确保目录存在
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 应用规则

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("应用规则")
                Spacer()
                // 添加规则按钮：点击弹出 NSOpenPanel 选择本地 App
                Button {
                    pickApp()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.app")
                            .font(.system(size: 10, weight: .medium))
                        Text("选择 App 添加")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appleBlue)
                }
                .buttonStyle(.plain)

                Button("恢复默认") {
                    AppRules.shared.resetToDefault()
                    rules = AppRules.shared.rules
                    pendingApp = nil
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.appleBlue)
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                // 选择 App 后的内联确认表单（只选格式）
                if let pending = pendingApp {
                    addRuleForm(pending)
                    SectionDivider()
                }

                ForEach(Array(rules.enumerated()), id: \.element.id) { idx, rule in
                    if idx > 0 || pendingApp != nil { SectionDivider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.appName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.appleInk)
                            Text(rule.bundleId)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.appleSoft)
                        }
                        Spacer()
                        // 格式选择
                        Picker("", selection: Binding(
                            get: { rules[idx].outputFormat },
                            set: { newValue in
                                rules[idx].outputFormat = newValue
                                AppRules.shared.save(rules)
                            }
                        )) {
                            Text("原格式").tag("original")
                            Text("PNG").tag("png")
                            Text("JPG").tag("jpg")
                            Text("SVG").tag("svg")
                            Text("PDF").tag("pdf")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                        .labelsHidden()

                        // 启用开关
                        Toggle("", isOn: Binding(
                            get: { rules[idx].enabled },
                            set: { newValue in
                                rules[idx].enabled = newValue
                                AppRules.shared.save(rules)
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()

                        // 删除按钮
                        Button {
                            deleteRule(at: idx)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("删除此规则")
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
            }
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 选择 App 后的内联确认表单：显示已选 App 信息 + 格式选择 + 确认/取消
    private func addRuleForm(_ pending: (name: String, bundleId: String)) -> some View {
        let alreadyExists = rules.contains { $0.bundleId == pending.bundleId }
        return HStack(spacing: 10) {
            // 已选 App 图标 + 名称 + Bundle ID
            Image(systemName: "app.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.appleBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Text(pending.bundleId)
                    .font(.system(size: 11))
                    .foregroundStyle(alreadyExists ? Color.red.opacity(0.7) : Color.appleSoft)
            }
            Spacer()
            // 格式选择
            Picker("格式", selection: $newOutputFormat) {
                Text("原格式").tag("original")
                Text("PNG").tag("png")
                Text("JPG").tag("jpg")
                Text("SVG").tag("svg")
                Text("PDF").tag("pdf")
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .labelsHidden()

            // 确认添加按钮
            Button {
                confirmAddRule()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(alreadyExists ? Color.gray.opacity(0.4) : Color.appleBlue)
            }
            .buttonStyle(.plain)
            .disabled(alreadyExists)
            .help(alreadyExists ? "该 App 规则已存在" : "确认添加")

            // 取消按钮
            Button {
                pendingApp = nil
                newOutputFormat = "png"
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.appleSoft)
            }
            .buttonStyle(.plain)
            .help("取消")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    /// 弹出 NSOpenPanel 让用户从 /Applications 选择 App
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "选择要添加规则的应用程序"
        panel.message = "从应用程序文件夹中选择一个 .app"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // 默认打开 /Applications 文件夹
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        // 从 .app 的 Info.plist 提取 bundleId 和应用名
        let bundle = Bundle(url: url)
        let bundleId = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        let appName = (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        // 暂存待添加的 App 信息，显示内联表单让用户选格式
        pendingApp = (name: appName, bundleId: bundleId)
        newOutputFormat = "png"
    }

    /// 确认添加新规则
    private func confirmAddRule() {
        guard let pending = pendingApp else { return }
        guard !rules.contains(where: { $0.bundleId == pending.bundleId }) else { return }
        let newRule = AppRule(
            bundleId: pending.bundleId,
            appName: pending.name,
            outputFormat: newOutputFormat,
            enabled: true
        )
        rules.append(newRule)
        AppRules.shared.save(rules)
        pendingApp = nil
        newOutputFormat = "png"
    }

    /// 删除指定规则
    private func deleteRule(at idx: Int) {
        guard idx < rules.count else { return }
        rules.remove(at: idx)
        AppRules.shared.save(rules)
    }

    // MARK: - 操作

    private func applyShelfEnabled() {
        if shelfEnabled {
            ShelfPanelController.shared.enable()
        } else {
            ShelfPanelController.shared.disable()
        }
    }
}
