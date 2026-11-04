import SwiftUI

// MARK: - 版本 / 状态卡片与状态标签逻辑
extension QuickRenamePopover {
    var versionStatusArea: some View {
        HStack(alignment: .top, spacing: 12) {
            // 版本卡片（高度跟随状态卡片）
            versionCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // 状态卡片
            statusCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // 圆形复选框（12pt）
    @ViewBuilder
    private func circleCheckbox(isOn: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isOn ? Color.appleBlue : Color.appleSoft.opacity(0.5), lineWidth: 1.2)
                .frame(width: 12, height: 12)
            if isOn {
                Circle()
                    .fill(Color.appleBlue)
                    .frame(width: 12, height: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // 版本卡片
    private var versionCard: some View {
        VStack(spacing: 0) {
            // 卡片头：标题(左) + 圆形复选框(右)
            HStack {
                Text("版本")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Spacer()
                circleCheckbox(isOn: versionEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                versionEnabled.toggle()
            }

            // 内容：大版本号 + 大加减号步进器（垂直居中填充）
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                // 减号按钮
                Button {
                    if versionNumber > 1 { versionNumber -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(versionEnabled ? Color.appleInk : Color.appleMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.appleSurface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!versionEnabled || versionNumber <= 1)
                .opacity(versionEnabled ? 1 : 0.4)

                // 大版本号
                Text("V\(versionNumber)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(versionEnabled ? Color.appleBlue : Color.appleMuted)
                    .frame(minWidth: 50)

                // 加号按钮
                Button {
                    if versionNumber < 999 { versionNumber += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(versionEnabled ? Color.appleInk : Color.appleMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.appleSurface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!versionEnabled)
                .opacity(versionEnabled ? 1 : 0.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            // 底部留白与状态卡片对齐
            Color.clear.frame(height: 12)
        }
        .background(
            Color.appleSurface
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    versionEnabled.toggle()
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(versionEnabled ? Color.appleBlue.opacity(0.3) : Color.appleDivider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // 状态卡片
    private var statusCard: some View {
        let statusEnabled = !status.isEmpty
        return VStack(spacing: 0) {
            // 卡片头：标题(左) + 圆形复选框(右)
            HStack {
                Text("状态")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                Spacer()
                circleCheckbox(isOn: statusEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if statusEnabled {
                    status = ""
                } else {
                    status = "草稿"
                }
            }

            // 状态标签网格（3列等宽；超过 2 行后内部滚动，顶/底渐变）
            ScrollView(.vertical, showsIndicators: false) {
                // 外层 VStack 保障 documentView 高度上报可靠（同批量弹窗编辑器方案）
                VStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ], spacing: 6) {
                        ForEach(allStatuses, id: \.self) { st in
                            statusPill(st)
                        }
                        if isAddingStatus {
                            statusAddInput
                        } else {
                            statusAddButton
                        }
                    }
                }
                .frame(minHeight: Self.statusGridViewportHeight, alignment: .top)
                .background(
                    ScrollEdgeObserver(axis: .vertical) { geom in
                        if statusScrollGeom != geom {
                            statusScrollGeom = geom
                        }
                    }
                )
            }
            .frame(height: Self.statusGridViewportHeight)
            // 顶/底渐变：滚动离开边界后淡出内容（走 mask，不再覆盖近似底色）
            .scrollEdgeFade(top: statusTopFade, bottom: statusBottomFade,
                            length: Self.statusGridFadeHeight)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            Color.appleSurface
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    if statusEnabled {
                        status = ""
                    } else {
                        status = "草稿"
                    }
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusEnabled ? Color.appleBlue.opacity(0.3) : Color.appleDivider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 状态网格视口固定高度（2 行：28 × 2 + 间距 6）
    private static let statusGridViewportHeight: CGFloat = 62
    /// 状态网格渐变高度：与批量弹窗编辑器一致（28pt 行高的约 1/3）
    private static let statusGridFadeHeight: CGFloat = 10

    private var statusTopFade: Bool { statusScrollGeom.offset > 1 }

    // 与批量更名预览 showPreviewBottomFade 完全一致的单行表达式
    private var statusBottomFade: Bool {
        statusScrollGeom.contentLength - statusScrollGeom.viewportLength - statusScrollGeom.offset > 1
    }

    // 状态新增输入框
    private var statusAddInput: some View {
        TextField("输入", text: $newStatusInput)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.appleInk)
            .frame(height: 28)
            .padding(.horizontal, 6)
            .background(Color.appleSurface2)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.appleBlue, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .focused($newStatusFocused)
            .onSubmit { addStatus() }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    newStatusFocused = true
                }
            }
    }

    // 状态新增按钮
    private var statusAddButton: some View {
        Button {
            isAddingStatus = true
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
                    .stroke(
                        Color.appleSoft.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - statusPill（右键改名，固定大小）
    @ViewBuilder
    private func statusPill(_ st: String) -> some View {
        let isSelected = status == st
        let isHovering = hoveringStatus == st
        let isEditing = editingStatus == st

        if isEditing {
            TextField("改名", text: $editingStatusText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .frame(height: 28)
                .padding(.horizontal, 6)
                .background(Color.appleSurface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appleBlue, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .focused($editingStatusFocused)
                .onSubmit { commitStatusEdit() }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        editingStatusFocused = true
                    }
                }
        } else {
            Text(st)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : Color.appleInk)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                // 圆角背景用 shape 画（不再用 clipShape，避免裁到右上角溢出的删除按钮）
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.appleBlue : Color.appleSurface2)
                )
                .overlay(alignment: .topTrailing) {
                    if isHovering && !QuickRenameEngine.defaultStatuses.contains(st) {
                        Button {
                            deleteStatus(st)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white, Color.red)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    status = (status == st) ? "" : st
                }
                .contextMenu {
                    Button("改名") {
                        editingStatus = st
                        editingStatusText = st
                    }
                }
                .onHover { hovering in
                    withAnimation(Motion.moveFast) {
                        hoveringStatus = hovering ? st : nil
                    }
                }
        }
    }

    // MARK: - 状态标签数据

    // 自定义状态列表（onAppear 解析原文件名时也要用，保持 internal）
    var customStatuses: [String] {
        guard let data = customStatusesJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    private func saveCustomStatuses(_ list: [String]) {
        if let data = try? JSONEncoder().encode(list),
           let str = String(data: data, encoding: .utf8) {
            customStatusesJSON = str
        }
    }

    private var allStatuses: [String] {
        QuickRenameEngine.defaultStatuses + customStatuses
    }

    private func addStatus() {
        let trimmed = newStatusInput.trimmingCharacters(in: .whitespaces)
        newStatusInput = ""
        isAddingStatus = false
        newStatusFocused = false
        guard !trimmed.isEmpty else { return }
        var list = customStatuses
        let reserved = QuickRenameEngine.defaultStatuses
        if list.contains(trimmed) || reserved.contains(trimmed) {
            status = trimmed
            return
        }
        list.append(trimmed)
        saveCustomStatuses(list)
        status = trimmed
    }

    private func deleteStatus(_ st: String) {
        var list = customStatuses
        list.removeAll { $0 == st }
        saveCustomStatuses(list)
        if status == st { status = "" }
        hoveringStatus = nil
    }

    // 右键改名保存
    private func commitStatusEdit() {
        let trimmed = editingStatusText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            editingStatus = nil
            return
        }
        // 如果是默认标签，改为自定义标签（把新名加入自定义列表）
        if QuickRenameEngine.defaultStatuses.contains(editingStatus ?? "") {
            var list = customStatuses
            if !list.contains(trimmed) && !QuickRenameEngine.defaultStatuses.contains(trimmed) {
                list.append(trimmed)
                saveCustomStatuses(list)
            }
        } else {
            // 自定义标签：替换
            var list = customStatuses
            if let idx = list.firstIndex(of: editingStatus ?? "") {
                if !list.contains(trimmed) && !QuickRenameEngine.defaultStatuses.contains(trimmed) {
                    list[idx] = trimmed
                    saveCustomStatuses(list)
                }
            }
        }
        if status == editingStatus {
            status = trimmed
        }
        editingStatus = nil
        editingStatusText = ""
        editingStatusFocused = false
    }
}
