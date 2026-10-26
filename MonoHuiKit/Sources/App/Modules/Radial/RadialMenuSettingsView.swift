import SwiftUI
import AppKit

struct RadialMenuSettingsView: View {
    @Environment(AppState.self) var state
    @State private var settings = RadialMenuSettings.shared
    @State private var previewModel = RadialMenuModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                masterSection
                sectorSection
                actionSection
                previewSection
                tipsSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
        .onAppear { syncPreview() }
        .onChange(of: settings.sectorCount) { _, _ in syncPreview() }
        .onChange(of: settings.actionIds) { _, _ in syncPreview() }
        .onChange(of: settings.iconSize) { _, _ in syncPreview() }
        .onChange(of: settings.textSize) { _, _ in syncPreview() }
        .onChange(of: settings.enabled) { _, _ in
            // 关闭时立即释放快捷键，开启时立即注册
            HotKeyManager.shared.refreshForFrontmostApp()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("圆环菜单")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("按住快捷键唤出，移动鼠标选择，松开执行")
                .font(.system(size: 13))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // MARK: - 总开关

    private var masterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("总开关")

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.enabled ? "已启用" : "未启用")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appleInk)
                    Text("启用后按住触发快捷键即可唤出圆环")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appleSoft)
                }
                Spacer()
                Toggle("", isOn: $settings.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
            }
            .padding(16)
            .background(Color.appleSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appleDivider, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("触发快捷键")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                    Text("按住不放，移动到扇区后松开修饰键执行")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appleSoft)
                }
                Spacer()

                if let combo = HotKeyManager.shared.currentCombination(for: .radialMenu) {
                    Text(combo.displayName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.appleInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.appleSurface2)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("未设置")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appleMuted)
                }

                Button("修改") {
                    state.pendingSidebarItem = .hotkey
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.appleBlue)
            }
            .padding(16)
            .background(Color.appleSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appleDivider, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 外观

    private var sectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("外观")

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("扇区数量")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleInk)
                        .frame(width: 64, alignment: .leading)
                    ForEach(RadialMenuSettings.allowedCounts, id: \.self) { count in
                        PillButton(
                            label: "\(count) 个",
                            isSelected: settings.sectorCount == count,
                            action: { settings.sectorCount = count }
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                SectionDivider()

                HStack(spacing: 10) {
                    Text("圆环尺寸")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleInk)
                        .frame(width: 64, alignment: .leading)
                    ForEach(RadialMenuSettings.allowedSizes, id: \.self) { size in
                        PillButton(
                            label: sizeLabel(size),
                            isSelected: settings.menuSize == size,
                            action: { settings.menuSize = size }
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                SectionDivider()

                HStack(spacing: 10) {
                    Text("图标大小")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleInk)
                        .frame(width: 64, alignment: .leading)
                    ForEach(RadialMenuSettings.allowedIconSizes, id: \.self) { size in
                        PillButton(
                            label: presetLabel(size, in: RadialMenuSettings.allowedIconSizes),
                            isSelected: settings.iconSize == size,
                            action: { settings.iconSize = size }
                        )
                    }
                    Spacer()
                    Text("\(settings.iconSize) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.appleMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                SectionDivider()

                HStack(spacing: 10) {
                    Text("文字大小")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleInk)
                        .frame(width: 64, alignment: .leading)
                    ForEach(RadialMenuSettings.allowedTextSizes, id: \.self) { size in
                        PillButton(
                            label: presetLabel(size, in: RadialMenuSettings.allowedTextSizes),
                            isSelected: settings.textSize == size,
                            action: { settings.textSize = size }
                        )
                    }
                    Spacer()
                    Text("\(settings.textSize) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.appleMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.appleSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appleDivider, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func sizeLabel(_ size: Int) -> String {
        presetLabel(size, in: RadialMenuSettings.allowedSizes)
    }

    /// 按档位在数组中的位置映射成「小 / 中 / 大」
    private func presetLabel(_ value: Int, in list: [Int]) -> String {
        let labels = ["小", "中", "大"]
        let index = list.firstIndex(of: value) ?? 1
        return labels[min(index, labels.count - 1)]
    }

    // MARK: - 动作分配

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("扇区动作")
                Spacer()
                Button("恢复默认") {
                    settings.actionIds = RadialActionCatalog.defaultActionIds
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.appleBlue)
            }

            VStack(spacing: 0) {
                ForEach(0..<settings.sectorCount, id: \.self) { index in
                    actionRow(index)
                    if index < settings.sectorCount - 1 {
                        SectionDivider()
                    }
                }
            }
            .background(Color.appleSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appleDivider, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func actionRow(_ index: Int) -> some View {
        let current = RadialActionCatalog.action(id: settings.actionId(at: index))

        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.appleSoft)
                .frame(width: 20, height: 20)
                .background(Color.appleSurface2)
                .clipShape(Circle())

            Image(systemName: current?.icon ?? "questionmark")
                .font(.system(size: 14))
                .foregroundStyle(Color.appleInk)
                .frame(width: 20)

            Text(current?.displayName ?? "未设置")
                .font(.system(size: 14))
                .foregroundStyle(Color.appleInk)

            Spacer()

            Menu {
                ForEach(RadialActionCatalog.all) { action in
                    Button {
                        settings.setAction(action.id, at: index)
                    } label: {
                        Label(action.displayName, systemImage: action.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("更换")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Color.appleBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.appleSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - 预览

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("预览")
                Spacer()
                Button("在光标处试一下") {
                    RadialMenuController.shared.preview()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.appleBlue)
            }
            HStack {
                Spacer()
                RadialMenuView(
                    model: previewModel,
                    metrics: RadialMenuMetrics(panelSize: CGFloat(settings.menuSize)),
                    isPreview: true
                )
                .scaleEffect(290 / CGFloat(settings.menuSize))
                .frame(width: 290, height: 290)
                Spacer()
            }
            .padding(.vertical, 4)
            .background(Color.appleSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appleDivider, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("使用提示")
            tip("按住快捷键不放，移动鼠标到目标扇区，松开修饰键即执行")
            tip("光标回到中心区域或按 Esc 取消，不会执行任何动作")
            tip("动作作用于唤出圆环时 Finder 中选中的文件")
            tip("快速点击快捷键不会误触发：光标未离开中心即视为取消")
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").foregroundStyle(Color.appleSoft)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.appleSoft)
        }
    }

    private func syncPreview() {
        previewModel.actions = settings.activeActions
        previewModel.selection = nil
        previewModel.isShown = true
        previewModel.iconSize = CGFloat(settings.iconSize)
        previewModel.titleSize = CGFloat(settings.textSize)
    }
}
