import SwiftUI
import AppKit
import Carbon

struct HotKeySettingsView: View {
    @Environment(AppState.self) var state

    // 当前正在录制的 actionId；nil 表示未在录制
    @State private var recordingId: HotKeyActionId?
    // 录制捕获的组合
    @State private var recordedCombo: KeyCombination?
    // 错误/冲突提示
    @State private var toastMessage: String?
    @State private var toastIsError = false

    // 触发 UI 重新渲染（@AppStorage 的值变化会自动触发，但读取时需要刷新）
    @State private var refreshTrigger = 0
    // 录制键盘事件的 monitor 引用（避免泄漏）
    @State private var keyMonitor: Any?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                masterToggleSection
                launchAtLoginSection
                shortcutListSection
                conflictInfoSection
                aboutSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appleCanvas)
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(toastIsError ? Color.red.opacity(0.85) : Color.appleInk.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 监听菜单栏的"打开设置"通知
        .onReceive(NotificationCenter.default.publisher(for: .toggleHotKeyFromStatusBar)) { note in
            if let enabled = note.userInfo?["enabled"] as? Bool {
                state.hotKeyEnabled = enabled
                refreshTrigger += 1
            }
        }
    }

    // MARK: - 总开关

    private var masterToggleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("全局快捷键")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { state.hotKeyEnabled },
                    set: { newValue in
                        state.hotKeyEnabled = newValue
                        refreshTrigger += 1
                        showToast(newValue ? "已启用，App 驻留菜单栏" : "已禁用", error: false)
                    }
                ))
                .labelsHidden()
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.hotKeyEnabled ? "已启用" : "未启用")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                    Text("启用后 App 驻留菜单栏，在 Finder 选中文件按快捷键即可触发对应功能")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.appleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - 开机自启动

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    private var launchAtLoginSection: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { newValue in
                    if LaunchAtLogin.setEnabled(newValue) {
                        launchAtLoginEnabled = newValue
                        showToast(newValue ? "开机自启动已启用" : "开机自启动已禁用", error: false)
                    } else {
                        showToast("设置失败，请在系统设置中手动添加", error: true)
                    }
                }
            ))
            .labelsHidden()
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 4) {
                Text("开机自启动")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Text("开机后自动驻留菜单栏，快捷键随时可用")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .disabled(!state.hotKeyEnabled)
        .opacity(state.hotKeyEnabled ? 1.0 : 0.5)
    }

    // MARK: - 快捷键列表

    private var shortcutListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            let categories = Dictionary(grouping: HotKeyActionId.allCases, by: { $0.category })
            ForEach(categories.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: 10) {
                    Text(category)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appleSoft)
                    ForEach(categories[category] ?? [], id: \.rawValue) { actionId in
                        shortcutRow(actionId)
                    }
                }
            }
        }
        .disabled(!state.hotKeyEnabled)
        .opacity(state.hotKeyEnabled ? 1.0 : 0.5)
    }

    private func shortcutRow(_ actionId: HotKeyActionId) -> some View {
        let combo = HotKeyManager.shared.currentCombination(for: actionId)
        let isRecording = recordingId == actionId

        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.opacity(0.001))
                .font(.system(size: 13))
            Text(actionId.displayName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Spacer()

            // 当前快捷键显示
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

            // 录制 / 保存 / 取消 按钮
            if isRecording {
                Button("取消") {
                    recordingId = nil
                    recordedCombo = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleSoft)
            } else {
                Button("录制") {
                    recordingId = actionId
                    recordedCombo = nil
                    installRecorder()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleBlue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .id(refreshTrigger)
    }

    // MARK: - 冲突信息

    private var conflictInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("冲突检查")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appleSoft)

            let conflicts = detectConflicts()
            if conflicts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("无冲突")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.appleInk)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.appleSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(conflicts, id: \.self) { msg in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.appleInk)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.appleSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("使用说明")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appleSoft)
            VStack(alignment: .leading, spacing: 6) {
                Text("• 启用全局快捷键后，App 将驻留菜单栏（Dock 图标隐藏）")
                Text("• 在 Finder 中选中文件，按对应快捷键即可触发")
                Text("• 默认快捷键：⌥⇧C 快速压缩 / ⌥⇧I 压缩为… / ⌥⇧N 新建文件夹弹窗")
                Text("• 建议使用 ⌥⇧ 组合，避免与系统快捷键冲突")
                Text("• 服务菜单作为备用入口仍可使用")
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.appleSoft)
            .padding(14)
            .background(Color.appleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - 录制键盘事件

    private func installRecorder() {
        // 移除上次未清理的 monitor
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        // 用 NSEvent local monitor 监听 App 内按键（设置窗口内按键）
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard self.recordingId != nil else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func stopRecorder() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Esc 取消
        if event.keyCode == 53 {
            recordingId = nil
            recordedCombo = nil
            stopRecorder()
            return true
        }

        // 至少一个修饰键
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

        // App 内冲突检测
        for other in HotKeyActionId.allCases where other != actionId {
            if let otherCombo = HotKeyManager.shared.currentCombination(for: other),
               otherCombo == combo {
                showToast("与「\(other.displayName)」冲突", error: true)
                recordingId = nil
                stopRecorder()
                return true
            }
        }

        // 系统冲突检测
        if HotKeyManager.shared.hasConflict(combo) {
            showToast("与系统或其他应用冲突", error: true)
            recordingId = nil
            stopRecorder()
            return true
        }

        // 保存并重新注册
        HotKeyManager.shared.saveCombination(combo, for: actionId)
        HotKeyManager.shared.registerAllFromSettings()
        StatusBarController.shared.refreshMenu()
        recordingId = nil
        stopRecorder()
        refreshTrigger += 1
        showToast("已保存：\(combo.displayName)", error: false)
        return true
    }

    // MARK: - 冲突检测

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

    // MARK: - Toast

    private func showToast(_ message: String, error: Bool) {
        withAnimation { toastMessage = message; toastIsError = error }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}
