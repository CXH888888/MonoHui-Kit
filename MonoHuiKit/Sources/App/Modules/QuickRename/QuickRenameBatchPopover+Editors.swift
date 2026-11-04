import SwiftUI

// MARK: - 统一模式编辑器与渠道/状态标签组件
extension QuickRenameBatchPopover {
    // MARK: - 统一模式编辑器
    @ViewBuilder
    func unifiedEditor(_ config: BatchFieldConfig) -> some View {
        switch config.key {
        case "date":
            dateEditor
        case "channel":
            channelEditor
        case "name":
            nameEditor
        case "version":
            versionEditor
        case "status":
            statusEditor
        default:
            Color.clear
        }
    }

    // 日期编辑器（3列网格，三个格式标签撑满一行）
    private var dateEditor: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(dateFormats, id: \.format) { item in
                batchGridPill(item.label, isSelected: dateFormat == item.format) {
                    let wasSelected = dateFormat == item.format
                    dateFormat = wasSelected ? "" : item.format
                    saveDateToFieldConfig()
                }
            }
        }
    }

    /// 日期格式变化时同步到 fieldConfigs
    private func saveDateToFieldConfig() {
        guard let idx = fieldConfigs.firstIndex(where: { $0.key == "date" }) else { return }
        fieldConfigs[idx].dateFormat = dateFormat
        fieldConfigs[idx].unifyValue = dateFormat.isEmpty ? "" : QuickRenameEngine.formatName(format: dateFormat)
        saveCurrentConfig()
    }

    // 渠道编辑器（3列flexible网格，与状态标签一致：等宽撑满、间距均匀）
    private var channelEditor: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(["线上", "线下"], id: \.self) { ch in
                batchGridPill(ch, isSelected: channels.contains(ch)) {
                    toggleChannel(ch)
                }
            }
            ForEach(customChannels, id: \.self) { ch in
                ChannelCustomPill(
                    title: ch,
                    isSelected: channels.contains(ch),
                    layout: .grid,
                    hovering: $hoveringChannel,
                    onTap: { toggleChannel(ch) },
                    onDelete: { deleteChannel(ch) }
                )
            }
            ChannelOtherPill(
                isActive: channels.contains("其他"),
                layout: .grid,
                text: $customChannel,
                textFocus: $customChannelFocused,
                onToggle: { toggleChannel("其他") },
                onRemove: { channels.removeAll { $0 == "其他" } },
                onTextChange: { saveEditorState(for: "channel") }
            )
            ChannelAddControl(
                layout: .grid,
                isAdding: $isAddingChannel,
                text: $newChannelInput,
                textFocus: $newChannelFocused,
                onSubmit: { addChannel() }
            )
        }
        .onChange(of: channels) { _, _ in saveEditorState(for: "channel") }
    }

    // 名字编辑器
    private var nameEditor: some View {
        TextField("输入名字", text: $namePart)
            .focused($nameFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.appleInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.appleSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: namePart) { _, _ in saveEditorState(for: "name") }
    }

    // 版本编辑器（大版本号 + 步进器，水平居中）
    private var versionEditor: some View {
        HStack(spacing: 10) {
            Button {
                if versionNumber > 1 { versionNumber -= 1; saveEditorState(for: "version") }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                    .frame(width: 28, height: 28)
                    .background(Color.appleSurface2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(versionNumber <= 1)

            Text("V\(versionNumber)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appleBlue)
                .frame(minWidth: 50)

            Button {
                if versionNumber < 999 { versionNumber += 1; saveEditorState(for: "version") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                    .frame(width: 28, height: 28)
                    .background(Color.appleSurface2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // 状态编辑器（复用状态标签网格）
    private var statusEditor: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ], spacing: 6) {
            ForEach(allStatuses, id: \.self) { st in
                batchStatusPill(st)
            }
            if isAddingStatus {
                batchStatusAddInput
            } else {
                batchStatusAddButton
            }
        }
        .onChange(of: status) { _, _ in saveEditorState(for: "status") }
    }

    private func addChannel() {
        let trimmed = newChannelInput.trimmingCharacters(in: .whitespaces)
        newChannelInput = ""
        isAddingChannel = false
        newChannelFocused = false
        guard !trimmed.isEmpty else { return }
        var list = customChannels
        let reserved = ["线上", "线下", "其他"]
        if list.contains(trimmed) || reserved.contains(trimmed) {
            if !channels.contains(trimmed) { channels.append(trimmed) }
            return
        }
        list.append(trimmed)
        if let data = try? JSONEncoder().encode(list),
           let str = String(data: data, encoding: .utf8) {
            customChannelsJSON = str
        }
        if !channels.contains(trimmed) { channels.append(trimmed) }
    }

    /// 删除自定义渠道标签（与单文件改名一致）
    private func deleteChannel(_ ch: String) {
        var list = customChannels
        list.removeAll { $0 == ch }
        if let data = try? JSONEncoder().encode(list),
           let str = String(data: data, encoding: .utf8) {
            customChannelsJSON = str
        }
        channels.removeAll { $0 == ch }
        hoveringChannel = nil
    }

    // MARK: - 通用网格 Pill（批量版）

    // 与状态标签一致：等宽撑满网格列、间距均匀；文字用 ZStack 绝对居中，不受网格行高变化影响
    private func batchGridPill(_ text: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        ZStack {
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : Color.appleInk)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.appleBlue : Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // MARK: - 状态 Pill（批量版）

    @ViewBuilder
    private func batchStatusPill(_ st: String) -> some View {
        let isSelected = status == st
        let isCustom = !QuickRenameEngine.defaultStatuses.contains(st)
        let isHovering = hoveringStatus == st
        ZStack(alignment: .topTrailing) {
            // 圆角背景（独立，不裁剪任何前景内容）
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.appleBlue : Color.appleSurface2)
            // 文字（撑满网格列居中，不被红叉遮挡）
            Text(st)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : Color.appleInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 删除按钮：骑在标签右上角、向外突出（仅自定义状态），纯淡入即时出现
            if isCustom && isHovering {
                Button {
                    deleteStatus(st)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white, Color.red)
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .offset(x: 6, y: -6)
                .buttonStyle(.plain)
                .transition(.opacity)
                .help("删除「\(st)」")
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { status = (status == st) ? "" : st }
        .onHover { hovering in
            withAnimation(Motion.moveFast) {
                hoveringStatus = hovering ? st : nil
            }
        }
    }

    private var batchStatusAddInput: some View {
        TextField("输入", text: $newStatusInput)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.appleInk)
            .frame(height: 28)
            .padding(.horizontal, 6)
            .background(Color.appleSurface2)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appleBlue, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .focused($newStatusFocused)
            .onSubmit { addStatus() }
    }

    private var batchStatusAddButton: some View {
        Button {
            isAddingStatus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                newStatusFocused = true
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .regular))
                Text("新增")
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(Color.appleSoft.opacity(0.7))
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.appleSoft.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addStatus() {
        let trimmed = newStatusInput.trimmingCharacters(in: .whitespaces)
        newStatusInput = ""
        isAddingStatus = false
        newStatusFocused = false
        guard !trimmed.isEmpty else { return }
        var list = customStatuses
        if list.contains(trimmed) || QuickRenameEngine.defaultStatuses.contains(trimmed) {
            status = trimmed
            return
        }
        list.append(trimmed)
        if let data = try? JSONEncoder().encode(list),
           let str = String(data: data, encoding: .utf8) {
            customStatusesJSON = str
        }
        status = trimmed
    }

    /// 删除自定义状态标签（与自定义渠道一致）
    private func deleteStatus(_ st: String) {
        var list = customStatuses
        list.removeAll { $0 == st }
        if let data = try? JSONEncoder().encode(list),
           let str = String(data: data, encoding: .utf8) {
            customStatusesJSON = str
        }
        if status == st { status = "" }
        hoveringStatus = nil
    }

}
