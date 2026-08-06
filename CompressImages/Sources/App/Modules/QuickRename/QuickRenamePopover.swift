import SwiftUI
import AppKit

struct QuickRenamePopover: View {
    @Environment(AppState.self) var state

    // 目标文件 URL
    @State private var targetURL: URL?

    // 日期格式 pill（默认月日，空字符串 = 未选中）
    @State private var dateFormat: String = "MMdd"

    // 渠道 pill（默认线上）：线上/线下/其他
    @State private var channel: String = "线上"
    // "其他"被选中时的自定义渠道文本
    @AppStorage("datefolder_interactive_custom_channel") private var customChannel: String = ""
    // 用户自定义渠道标签列表（与新建文件夹共享）
    @AppStorage("datefolder_custom_channels_json") private var customChannelsJSON: String = "[]"
    @State private var isAddingChannel = false
    @State private var newChannelInput = ""
    @FocusState private var newChannelFocused: Bool
    @State private var hoveringChannel: String?
    @FocusState private var customChannelFocused: Bool

    // 名字输入
    @State private var namePart: String = ""

    // 版本号
    @State private var versionEnabled: Bool = true
    @State private var versionNumber: Int = 1

    // 状态
    @State private var status: String = ""
    @AppStorage("quickrename_custom_statuses_json") private var customStatusesJSON: String = "[]"
    @State private var isAddingStatus = false
    @State private var newStatusInput = ""
    @FocusState private var newStatusFocused: Bool
    @State private var hoveringStatus: String?
    @State private var editingStatus: String?  // 右键改名的标签
    @State private var editingStatusText: String = ""
    @FocusState private var editingStatusFocused: Bool

    // 重命名状态
    @State private var isRenaming = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let dateFormats: [(label: String, format: String)] = [
        ("月日", "MMdd"),
        ("年月", "yyMM"),
        ("年月日", "yyMMdd")
    ]

    private var dateLabel: String {
        dateFormat.isEmpty ? "" : QuickRenameEngine.formatName(format: dateFormat)
    }

    private var effectiveChannel: String {
        if channel.isEmpty { return "" }
        return channel == "其他" ? customChannel : channel
    }

    // 自定义渠道列表
    private var customChannels: [String] {
        guard let data = customChannelsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    private func saveCustomChannels(_ list: [String]) {
        if let data = try? JSONEncoder().encode(list),
           let str = String(data: data, encoding: .utf8) {
            customChannelsJSON = str
        }
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
            channel = trimmed
            return
        }
        list.append(trimmed)
        saveCustomChannels(list)
        channel = trimmed
    }

    private func deleteChannel(_ ch: String) {
        var list = customChannels
        list.removeAll { $0 == ch }
        saveCustomChannels(list)
        if channel == ch { channel = "" }
        hoveringChannel = nil
    }

    // 自定义状态列表
    private var customStatuses: [String] {
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

    private var finalName: String {
        QuickRenameEngine.buildName(
            date: dateLabel, channel: effectiveChannel, name: namePart,
            version: versionNumber, versionEnabled: versionEnabled, status: status
        )
    }

    private var originalFileName: String {
        targetURL?.lastPathComponent ?? ""
    }

    var body: some View {
        VStack(spacing: 16) {
            headerArea
            Divider().padding(.horizontal, -24)
            fileInfoArea
            optionsArea
            nameArea
            versionStatusArea
            previewArea
            Spacer()
            renameButton
            if showError {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color.appleCanvas)
        .onAppear { onAppearInit() }
    }

    // MARK: - onAppear 初始化
    private func onAppearInit() {
        // 读取目标文件
        guard let url = state.preloadedURLs.first else {
            errorMessage = "未检测到选中文件"
            showError = true
            return
        }
        targetURL = url

        // 解析文件名
        let parsed = QuickRenameEngine.parse(
            fileName: url.lastPathComponent,
            customChannels: customChannels,
            customStatuses: customStatuses
        )
        AppLog.shared.log("快速改名解析 fileName=\(url.lastPathComponent) → date=\(parsed.date) channel=\(parsed.channel) name=\(parsed.name) version=\(parsed.version.map(String.init) ?? "nil") status=\(parsed.status)", category: "QuickRename")

        // 填充各字段（无格式文件用默认值）
        if !parsed.dateFormat.isEmpty {
            dateFormat = parsed.dateFormat
        } else {
            dateFormat = "MMdd"
        }

        if !parsed.channel.isEmpty {
            channel = parsed.channel
        } else {
            channel = "线上"
        }

        namePart = parsed.name
        versionNumber = QuickRenameEngine.nextVersion(current: parsed.version)
        versionEnabled = true
        status = parsed.status

        // 窗口校准（高度自适应内容）
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.level == .screenSaver }) else { return }
            window.styleMask.remove(.resizable)
            window.isMovableByWindowBackground = true
            // 让窗口根据 SwiftUI 内容自动调整高度
            window.contentMinSize = NSSize(width: 480, height: 400)
            window.contentMaxSize = NSSize(width: 480, height: 1200)
            FinderSelection.positionWindowNearFinder(window)
            window.level = .screenSaver
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - headerArea
    private var headerArea: some View {
        HStack {
            Text("快速改名")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Spacer()
            Button {
                // 清空：恢复到 onAppear 时的解析默认值
                if let url = targetURL {
                    let parsed = QuickRenameEngine.parse(
                        fileName: url.lastPathComponent,
                        customChannels: customChannels,
                        customStatuses: customStatuses
                    )
                    dateFormat = parsed.dateFormat.isEmpty ? "MMdd" : parsed.dateFormat
                    channel = parsed.channel.isEmpty ? "线上" : parsed.channel
                    namePart = parsed.name
                    versionNumber = QuickRenameEngine.nextVersion(current: parsed.version)
                    versionEnabled = true
                    status = parsed.status
                }
                customChannelFocused = false
                isAddingChannel = false
                newChannelInput = ""
                newChannelFocused = false
                hoveringChannel = nil
                isAddingStatus = false
                newStatusInput = ""
                newStatusFocused = false
                hoveringStatus = nil
                editingStatus = nil
                editingStatusText = ""
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("重置为解析默认值")
        }
    }

    // MARK: - fileInfoArea
    private var fileInfoArea: some View {
        HStack(spacing: 12) {
            if let url = targetURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(originalFileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                    .lineLimit(1)
                if let url = targetURL {
                    Text(url.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - optionsArea（日期+渠道）
    private var optionsArea: some View {
        VStack(spacing: 12) {
            // 日期行
            HStack(spacing: 10) {
                Text("日期")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
                ForEach(dateFormats, id: \.format) { item in
                    PillButton(
                        label: item.label,
                        isSelected: dateFormat == item.format,
                        action: {
                            dateFormat = (dateFormat == item.format) ? "" : item.format
                        }
                    )
                }
                Spacer(minLength: 0)
            }

            // 渠道行
            HStack(spacing: 10) {
                Text("渠道")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
                ForEach(["线上", "线下"], id: \.self) { ch in
                    PillButton(
                        label: ch,
                        isSelected: channel == ch,
                        action: {
                            channel = (channel == ch) ? "" : ch
                        }
                    )
                }
                ForEach(customChannels, id: \.self) { ch in
                    customChannelPill(ch)
                }
                if channel == "其他" {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.appleBlue)
                        TextField("输入", text: $customChannel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.appleInk)
                            .frame(width: 60)
                            .focused($customChannelFocused)
                            .onSubmit { rename() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(Color.appleSurface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.appleBlue, lineWidth: 1.5)
                    )
                    .overlay(alignment: .trailing) {
                        Button {
                            channel = ""
                            customChannelFocused = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.appleSoft)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onAppear { customChannelFocused = true }
                } else {
                    Button {
                        channel = "其他"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            customChannelFocused = true
                        }
                    } label: {
                        Text("其他")
                            .font(.system(size: 12, weight: .regular))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(Color.appleInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: 32)
                            .background(Color.appleSurface3)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if isAddingChannel {
                    HStack(spacing: 4) {
                        TextField("输入标签名", text: $newChannelInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.appleInk)
                            .frame(width: 70)
                            .focused($newChannelFocused)
                            .onSubmit { addChannel() }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.appleSurface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.appleBlue, lineWidth: 1.5)
                    )
                    .overlay(alignment: .trailing) {
                        Button {
                            isAddingChannel = false
                            newChannelInput = ""
                            newChannelFocused = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.appleSoft)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            newChannelFocused = true
                        }
                    }
                } else {
                    Button {
                        isAddingChannel = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .regular))
                            Text("新增")
                                .font(.system(size: 12, weight: .regular))
                        }
                        .foregroundStyle(Color.appleSoft.opacity(0.7))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    Color.appleSoft.opacity(0.35),
                                    style: StrokeStyle(
                                        lineWidth: 1,
                                        dash: [4, 3]
                                    )
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - customChannelPill
    @ViewBuilder
    private func customChannelPill(_ ch: String) -> some View {
        let isSelected = channel == ch
        let isHovering = hoveringChannel == ch
        HStack(spacing: 4) {
            Text(ch)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isSelected ? .white : Color.appleInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(isSelected ? Color.appleBlue : Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    deleteChannel(ch)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white, Color.red.opacity(0.9))
                        .background(Circle().fill(Color.appleCanvas))
                        .offset(x: 5, y: -5)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            channel = (channel == ch) ? "" : ch
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveringChannel = hovering ? ch : nil
            }
        }
    }

    // MARK: - nameArea
    private var nameArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("名字")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            TextField("输入名字", text: $namePart)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.appleSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit { rename() }
        }
    }

    // MARK: - versionStatusArea（两个等高等宽带底色线框卡片）
    private var versionStatusArea: some View {
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

            // 状态标签网格（3列，等宽）
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

    // 状态新增输入框
    private var statusAddInput: some View {
        TextField("输入", text: $newStatusInput)
            .textFieldStyle(.plain)
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
                .background(isSelected ? Color.appleBlue : Color.appleSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if isHovering && !QuickRenameEngine.defaultStatuses.contains(st) {
                        Button {
                            deleteStatus(st)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white, Color.red.opacity(0.9))
                                .background(Circle().fill(Color.appleCanvas))
                                .offset(x: 4, y: -4)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale))
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
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveringStatus = hovering ? st : nil
                    }
                }
        }
    }

    // MARK: - previewArea
    private var previewArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("更名预览")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                Spacer()
                if !originalFileName.isEmpty {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Color.appleMuted)
                }
            }

            if !originalFileName.isEmpty {
                Text(originalFileName)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.appleMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(finalName.isEmpty ? originalFileName : "\(finalName).\(targetURL?.pathExtension ?? "")")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.appleBlue)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.appleBlue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - renameButton
    private var renameButton: some View {
        Button(action: rename) {
            HStack(spacing: 8) {
                if isRenaming {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isRenaming ? "重命名中…" : "立即重命名")
                    .font(.system(size: 17, weight: .regular))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isRenaming ? Color.appleBlue.opacity(0.7) : Color.appleBlue)
            .clipShape(RoundedRectangle(cornerRadius: 980))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(isRenaming || finalName.isEmpty || namePart.isEmpty)
    }

    // MARK: - rename 执行
    private func rename() {
        guard QuickRenameEngine.tryAcquireCreateLock() else {
            AppLog.shared.log("rename() 被拦截：已有重命名进行中", category: "QuickRename", level: .warn)
            return
        }
        guard let url = targetURL else {
            QuickRenameEngine.releaseCreateLock()
            return
        }
        isRenaming = true
        let newName = finalName

        Task {
            do {
                let resultURL = try QuickRenameEngine.rename(url: url, newName: newName)
                await MainActor.run {
                    AppNotification.send(title: "已重命名", body: resultURL.lastPathComponent)
                    AppLog.shared.log("文件重命名完成 \(url.lastPathComponent) → \(resultURL.lastPathComponent)", category: "QuickRename", level: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        for window in NSApp.windows where window.level == .screenSaver {
                            window.close()
                        }
                        isRenaming = false
                        QuickRenameEngine.releaseCreateLock()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isRenaming = false
                    QuickRenameEngine.releaseCreateLock()
                }
            }
        }
    }
}
