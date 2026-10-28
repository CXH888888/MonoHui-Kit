import SwiftUI
import AppKit

// MARK: - 渠道行横向滚动（复用批量重命名更名预览的观察器方案，坐标轴换成水平）
struct ChannelScrollGeom: Equatable {
    var offset: CGFloat = 0         // 0 = 最左，向右滚动为正
    var contentWidth: CGFloat = 0   // 内容总宽
    var viewportWidth: CGFloat = 0  // 视口（可见区）宽度
}

final class ChannelScrollObserverView: NSView {
    var onChange: ((ChannelScrollGeom) -> Void)?
    private var observingClip = false
    private var observingDoc = false
    private var monitor: Any?
    private var lastGeom: ChannelScrollGeom?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startObservingIfNeeded()
            installWheelMonitorIfNeeded()
        } else {
            removeWheelMonitor()
        }
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        guard window != nil else { return }
        startObservingIfNeeded()
        // 布局完成后重读一次（等值守卫防循环）：标签增删会改变内容宽度
        DispatchQueue.main.async { [weak self] in
            self?.scrollChanged()
        }
    }

    deinit {
        removeWheelMonitor()
    }

    private func startObservingIfNeeded() {
        if !observingClip,
           let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollChanged),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
            observingClip = true
        }
        // 标签增删改变内容宽度时不触发 clip bounds 通知，需单独监听 documentView 的 frame 变化
        if !observingDoc,
           let doc = enclosingScrollView?.documentView {
            doc.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollChanged),
                name: NSView.frameDidChangeNotification,
                object: doc
            )
            observingDoc = true
        }
        scrollChanged()
    }

    @objc private func scrollChanged() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let geom = ChannelScrollGeom(
            offset: clip.bounds.origin.x,
            contentWidth: clip.documentView?.frame.width ?? 0,
            viewportWidth: clip.bounds.width
        )
        // 值未变化时不再回写，避免 viewWillDraw → 状态更新 → 重绘 的循环
        guard geom != lastGeom else { return }
        lastGeom = geom
        onChange?(geom)
    }

    // macOS 横向 ScrollView 不响应竖向滚轮（触控板横向滑动原生支持），鼠标用户需转换
    private func installWheelMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  let clip = self.enclosingScrollView?.contentView,
                  event.window === self.window,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
            else { return event }
            // 仅当内容超宽（可横向滚动）且光标在滚动区内时接管
            let contentWidth = clip.documentView?.frame.width ?? 0
            guard contentWidth > clip.bounds.width + 1 else { return event }
            let clipFrame = clip.convert(clip.bounds, to: nil)
            guard clipFrame.contains(event.locationInWindow) else { return event }
            let maxX = contentWidth - clip.bounds.width
            let newX = min(max(clip.bounds.origin.x - event.scrollingDeltaY, 0), maxX)
            clip.scroll(to: NSPoint(x: newX, y: 0))
            return nil
        }
    }

    private func removeWheelMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

struct ChannelScrollObserver: NSViewRepresentable {
    var onChange: (ChannelScrollGeom) -> Void

    func makeNSView(context: Context) -> ChannelScrollObserverView {
        let view = ChannelScrollObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ChannelScrollObserverView, context: Context) {
        view.onChange = onChange
    }
}

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
    @FocusState private var newChannelFocused: Bool
    @State private var hoveringChannel: String?
    @FocusState private var customChannelFocused: Bool
    // 渠道行横向滚动状态（标签超出后左右渐变提示）
    @State private var channelScrollGeom = ChannelScrollGeom()

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
    // 状态卡网格滚动（标签超 2 行后内部滚动，复用批量弹窗的观察器方案）
    @State private var statusScrollGeom = PreviewScrollGeom()

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
        channelScrollGeom.contentWidth > 0 &&
        channelScrollGeom.offset + channelScrollGeom.viewportWidth < channelScrollGeom.contentWidth - 1
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
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.level == .screenSaver }) else { return }
            window.styleMask.remove(.resizable)
            window.isMovableByWindowBackground = true
            // 让窗口根据 SwiftUI 内容自动调整高度
            window.contentMinSize = NSSize(width: 480 + 2 * Motion.popupShadowInset,
                                           height: 400 + 2 * Motion.popupShadowInset)
            window.contentMaxSize = NSSize(width: 480 + 2 * Motion.popupShadowInset,
                                           height: 1200 + 2 * Motion.popupShadowInset)
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
                            customChannelPill(ch)
                        }
                        if channels.contains("其他") {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Color.appleBlue)
                                TextField("输入", text: $customChannel)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.center)
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
                                    channels.removeAll { $0 == "其他" }
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
                                toggleChannel("其他")
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
                                    .multilineTextAlignment(.center)
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
                    }
                    .background(
                        ChannelScrollObserver { geom in
                            channelScrollGeom = geom
                        }
                    )
                }
                // 左渐变：已向右滚动（离开最左）时浮现，避免内容生硬截断
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [Color.appleCanvas, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                        .allowsHitTesting(false)
                        .opacity(channelLeftFade ? 1 : 0)
                        .animation(Motion.easeInstant, value: channelLeftFade)
                }
                // 右渐变：右侧还有未看完的内容时浮现，提示可滚动
                .overlay(alignment: .trailing) {
                    LinearGradient(colors: [.clear, Color.appleCanvas], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                        .allowsHitTesting(false)
                        .opacity(channelRightFade ? 1 : 0)
                        .animation(Motion.easeInstant, value: channelRightFade)
                }
            }
        }
    }

    // MARK: - customChannelPill
    @ViewBuilder
    private func customChannelPill(_ ch: String) -> some View {
        let isSelected = channels.contains(ch)
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
        // 圆角背景用 shape 画（不再用 clipShape，避免裁到右上角溢出的删除按钮）
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.appleBlue : Color.appleSurface2)
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    deleteChannel(ch)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white, Color.red.opacity(0.9))
                        .background(
                            Circle()
                                .fill(Color.appleCanvas)
                                .frame(width: 18, height: 18)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleChannel(ch)
        }
        .onHover { hovering in
            withAnimation(Motion.moveFast) {
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
                    PreviewScrollObserver { geom in
                        if statusScrollGeom != geom {
                            statusScrollGeom = geom
                        }
                    }
                )
            }
            .frame(height: Self.statusGridViewportHeight)
            // 顶部渐变：滚动离开顶部后浮现（遮罩色 = 卡片底合成到弹窗底的不透明等效色）
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.appleCardOnCanvas, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.statusGridFadeHeight)
                    .allowsHitTesting(false)
                    .opacity(statusTopFade ? 1 : 0)
                    .animation(Motion.easeInstant, value: statusTopFade)
            }
            // 底部渐变：下方还有未看完的内容时浮现，滚到底自动消失，与顶部对称
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color.appleCardOnCanvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.statusGridFadeHeight)
                    .allowsHitTesting(false)
                    .opacity(statusBottomFade ? 1 : 0)
                    .animation(Motion.easeInstant, value: statusBottomFade)
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

    /// 状态网格视口固定高度（2 行：28 × 2 + 间距 6）
    private static let statusGridViewportHeight: CGFloat = 62
    /// 状态网格渐变高度：与批量弹窗编辑器一致（28pt 行高的约 1/3）
    private static let statusGridFadeHeight: CGFloat = 10

    private var statusTopFade: Bool { statusScrollGeom.offset > 1 }

    // 与批量更名预览 showPreviewBottomFade 完全一致的单行表达式
    private var statusBottomFade: Bool {
        statusScrollGeom.contentHeight - statusScrollGeom.viewportHeight - statusScrollGeom.offset > 1
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
                                .foregroundStyle(.white, Color.red.opacity(0.9))
                                .background(
                                    Circle()
                                        .fill(Color.appleCanvas)
                                        .frame(width: 18, height: 18)
                                )
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
