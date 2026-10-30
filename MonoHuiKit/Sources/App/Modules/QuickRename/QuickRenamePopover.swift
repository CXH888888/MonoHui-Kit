import SwiftUI
import AppKit

struct QuickRenamePopover: View {
    @Environment(AppState.self) var state

    // 目标文件 URL
    @State private var targetURL: URL?

    // 目标文件图标（onAppear 时加载一次并缓存，避免 body 重算时反复调用 NSWorkspace 导致闪动）
    @State private var fileIcon: NSImage?

    // 日期格式 pill（默认月日，空字符串 = 未选中）
    // 特殊值 "original" = 使用解析出的原日期
    @State private var dateFormat: String = "MMdd"
    // 解析出的原日期（避免日期被覆盖为今天）
    @State private var originalDate: String = ""

    // 渠道 pill（默认线上）：线上/线下/其他
    @State private var channels: [String] = ["线上"]
    // "其他"被选中时的自定义渠道文本
    @AppStorage("datefolder_interactive_custom_channel") private var customChannel: String = ""
    // 用户自定义渠道标签列表（与新建文件夹共享）
    @AppStorage("datefolder_custom_channels_json") private var customChannelsJSON: String = "[]"
    @State private var isAddingChannel = false
    @State private var newChannelInput = ""
    /// 弹窗唤起时自动聚焦名称输入框
    @FocusState private var nameFocused: Bool
    @FocusState private var newChannelFocused: Bool
    @State private var hoveringChannel: String?
    @FocusState private var customChannelFocused: Bool
    // 渠道行横向滚动状态（标签超出后左右渐变提示）
    @State private var channelScrollGeom = ScrollEdgeGeom()

    // 名字输入
    @State private var namePart: String = ""

    // 版本号
    @State var versionEnabled: Bool = true
    @State var versionNumber: Int = 1

    // 状态
    @State var status: String = ""
    @AppStorage("quickrename_custom_statuses_json") var customStatusesJSON: String = "[]"
    @State var isAddingStatus = false
    @State var newStatusInput = ""
    @FocusState var newStatusFocused: Bool
    @State var hoveringStatus: String?
    @State var editingStatus: String?  // 右键改名的标签
    @State var editingStatusText: String = ""
    @FocusState var editingStatusFocused: Bool
    // 状态卡网格滚动（标签超 2 行后内部滚动，复用批量弹窗的观察器方案）
    @State var statusScrollGeom = ScrollEdgeGeom()

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
        if dateFormat == "original" {
            return originalDate
        }
        return dateFormat.isEmpty ? "" : QuickRenameEngine.formatName(format: dateFormat)
    }

    /// 实际用于命名的渠道值：选"其他"时取 customChannel，其余取标签本身。
    /// 顺序按 pill 的固定顺序，保证同一组合永远得到同一个名字。
    private var effectiveChannels: [String] {
        let order = ["线上", "线下"] + customChannels + ["其他"]
        return order.filter { channels.contains($0) }.compactMap { ch in
            let value = ch == "其他" ? customChannel.trimmingCharacters(in: .whitespaces) : ch
            return value.isEmpty ? nil : value
        }
    }

    /// 多选开关：已选则取消，未选则追加
    private func toggleChannel(_ ch: String) {
        if let index = channels.firstIndex(of: ch) {
            channels.remove(at: index)
        } else {
            channels.append(ch)
        }
    }

    // 自定义渠道列表
    private var customChannels: [String] {
        guard let data = customChannelsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    // 渠道行渐变：已向右滚（离开最左）→ 左侧渐变；右侧还有内容 → 右侧渐变
    private var channelLeftFade: Bool { channelScrollGeom.offset > 1 }
    private var channelRightFade: Bool {
        channelScrollGeom.contentLength > 0 &&
        channelScrollGeom.offset + channelScrollGeom.viewportLength < channelScrollGeom.contentLength - 1
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
            if !channels.contains(trimmed) { channels.append(trimmed) }
            return
        }
        list.append(trimmed)
        saveCustomChannels(list)
        if !channels.contains(trimmed) { channels.append(trimmed) }
    }

    private func deleteChannel(_ ch: String) {
        var list = customChannels
        list.removeAll { $0 == ch }
        saveCustomChannels(list)
        channels.removeAll { $0 == ch }
        hoveringChannel = nil
    }

    private var finalName: String {
        QuickRenameEngine.buildName(
            date: dateLabel, channel: effectiveChannels.joined(separator: "-"), name: namePart,
            version: versionNumber, versionEnabled: versionEnabled, status: status
        )
    }

    private var originalFileName: String {
        targetURL?.lastPathComponent ?? ""
    }

    /// 预览用的完整文件名（扩展名为空时不加句号）
    private var previewFullName: String {
        if finalName.isEmpty { return originalFileName }
        let ext = targetURL?.pathExtension ?? ""
        return ext.isEmpty ? finalName : "\(finalName).\(ext)"
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
        .background(Color.applePopupCanvas)
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
        // 仅取一次系统图标缓存到 @State，避免每次 body 重算创建新 NSImage 导致预览图标闪动
        fileIcon = NSWorkspace.shared.icon(forFile: url.path)

        // 解析文件名
        let parsed = QuickRenameEngine.parse(
            fileName: url.lastPathComponent,
            customChannels: customChannels,
            customStatuses: customStatuses
        )
        AppLog.shared.log("快速改名解析 fileName=\(url.lastPathComponent) → date=\(parsed.date) channel=\(parsed.channel) name=\(parsed.name) version=\(parsed.version.map(String.init) ?? "nil") status=\(parsed.status)", category: "QuickRename")

        // 填充各字段（无格式文件用默认值）
        if !parsed.dateFormat.isEmpty {
            // 有原日期：默认选"原始"，保留原日期
            dateFormat = "original"
            originalDate = parsed.date
        } else {
            // 无格式文件：默认月日（今天）
            dateFormat = "MMdd"
            originalDate = ""
        }

        channels = parsed.channel.isEmpty
            ? ["线上"]
            : parsed.channel.split(separator: "-").map(String.init)

        namePart = parsed.name
        versionNumber = QuickRenameEngine.nextVersion(current: parsed.version)
        versionEnabled = true
        status = parsed.status

        // 窗口校准（高度自适应内容）
        HotKeyDispatcher.calibratePopupWindow(width: 480, minHeight: 400, maxHeight: 1200)

        // 唤起即聚焦名称输入框，省掉一次点击
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            nameFocused = true
        }
    }

    // MARK: - headerArea
    private var headerArea: some View {
        HStack {
            Text("快速改名")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Button {
                // 清空：恢复到 onAppear 时的解析默认值
                if let url = targetURL {
                    let parsed = QuickRenameEngine.parse(
                        fileName: url.lastPathComponent,
                        customChannels: customChannels,
                        customStatuses: customStatuses
                    )
                    dateFormat = parsed.dateFormat.isEmpty ? "MMdd" : "original"
                    originalDate = parsed.date
                    channels = parsed.channel.isEmpty
                        ? ["线上"]
                        : parsed.channel.split(separator: "-").map(String.init)
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
            Spacer()
            PopoverCloseButton()
        }
    }

    // MARK: - fileInfoArea
    private var fileInfoArea: some View {
        HStack(spacing: 12) {
            if let fileIcon {
                Image(nsImage: fileIcon)
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
                // 原始日期标签（仅当解析出原日期时显示）
                if !originalDate.isEmpty {
                    PillButton(
                        label: "原始·\(originalDate)",
                        isSelected: dateFormat == "original",
                        action: {
                            dateFormat = (dateFormat == "original") ? "" : "original"
                        }
                    )
                }
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

            // 渠道行（标签区横向滚动：超出后左右渐变提示，参考批量重命名更名预览）
            HStack(spacing: 10) {
                Text("渠道")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(["线上", "线下"], id: \.self) { ch in
                            PillButton(
                                label: ch,
                                isSelected: channels.contains(ch),
                                action: { toggleChannel(ch) }
                            )
                        }
                        ForEach(customChannels, id: \.self) { ch in
                            ChannelCustomPill(
                                title: ch,
                                isSelected: channels.contains(ch),
                                layout: .row,
                                hovering: $hoveringChannel,
                                onTap: { toggleChannel(ch) },
                                onDelete: { deleteChannel(ch) }
                            )
                        }
                        ChannelOtherPill(
                            isActive: channels.contains("其他"),
                            layout: .row,
                            text: $customChannel,
                            textFocus: $customChannelFocused,
                            onToggle: { toggleChannel("其他") },
                            onRemove: { channels.removeAll { $0 == "其他" } },
                            onSubmit: { rename() }
                        )
                        ChannelAddControl(
                            layout: .row,
                            isAdding: $isAddingChannel,
                            text: $newChannelInput,
                            textFocus: $newChannelFocused,
                            onSubmit: { addChannel() }
                        )
                    }
                    .background(
                        ScrollEdgeObserver(axis: .horizontal) { geom in
                            channelScrollGeom = geom
                        }
                    )
                }
                // 左渐变：已向右滚动（离开最左）时浮现，避免内容生硬截断
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [Color.applePopupCanvas, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                        .allowsHitTesting(false)
                        .opacity(channelLeftFade ? 1 : 0)
                        .animation(Motion.easeInstant, value: channelLeftFade)
                }
                // 右渐变：右侧还有未看完的内容时浮现，提示可滚动
                .overlay(alignment: .trailing) {
                    LinearGradient(colors: [.clear, Color.applePopupCanvas], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                        .allowsHitTesting(false)
                        .opacity(channelRightFade ? 1 : 0)
                        .animation(Motion.easeInstant, value: channelRightFade)
                }
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
            .focused($nameFocused)
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

            Text(previewFullName)
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
