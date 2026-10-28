import SwiftUI

struct DateFolderPopover: View {
    @Environment(AppState.self) var state

    // 日期格式 pill（默认月日，空字符串 = 未选中）
    @State private var dateFormat: String = "MMdd"

    // 渠道 pill（默认线上，可多选，空数组 = 未选中）
    // 门店/规范 这类「品种」和线上/线下 平级，靠多选表达「门店 + 线上物料」
    @State private var channels: [String] = ["线上"]
    // "其他"被选中时，用户自定义的渠道文本（持久化，切回"其他"时保留）
    @AppStorage("datefolder_interactive_custom_channel") private var customChannel: String = ""

    // 用户自定义渠道标签列表（JSON 持久化）
    @AppStorage("datefolder_custom_channels_json") private var customChannelsJSON: String = "[]"
    // "新增标签"输入态
    @State private var isAddingChannel = false
    @State private var newChannelInput = ""
    @FocusState private var newChannelFocused: Bool
    // 当前 hover 的自定义标签名（用于显示右上角删除按钮）
    @State private var hoveringChannel: String?
    // 渠道行横向滚动状态（标签超出后左右渐变提示，复用单文件重命名的观察器）
    @State private var channelScrollGeom = ChannelScrollGeom()

    // 名称输入
    @State private var namePart: String = ""

    // 移入选中文件开关（默认开）
    @AppStorage("datefolder_move_selected") private var moveSelected: Bool = true

    // 创建状态
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    // "其他"输入框焦点：切到"其他"时自动聚焦，免二次点击
    @FocusState private var customChannelFocused: Bool

    private var selectedFileCount: Int {
        state.preloadedURLs.count
    }

    /// 创建目录的位置：优先用 Finder 当前窗口目录（用户"目前打开的文件位置"）
    private var targetDirectory: URL? {
        if let dir = FinderSelection.currentFinderDirectory() {
            return dir
        }
        // fallback：用选中文件所在目录
        if let firstURL = state.preloadedURLs.first {
            return firstURL.deletingLastPathComponent()
        }
        return nil
    }

    private let dateFormats: [(label: String, format: String)] = [
        ("月日", "MMdd"),
        ("年月", "yyMM"),
        ("年月日", "yyMMdd")
    ]

    private var dateLabel: String {
        dateFormat.isEmpty ? "" : DateFolderEngine.formatName(format: dateFormat, prefix: "", suffix: "")
    }
    /// 实际用于命名的渠道值：选"其他"时取 customChannel，其余取标签本身。
    /// 顺序按 pill 的固定顺序（线上 / 线下 / 自定义 / 其他）而不是点击先后，
    /// 这样「先点门店再点线上」和反过来得到的名字完全一致。
    private var effectiveChannels: [String] {
        let order = ["线上", "线下"] + customChannels + ["其他"]
        return order.filter { channels.contains($0) }.compactMap { ch in
            let value = ch == "其他" ? customChannel.trimmingCharacters(in: .whitespaces) : ch
            return value.isEmpty ? nil : value
        }
    }

    /// 多选开关：已选则取消，未选则追加（追加到末尾，渲染顺序仍由 effectiveChannels 决定）
    private func toggleChannel(_ ch: String) {
        if let index = channels.firstIndex(of: ch) {
            channels.remove(at: index)
        } else {
            channels.append(ch)
        }
    }

    // 渠道行渐变：已向右滚（离开最左）→ 左侧渐变；右侧还有内容 → 右侧渐变
    private var channelLeftFade: Bool { channelScrollGeom.offset > 1 }
    private var channelRightFade: Bool {
        channelScrollGeom.contentWidth > 0 &&
        channelScrollGeom.offset + channelScrollGeom.viewportWidth < channelScrollGeom.contentWidth - 1
    }

    /// 用户自定义渠道标签列表（从 JSON 反序列化）
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

    /// 新增自定义渠道：回车确认。空名直接取消；与内置/已有重名则切回普通态（不重复添加）
    private func addChannel() {
        let trimmed = newChannelInput.trimmingCharacters(in: .whitespaces)
        newChannelInput = ""
        isAddingChannel = false
        newChannelFocused = false
        guard !trimmed.isEmpty else { return }
        var list = customChannels
        let reserved = ["线上", "线下", "其他"]
        if list.contains(trimmed) || reserved.contains(trimmed) {
            // 已存在则仅加入选中，不重复添加
            if !channels.contains(trimmed) { channels.append(trimmed) }
            return
        }
        list.append(trimmed)
        saveCustomChannels(list)
        if !channels.contains(trimmed) { channels.append(trimmed) }  // 自动选中新标签
    }

    private func deleteChannel(_ ch: String) {
        var list = customChannels
        list.removeAll { $0 == ch }
        saveCustomChannels(list)
        channels.removeAll { $0 == ch }
        hoveringChannel = nil
    }
    /// 预览用的渠道文本（多选用 - 连接）
    private var channelText: String { effectiveChannels.joined(separator: "-") }

    /// 最终文件夹名：日期 / 各个渠道 / 项目名称 都用 - 拼接
    private var finalName: String {
        ([dateLabel] + effectiveChannels + [namePart])
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    var body: some View {
        VStack(spacing: 16) {
            headerArea
            Divider().padding(.horizontal, -24)
            optionsArea
            nameArea
            if selectedFileCount > 0 {
                moveFileArea
            }
            previewArea
            Spacer()
            createButton
            if showError {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 480, height: selectedFileCount > 0 ? 430 : 380)
        .background(Color.appleCanvas)
        .onAppear {
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: { $0.level == .screenSaver }) else { return }
                // 高度跟随是否有选中文件（moveFileArea 占额外 50 高度）
                let height = selectedFileCount > 0 ? 430 : 380
                window.setContentSize(NSSize(width: 480, height: height))
                window.styleMask.remove(.resizable)
                window.isMovableByWindowBackground = true
                FinderSelection.positionWindowNearFinder(window)
                window.level = .screenSaver
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private var headerArea: some View {
        HStack {
            Text("新建文件夹")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Spacer()
            // 清空按钮：清除日期/渠道选中 + 名称输入 + 新增标签输入态
            Button {
                dateFormat = ""
                channels.removeAll()
                namePart = ""
                customChannelFocused = false
                isAddingChannel = false
                newChannelInput = ""
                newChannelFocused = false
                hoveringChannel = nil
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("清空所有选中与输入")
        }
    }

    private var optionsArea: some View {
        VStack(spacing: 12) {
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
                            // 再点一次取消选中
                            dateFormat = (dateFormat == item.format) ? "" : item.format
                        }
                    )
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("渠道")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
                // 标签区横向滚动：超出后左右渐变提示，不再挤压任何按钮
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // 线上 / 线下（再点一次取消选中）—— 跟日期行同款 appleSurface2 色块
                        ForEach(["线上", "线下"], id: \.self) { ch in
                            PillButton(
                                label: ch,
                                isSelected: channels.contains(ch),
                                action: { toggleChannel(ch) }
                            )
                        }
                        // 用户自定义渠道（排在"其他"之前，再点一次取消选中）
                        ForEach(customChannels, id: \.self) { ch in
                            customChannelPill(ch)
                        }
                        // "其他" pill：未选中时是普通 pill，
                        // 选中时变成内联输入框（灰底蓝描边，右侧 × 按钮可退出"其他"）
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
                                    .onSubmit {
                                        create()
                                    }
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
                                // × 退出"其他"：Image + frame(28,28) + contentShape 保证整个区域可点击
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
                            // "其他"未选中：比固定标签稍微暗一些的灰底色块（无描边），表示可输入入口
                            Button {
                                toggleChannel("其他")
                                // 切换后等 TextField 渲染完成再聚焦
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
                        // "+新增"虚线按钮：点击切换为内联输入框（最淡，纯辅助入口）
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
                            .padding(.vertical, 6)
                            .frame(minHeight: 32)
                            .background(Color.appleSurface2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.appleBlue, lineWidth: 1.5)
                            )
                            .overlay(alignment: .trailing) {
                                // × 取消新增：Image + frame(28,28) + contentShape 保证整个区域可点击
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
                                .padding(.vertical, 6)
                                .frame(minHeight: 32)
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
                // 左渐变：已向右滚动（离开最左）时浮现
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [Color.appleCanvas, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                        .allowsHitTesting(false)
                        .opacity(channelLeftFade ? 1 : 0)
                        .animation(Motion.easeInstant, value: channelLeftFade)
                }
                // 右渐变：右侧还有未看完的内容时浮现
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

    /// 用户自定义渠道 pill：点击切换选中（再点一次取消），hover 时右上角浮出小红删除按钮
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

    private var nameArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件夹名称")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            HStack(spacing: 6) {
                // 时间标签（只读，未选日期时显示占位）
                Text(dateLabel.isEmpty ? "日期" : dateLabel)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(dateLabel.isEmpty ? Color.appleSoft : Color.appleInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // 渠道标签（只读，未选渠道时显示占位）：宽度按内容自适应，
                // 渠道越多标签越宽、后面输入框越窄；文本过长时中间截断
                Text(channelText.isEmpty ? "渠道" : channelText)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(channelText.isEmpty ? Color.appleSoft : Color.appleInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // 名称输入框：吃掉剩余宽度；渠道标签过长时保底 120pt，不让输入框被挤没
                TextField("输入项目名称", text: $namePart)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minWidth: 120)
                    .onSubmit {
                        // TextField 聚焦时按回车触发创建
                        // 注意：Button 的 .keyboardShortcut(.return) 可能同时触发，
                        // 所以 create() 开头有 guard !isCreating 防止重复创建
                        create()
                    }
            }
        }
    }

    private var previewArea: some View {
        HStack(spacing: 4) {
            Text("预览:")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleMuted)
            Text(finalName.isEmpty ? "（至少选择一项）" : finalName)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(finalName.isEmpty ? Color.appleMuted : Color.appleSoft)
            Spacer()
        }
    }

    private var moveFileArea: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $moveSelected) {
                Text("将 \(selectedFileCount) 个选中文件移入新文件夹")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            .toggleStyle(.checkbox)
            Spacer()
        }
    }

    private var createButton: some View {
        Button(action: create) {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isCreating ? "创建中…" : "创建文件夹")
                    .font(.system(size: 17, weight: .regular))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isCreating ? Color.appleBlue.opacity(0.7) : Color.appleBlue)
            .clipShape(RoundedRectangle(cornerRadius: 980))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(isCreating || finalName.isEmpty)
    }

    private func create() {
        // 用 NSLock 保证原子性，防止 onSubmit + keyboardShortcut 同时触发 create()
        // 导致创建多个文件夹。@State 的更新在 SwiftUI 中可能有延迟，guard !isCreating 不可靠。
        guard DateFolderEngine.tryAcquireCreateLock() else {
            AppLog.shared.log("create() 被拦截：已有创建进行中", category: "Dispatcher", level: .warn)
            return
        }
        isCreating = true
        let urls = state.preloadedURLs
        let name = finalName
        let shouldMove = moveSelected && selectedFileCount > 0
        let directory = targetDirectory

        Task {
            do {
                if let dir = directory {
                    _ = try DateFolderEngine.runInteractiveInDirectory(
                        directory: dir, urls: urls, name: name, moveSelectedFiles: shouldMove
                    )
                } else {
                    _ = try DateFolderEngine.runInteractive(
                        urls: urls, name: name, moveSelectedFiles: shouldMove
                    )
                }
                await MainActor.run {
                    let bodySuffix = shouldMove ? "（已移入 \(selectedFileCount) 个文件）" : ""
                    AppNotification.send(title: "文件夹已创建", body: name + bodySuffix)
                    // 注意：不在这里释放锁也不重置 isCreating
                    // 因为窗口 0.6s 后才关，这期间用户再按回车会再次触发 create()
                    // 锁延迟到窗口关闭时释放，防止 0.6s 窗口期内重复创建
                    AppLog.shared.log("文件夹创建完成 name=\(name)", category: "Dispatcher", level: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        AppLog.shared.log("文件夹弹窗完成，关闭窗口", category: "Dispatcher")
                        for window in NSApp.windows where window.level == .screenSaver {
                            window.close()
                        }
                        namePart = ""
                        isCreating = false
                        DateFolderEngine.releaseCreateLock()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCreating = false
                    DateFolderEngine.releaseCreateLock()
                }
            }
        }
    }
}
