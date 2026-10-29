import SwiftUI
import AppKit
import Carbon

struct HotKeySettingsView: View {
    @Environment(AppState.self) var state

    @State private var recordingId: HotKeyActionId?
    @State private var toastMessage: String?
    @State private var toastIsError = false
    @State private var refreshTrigger = 0
    @State private var keyMonitor: Any?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader
                startupSection
                shortcutListSection
                conflictInfoSection
                aboutSection
            }
            .pagePadding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(toastIsError ? Color.red.opacity(0.85) : Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleHotKeyFromStatusBar)) { note in
            if let enabled = note.userInfo?["enabled"] as? Bool {
                state.hotKeyEnabled = enabled
                refreshTrigger += 1
            }
        }
        .onDisappear {
            // 离开页面时清理 keyMonitor，防止切走后仍拦截全局键盘事件
            stopRecorder()
        }
    }

    // MARK: - 页面头部

    private var pageHeader: some View {
        PageHeader("快捷键", subtitle: "设置全局快捷键，启用后 App 驻留菜单栏")
    }

    private func sectionHeader(_ text: String) -> some View { SectionHeader(text) }

    private var divider: some View { SectionDivider() }

    // MARK: - 总开关
    //
    // 「开机自启动」已移到「设置 → 通用」：它是系统级行为（登录项），
    // 跟快捷键没有依赖关系，放在这里会被误读成"快捷键的子选项"。

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("总开关")
            VStack(spacing: 0) {
                settingRow(
                    title: "快捷键总开关",
                    detail: "启用后 App 驻留菜单栏，在 Finder 选中文件按快捷键即可触发对应功能"
                ) {
                    Toggle("", isOn: Binding(
                        get: { state.hotKeyEnabled },
                        set: { newValue in
                            state.hotKeyEnabled = newValue
                            refreshTrigger += 1
                            showToast(newValue ? "已启用，App 驻留菜单栏" : "已禁用", error: false)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                }
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

    /// 设置行：左标题 + 说明，右控件。和「设置」页的功能行同构
    private func settingRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            accessory()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    // MARK: - 快捷键列表（surface 卡片 + border，功能行用 divider 分隔）

    private var shortcutListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("快捷键列表")
            VStack(alignment: .leading, spacing: 0) {
                let categories = Dictionary(grouping: HotKeyActionId.allCases, by: { $0.category })
                let sortedCategories = categories.keys.sorted()
                ForEach(Array(sortedCategories.enumerated()), id: \.element) { catIndex, category in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(category)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.appleSoft)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        let actions = categories[category] ?? []
                        ForEach(Array(actions.enumerated()), id: \.element.rawValue) { index, actionId in
                            shortcutRow(actionId)
                            if index < actions.count - 1 {
                                divider
                            }
                        }
                    }
                    if catIndex < sortedCategories.count - 1 {
                        divider
                    }
                }
            }
            .padding(.bottom, 4)
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(!state.hotKeyEnabled)
            .opacity(state.hotKeyEnabled ? 1.0 : 0.5)
        }
    }

    private func shortcutRow(_ actionId: HotKeyActionId) -> some View {
        let combo = HotKeyManager.shared.currentCombination(for: actionId)
        let isRecording = recordingId == actionId

        return HStack(spacing: 12) {
            Text(actionId.displayName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Spacer()

            if isRecording {
                Text("按任意键组合…（Esc 取消）")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let combo = combo {
                Text(combo.displayName)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("未设置")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if isRecording {
                Button("取消") {
                    recordingId = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
            } else {
                Button("录制") {
                    recordingId = actionId
                    installRecorder()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleBlue)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .id(refreshTrigger)
    }

    // MARK: - 冲突信息（surface 卡片 + border）

    /// 冲突检查：**只在真有冲突时出现**。
    ///
    /// 必须用 `@ViewBuilder` 在顶层 `if`：如果返回一个"内容为空的 VStack"，
    /// 它自身高度虽然是 0，但外层 `VStack(spacing: 24)` 仍会把它当成一个子视图，
    /// 前后各留 24pt —— 表现就是「使用说明」上方凭空多出一大块空白。
    @ViewBuilder
    private var conflictInfoSection: some View {
        let conflicts = detectConflicts()
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("冲突检查")
                VStack(spacing: 0) {
                    ForEach(Array(conflicts.enumerated()), id: \.element) { index, msg in
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .frame(width: 20, height: 20)
                                .foregroundStyle(.orange)
                            Text(msg)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.appleInk)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        if index < conflicts.count - 1 {
                            divider
                        }
                    }
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
    }

    // MARK: - 使用说明（surface 卡片 + border）

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("使用说明")
            VStack(alignment: .leading, spacing: 8) {
                Text("• 启用全局快捷键后，App 将驻留菜单栏（Dock 图标隐藏）")
                Text("• 在 Finder 中选中文件，按对应快捷键即可触发")
                Text("• 默认快捷键：⌥⇧C 快速压缩 / ⌥⇧I 压缩为… / ⌥⇧N 新建文件夹弹窗 / ⌘R 快速改名")
                Text("• 建议使用 ⌥⇧ 组合，避免与系统快捷键冲突")
                Text("• 服务菜单作为备用入口仍可使用")
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.appleSoft)
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

    // MARK: - 录制键盘事件

    private func installRecorder() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard self.recordingId != nil else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func stopRecorder() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            recordingId = nil
            stopRecorder()
            return true
        }

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift)   { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option)  { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }

        guard modifiers != 0 else {
            showToast("至少需要一个修饰键（⌘/⇧/⌥/⌃）", error: true)
            return true
        }

        let combo = KeyCombination(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard let actionId = recordingId else { return true }

        for other in HotKeyActionId.allCases where other != actionId {
            if let otherCombo = HotKeyManager.shared.currentCombination(for: other),
               otherCombo == combo {
                showToast("与「\(other.displayName)」冲突", error: true)
                recordingId = nil
                stopRecorder()
                return true
            }
        }

        if HotKeyManager.shared.hasConflict(combo) {
            showToast("与系统或其他应用冲突", error: true)
            recordingId = nil
            stopRecorder()
            return true
        }

        HotKeyManager.shared.saveCombination(combo, for: actionId)
        HotKeyManager.shared.registerAllFromSettings()
        StatusBarController.shared.refreshMenu()
        recordingId = nil
        stopRecorder()
        refreshTrigger += 1
        showToast("已保存：\(combo.displayName)", error: false)
        return true
    }

    private func detectConflicts() -> [String] {
        var conflicts: [String] = []
        let allCombos: [(HotKeyActionId, KeyCombination)] = HotKeyActionId.allCases.compactMap {
            guard let c = HotKeyManager.shared.currentCombination(for: $0) else { return nil }
            return ($0, c)
        }
        for i in 0..<allCombos.count {
            for j in (i+1)..<allCombos.count {
                if allCombos[i].1 == allCombos[j].1 {
                    conflicts.append("\(allCombos[i].0.displayName) 与 \(allCombos[j].0.displayName) 相同（\(allCombos[i].1.displayName)）")
                }
            }
        }
        return conflicts
    }

    private func showToast(_ message: String, error: Bool) {
        withAnimation(Motion.enter) { toastMessage = message; toastIsError = error }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(Motion.leave) { toastMessage = nil }
        }
    }
}
