import SwiftUI
import UserNotifications

struct DateFolderPopover: View {
    @Environment(AppState.self) var state

    // 日期格式 pill（决定底部时间标签的显示格式）
    @State private var dateFormat: String = "MMdd"  // 默认月日

    // 渠道 pill（记忆上次选择）：线上/线下/其他
    @AppStorage("datefolder_interactive_channel") private var channel: String = "线上"
    // "其他"被选中时，用户自定义的渠道文本（持久化，切回"其他"时保留）
    @AppStorage("datefolder_interactive_custom_channel") private var customChannel: String = ""

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
    private let channels = ["线上", "线下", "其他"]

    private var dateLabel: String {
        DateFolderEngine.formatName(format: dateFormat, prefix: "", suffix: "")
    }
    /// 实际用于命名的渠道值：选"其他"时取 customChannel，否则取 channel
    private var effectiveChannel: String {
        channel == "其他" ? customChannel : channel
    }
    private var finalName: String {
        "\(dateLabel)-\(effectiveChannel)-\(namePart)"
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
                        action: { dateFormat = item.format }
                    )
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("渠道")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
                // 线上 / 线下
                ForEach(["线上", "线下"], id: \.self) { ch in
                    PillButton(
                        label: ch,
                        isSelected: channel == ch,
                        action: { channel = ch }
                    )
                }
                // "其他" pill：未选中时是普通 pill（带编辑 icon 提示可自定义），
                // 选中时变成内联输入框（灰底蓝描边，直接在 pill 位置编辑）
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
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onAppear { customChannelFocused = true }
                } else {
                    PillButton(
                        label: "其他",
                        isSelected: false,
                        action: {
                            channel = "其他"
                            // 切换后等 TextField 渲染完成再聚焦
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                customChannelFocused = true
                            }
                        }
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var nameArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件夹名称")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            HStack(spacing: 6) {
                // 时间标签（只读）
                Text(dateLabel)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // 渠道标签（只读）：显示实际生效的渠道值（选"其他"时为 customChannel）
                Text(effectiveChannel.isEmpty ? "渠道" : effectiveChannel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(effectiveChannel.isEmpty ? Color.appleSoft : Color.appleInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // 名称输入框
                TextField("输入项目名称", text: $namePart)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
            Text(namePart.isEmpty ? "\(dateLabel)-\(effectiveChannel)-" : finalName)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.appleSoft)
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
        .disabled(isCreating || namePart.isEmpty || effectiveChannel.isEmpty)
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
                let createdURL: URL
                if let dir = directory {
                    createdURL = try DateFolderEngine.runInteractiveInDirectory(
                        directory: dir, urls: urls, name: name, moveSelectedFiles: shouldMove
                    )
                } else {
                    createdURL = try DateFolderEngine.runInteractive(
                        urls: urls, name: name, moveSelectedFiles: shouldMove
                    )
                }
                await MainActor.run {
                    let bodySuffix = shouldMove ? "（已移入 \(selectedFileCount) 个文件）" : ""
                    sendNotification(title: "文件夹已创建", body: name + bodySuffix)
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

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
