import SwiftUI
import AppKit

// MARK: - 字段模式
enum BatchFieldMode: String, CaseIterable {
    case unify = "统一"
    case keep = "保留"
}

// MARK: - 字段配置
struct BatchFieldConfig {
    let key: String       // date/channel/name/version/status
    let label: String
    var mode: BatchFieldMode
    var unifyValue: String
    var dateFormat: String  // 仅 date 使用
    var enabled: Bool = true  // 是否参与重命名
}

// MARK: - 预览区滚动检测
// macOS 14 的 SwiftUI preference 在滚动过程中不更新，改用 AppKit 通知直读 NSScrollView
struct PreviewScrollGeom: Equatable {
    var offset: CGFloat = 0         // 0 = 顶部，向下滚动为正
    var contentHeight: CGFloat = 0  // 列表内容总高
    var viewportHeight: CGFloat = 0 // 视口（可见区）高度
}

final class PreviewScrollObserverView: NSView {
    var onChange: ((PreviewScrollGeom) -> Void)?
    private var observingClip = false
    private var observingDoc = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        startObservingIfNeeded()
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        guard window != nil else { return }
        startObservingIfNeeded()
        // 布局完成后重读一次（等值守卫防循环）：懒网格行实例化、标签增删都会改变内容高度
        DispatchQueue.main.async { [weak self] in
            self?.scrollChanged()
        }
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
        // 内容高度变化（标签增删/懒网格展开）不触发 clip bounds 通知，需单独监听 documentView 的 frame 变化
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

    private var lastGeom: PreviewScrollGeom?

    @objc private func scrollChanged() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let geom = PreviewScrollGeom(
            offset: clip.bounds.origin.y,
            contentHeight: clip.documentView?.frame.height ?? 0,
            viewportHeight: clip.bounds.height
        )
        // 值未变化时不再回写，避免 viewWillDraw → 状态更新 → 重绘 的循环
        guard geom != lastGeom else { return }
        lastGeom = geom
        onChange?(geom)
    }
}

struct PreviewScrollObserver: NSViewRepresentable {
    var onChange: (PreviewScrollGeom) -> Void

    func makeNSView(context: Context) -> PreviewScrollObserverView {
        let view = PreviewScrollObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: PreviewScrollObserverView, context: Context) {
        view.onChange = onChange
    }
}

struct PreviewRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - 批量重命名弹窗
struct QuickRenameBatchPopover: View {
    @Environment(AppState.self) var state

    // 解析后的文件列表
    @State private var files: [URL] = []

    // 字段配置
    @State private var fieldConfigs: [BatchFieldConfig] = []

    // 每个文件每个字段的手动覆盖
    @State private var overrides: [[String: String]] = []

    // 预览区正在编辑的标签
    @State private var editingTag: EditingTag?

    // 自定义渠道和状态（与单文件改名共享）
    @AppStorage("datefolder_custom_channels_json") private var customChannelsJSON: String = "[]"
    @AppStorage("quickrename_custom_statuses_json") private var customStatusesJSON: String = "[]"

    // 渠道编辑状态（可多选，命名时用 - 连接）
    @State private var channels: [String] = ["线上"]
    @State private var customChannel: String = ""
    @State private var isAddingChannel = false
    @State private var newChannelInput = ""
    @State private var hoveringChannel: String? = nil
    @FocusState private var newChannelFocused: Bool
    @FocusState private var customChannelFocused: Bool

    // 状态编辑状态
    @State private var status: String = "草稿"
    @State private var isAddingStatus = false
    @State private var newStatusInput = ""
    @State private var hoveringStatus: String? = nil
    @FocusState private var newStatusFocused: Bool

    // 名字
    @State private var namePart: String = ""

    // 版本
    @State private var versionNumber: Int = 1

    // 日期
    @State private var dateFormat: String = "yyMMdd"

    // 重命名状态
    @State private var isRenaming = false
    @State private var showError = false
    @State private var errorMessage = ""

    // 预览区滚动状态（默认 3 行，超出滚动 + 顶/底渐变遮罩）
    // 更名预览每行固定高度：重名加序号标签等不再改变行高，整个窗口高度稳定不撑开
    private let previewRowHeight: CGFloat = 60
    @State private var previewScrollGeom = PreviewScrollGeom()
    // 细滚动条：仅滚动期间显示，停止 0.9s 后淡出
    @State private var scrollbarVisible = false
    @State private var scrollbarHideTask: DispatchWorkItem?

    // 字段编辑器滚动状态（渠道/状态等网格编辑器内部滚动），key = 字段 key
    @State private var editorScrollGeoms: [String: PreviewScrollGeom] = [:]

    struct EditingTag: Equatable {
        let fileIdx: Int
        let fieldKey: String
    }

    // 记忆上次的字段模式与设置项，下次打开时恢复
    private struct SavedBatchConfig: Codable {
        var modes: [String: String] = [:]   // fieldKey -> "unify"/"keep"
        var enabled: [String: Bool] = [:]   // fieldKey -> 是否参与
        var channel: String = ""
        var status: String = ""
        var dateFormat: String = ""
        var version: String = ""
    }

    private let savedConfigKey = "quickrename_batch_config_json"

    private let dateFormats: [(label: String, format: String)] = [
        ("月日", "MMdd"),
        ("年月", "yyMM"),
        ("年月日", "yyMMdd")
    ]

    // MARK: - 数据计算

    private var customChannels: [String] {
        guard let data = customChannelsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    /// 选中渠道按 pill 固定顺序展开，"其他"替换成自定义文本
    private var effectiveChannels: [String] {
        let order = ["线上", "线下"] + customChannels + ["其他"]
        return order.filter { channels.contains($0) }.compactMap { ch in
            let value = ch == "其他" ? customChannel.trimmingCharacters(in: .whitespaces) : ch
            return value.isEmpty ? nil : value
        }
    }

    /// 写进 BatchFieldConfig.unifyValue 的渠道字符串
    private var channelValue: String { effectiveChannels.joined(separator: "-") }

    /// 把存下来的渠道字符串还原成多选状态（空串表示用户主动清空，保持空）
    static func splitChannels(_ value: String) -> [String] {
        value.isEmpty ? [] : value.split(separator: "-").map(String.init)
    }

    private func toggleChannel(_ ch: String) {
        if let index = channels.firstIndex(of: ch) {
            channels.remove(at: index)
        } else {
            channels.append(ch)
        }
    }

    private var customStatuses: [String] {
        guard let data = customStatusesJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    private var allStatuses: [String] {
        QuickRenameEngine.defaultStatuses + customStatuses
    }

    /// 获取某文件某字段的最终值
    private func fieldValue(fileIdx: Int, key: String) -> String {
        // 字段被关闭时整体退出命名（预览区标签随之隐藏）
        if let cfg = fieldConfigs.first(where: { $0.key == key }), !cfg.enabled {
            return ""
        }
        if let override = overrides[fileIdx][key], !override.isEmpty {
            return override
        }
        guard let config = fieldConfigs.first(where: { $0.key == key }) else { return "" }
        if config.mode == .unify {
            return config.unifyValue
        }
        // 保留模式：用解析出的原值
        return originalValue(fileIdx: fileIdx, key: key)
    }

    /// 从解析结果获取原值
    private func originalValue(fileIdx: Int, key: String) -> String {
        guard fileIdx < files.count else { return "" }
        let url = files[fileIdx]
        let parsed = QuickRenameEngine.parse(
            fileName: url.lastPathComponent,
            customChannels: customChannels,
            customStatuses: customStatuses
        )
        switch key {
        case "date":
            return parsed.date
        case "channel":
            return parsed.channel
        case "name":
            return parsed.name
        case "version":
            return parsed.version.map { String($0) } ?? ""
        case "status":
            return parsed.status
        default:
            return ""
        }
    }

    /// 生成某文件的新文件名（不含扩展名）
    private func buildNameForFile(fileIdx: Int, dupSuffix: Int? = nil) -> String {
        let date = fieldValue(fileIdx: fileIdx, key: "date")
        let ch = fieldValue(fileIdx: fileIdx, key: "channel")
        let name = fieldValue(fileIdx: fileIdx, key: "name")
        let verStr = fieldValue(fileIdx: fileIdx, key: "version")
        let ver = Int(verStr)
        let st = fieldValue(fileIdx: fileIdx, key: "status")

        var built = QuickRenameEngine.buildName(
            date: date, channel: ch, name: name,
            version: ver, versionEnabled: !verStr.isEmpty, status: st
        )
        if let suffix = dupSuffix {
            built += " \(suffix)"
        }
        return built
    }

    /// 获取某文件的扩展名
    private func extForFile(fileIdx: Int) -> String {
        guard fileIdx < files.count else { return "" }
        return files[fileIdx].pathExtension
    }

    /// 获取某文件的原始完整文件名
    private func originalFullName(fileIdx: Int) -> String {
        guard fileIdx < files.count else { return "" }
        return files[fileIdx].lastPathComponent
    }

    /// 预览区右对齐展示的更改后完整文件名（含重名后缀与扩展名）
    private func fullNewName(fileIdx: Int) -> String {
        let suffixes = duplicateSuffixes
        let dupSuffix = fileIdx < suffixes.count ? suffixes[fileIdx] : nil
        let newName = buildNameForFile(fileIdx: fileIdx, dupSuffix: dupSuffix)
        let ext = extForFile(fileIdx: fileIdx)
        return ext.isEmpty ? newName : "\(newName).\(ext)"
    }

    /// 检测重名并返回每个文件的序号后缀
    private var duplicateSuffixes: [Int?] {
        var names: [String] = []
        for i in 0..<files.count {
            let name = buildNameForFile(fileIdx: i) + "." + extForFile(fileIdx: i)
            names.append(name)
        }
        var counts: [String: Int] = [:]
        names.forEach { counts[$0, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return names.map { n in
            if counts[n]! > 1 {
                seen[n, default: 0] += 1
                return seen[n]
            }
            return nil
        }
    }

    private var hasDuplicates: Bool {
        duplicateSuffixes.contains { $0 != nil }
    }

    // MARK: - 预览区滚动计算

    /// 预览列表最大高度 = 3 行 + 2 个行间距（行高运行时测量）
    private var previewListMaxHeight: CGFloat {
        previewRowHeight * 3 + 6 * 2
    }

    /// 列表实际高度：内容不足 3 行时按内容高度收缩，超出封顶 3 行（此时可滚动）
    private var previewListFitHeight: CGFloat {
        previewScrollGeom.contentHeight > 0
            ? min(previewScrollGeom.contentHeight, previewListMaxHeight)
            : previewListMaxHeight
    }

    /// 顶部渐变：已向下滚动（离开顶部）时显示
    private var showPreviewTopFade: Bool {
        previewScrollGeom.offset > 1
    }

    /// 底部渐变：下方还有未看完的内容时显示
    private var showPreviewBottomFade: Bool {
        previewScrollGeom.contentHeight - previewScrollGeom.viewportHeight - previewScrollGeom.offset > 1
    }

    /// 内容是否溢出视口（决定是否显示细滚动条）
    private var previewOverflow: Bool {
        previewScrollGeom.contentHeight > previewScrollGeom.viewportHeight + 1
    }

    /// 所有字段是否都有值（用于按钮启用判断）
    private var canRename: Bool {
        !isRenaming && !files.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            headerArea
            Divider().padding(.horizontal, -24)
            fileInfoArea
            fieldGridArea
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
        .frame(width: 560)
        .background(Color.appleCanvas)
        .onAppear { onAppearInit() }
    }

    // MARK: - 初始化

    private func onAppearInit() {
        files = state.preloadedURLs

        // 解析每个文件
        // 默认模式：日期=保留，渠道=统一，名字=统一，版本=统一，状态=保留
        fieldConfigs = [
            BatchFieldConfig(key: "date", label: "日期", mode: .keep, unifyValue: "", dateFormat: "yyMMdd"),
            BatchFieldConfig(key: "channel", label: "渠道", mode: .unify, unifyValue: "线上", dateFormat: ""),
            BatchFieldConfig(key: "name", label: "名字", mode: .unify, unifyValue: "", dateFormat: ""),
            BatchFieldConfig(key: "version", label: "版本", mode: .unify, unifyValue: "1", dateFormat: ""),
            BatchFieldConfig(key: "status", label: "状态", mode: .keep, unifyValue: "草稿", dateFormat: "")
        ]

        // 初始化覆盖数组
        overrides = files.map { _ in [:] }

        // 初始化统一值：从第一个文件解析
        if let firstUrl = files.first {
            let parsed = QuickRenameEngine.parse(
                fileName: firstUrl.lastPathComponent,
                customChannels: customChannels,
                customStatuses: customStatuses
            )
            // 日期统一值：用今天
            if let dateConfigIdx = fieldConfigs.firstIndex(where: { $0.key == "date" }) {
                fieldConfigs[dateConfigIdx].unifyValue = QuickRenameEngine.formatName(format: "yyMMdd")
            }
            // 名字统一值：用第一个文件的名字
            if let nameConfigIdx = fieldConfigs.firstIndex(where: { $0.key == "name" }) {
                fieldConfigs[nameConfigIdx].unifyValue = parsed.name
            }
            // 版本统一值：用第一个文件的版本+1
            if let versionConfigIdx = fieldConfigs.firstIndex(where: { $0.key == "version" }) {
                fieldConfigs[versionConfigIdx].unifyValue = String(QuickRenameEngine.nextVersion(current: parsed.version))
            }
            // 渠道和状态用默认值
            channels = ["线上"]
            status = "草稿"
            namePart = parsed.name
            versionNumber = QuickRenameEngine.nextVersion(current: parsed.version)
        }

        // 同步编辑器缓冲（平铺卡片初始化）
        syncAllEditorsFromConfig()

        // 应用上次记忆的配置（字段模式与渠道/状态/日期/版本）
        applySavedConfig()

        // 窗口校准
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.level == .screenSaver }) else { return }
            window.styleMask.remove(.resizable)
            window.isMovableByWindowBackground = true
            window.contentMinSize = NSSize(width: 560, height: 500)
            window.contentMaxSize = NSSize(width: 560, height: 1200)
            FinderSelection.positionWindowNearFinder(window)
            window.level = .screenSaver
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 同步编辑器缓冲（平铺卡片渲染时一次性从配置读数）
    private func syncAllEditorsFromConfig() {
        for config in fieldConfigs {
            switch config.key {
            case "date":
                dateFormat = config.dateFormat
            case "channel":
                channels = Self.splitChannels(config.unifyValue)
            case "name":
                namePart = config.unifyValue
            case "version":
                versionNumber = Int(config.unifyValue) ?? 1
            case "status":
                status = config.unifyValue
            default:
                break
            }
        }
    }

    /// 按字段 key 将编辑器缓冲写回对应 fieldConfig
    private func saveEditorState(for key: String) {
        guard let idx = fieldConfigs.firstIndex(where: { $0.key == key }) else { return }
        switch key {
        case "date":
            fieldConfigs[idx].dateFormat = dateFormat
            fieldConfigs[idx].unifyValue = dateFormat == "original" ? "" : QuickRenameEngine.formatName(format: dateFormat)
        case "channel":
            fieldConfigs[idx].unifyValue = channelValue
        case "name":
            fieldConfigs[idx].unifyValue = namePart
        case "version":
            fieldConfigs[idx].unifyValue = String(versionNumber)
        case "status":
            fieldConfigs[idx].unifyValue = status
        default:
            break
        }
        saveCurrentConfig()
    }

    /// 重命名前兜底：保存所有字段的编辑器缓冲
    private func saveAllEditors() {
        for key in ["date", "channel", "name", "version", "status"] {
            saveEditorState(for: key)
        }
    }

    // MARK: - 配置记忆

    private func loadSavedConfig() -> SavedBatchConfig? {
        guard let data = UserDefaults.standard.data(forKey: savedConfigKey),
              let cfg = try? JSONDecoder().decode(SavedBatchConfig.self, from: data) else { return nil }
        return cfg
    }

    private func saveCurrentConfig() {
        var cfg = SavedBatchConfig()
        for config in fieldConfigs {
            cfg.modes[config.key] = config.mode == .unify ? "unify" : "keep"
            cfg.enabled[config.key] = config.enabled
        }
        cfg.channel = fieldConfigs.first(where: { $0.key == "channel" })?.unifyValue ?? ""
        cfg.status = fieldConfigs.first(where: { $0.key == "status" })?.unifyValue ?? ""
        cfg.dateFormat = fieldConfigs.first(where: { $0.key == "date" })?.dateFormat ?? ""
        cfg.version = fieldConfigs.first(where: { $0.key == "version" })?.unifyValue ?? ""
        if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: savedConfigKey)
        }
    }

    /// 将上次记忆的配置应用到当前弹窗（覆盖字段模式与设置项，不覆盖名字）
    private func applySavedConfig() {
        guard let saved = loadSavedConfig() else { return }
        for idx in fieldConfigs.indices {
            let key = fieldConfigs[idx].key
            if let m = saved.modes[key] {
                fieldConfigs[idx].mode = (m == "unify") ? .unify : .keep
            }
            if let e = saved.enabled[key] {
                fieldConfigs[idx].enabled = e
            }
        }
        if let dIdx = fieldConfigs.firstIndex(where: { $0.key == "date" }), !saved.dateFormat.isEmpty {
            fieldConfigs[dIdx].dateFormat = saved.dateFormat
            fieldConfigs[dIdx].unifyValue = QuickRenameEngine.formatName(format: saved.dateFormat)
        }
        if !saved.channel.isEmpty, let chIdx = fieldConfigs.firstIndex(where: { $0.key == "channel" }) {
            fieldConfigs[chIdx].unifyValue = saved.channel
            channels = Self.splitChannels(saved.channel)
        }
        if !saved.status.isEmpty, let stIdx = fieldConfigs.firstIndex(where: { $0.key == "status" }) {
            fieldConfigs[stIdx].unifyValue = saved.status
            status = saved.status
        }
        if let ver = Int(saved.version), let vIdx = fieldConfigs.firstIndex(where: { $0.key == "version" }) {
            fieldConfigs[vIdx].unifyValue = String(ver)
            versionNumber = ver
        }
        syncAllEditorsFromConfig()
    }

    // MARK: - Header

    private var headerArea: some View {
        HStack {
            Text("批量重命名")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.appleInk)
            Spacer()
            Button {
                resetAll()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("重置")
        }
    }

    // MARK: - 文件信息

    private var fileInfoArea: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.appleBlue)
                .frame(width: 32, height: 32)
                .background(Color.appleSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(files.count) 个文件")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                if let firstUrl = files.first {
                    Text(firstUrl.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(files.count) 项")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.appleSurface3)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 字段区（两栏网格卡片布局）

    // 两栏网格：日期/渠道 + （名字独占一行）+ 版本/状态（等高）
    private var fieldGridArea: some View {
        VStack(spacing: 12) {
            // 日期/渠道两卡片等高（与版本/状态一致）
            HStack(alignment: .top, spacing: 12) {
                batchFieldCard(fieldConfig(key: "date"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                batchFieldCard(fieldConfig(key: "channel"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            // 名字内容较少（完整输入框），独占一行，卡片高度自适应
            batchFieldCard(fieldConfig(key: "name"))
            // 版本/状态两卡片等高（参考单文件重命名弹窗）
            HStack(alignment: .top, spacing: 12) {
                batchFieldCard(fieldConfig(key: "version"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                batchFieldCard(fieldConfig(key: "status"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 按 key 取字段配置（缺失时返回占位，避免布局中断）
    private func fieldConfig(key: String) -> BatchFieldConfig {
        fieldConfigs.first(where: { $0.key == key })
            ?? BatchFieldConfig(key: key, label: key, mode: .unify, unifyValue: "", dateFormat: "")
    }

    // 字段卡片：标题行（字段名 + 统一/保留胶囊 + 右对齐启停开关）+ 值编辑区
    @ViewBuilder
    private func batchFieldCard(_ config: BatchFieldConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(config.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                modeCapsule(config)
                Spacer(minLength: 0)
                circleCheckbox(isOn: config.enabled)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleEnabled(config) }
                    .help(config.enabled ? "关闭该字段" : "启用该字段")
            }
            if config.key == "name" {
                // 名字：固定 34pt 外壳——启用时输入框 / 保留时提示 / 关闭时提示都在内，高度恒定
                ZStack {
                    if !config.enabled {
                        disabledHintView(config)
                    } else if config.mode == .keep {
                        keepHintView(config)
                    } else {
                        unifiedEditor(config)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            } else if config.enabled {
                if config.mode == .keep {
                    keepHintView(config)
                        .frame(height: 62)
                } else {
                    // 网格编辑器：固定高度（对齐“状态两行”），标签溢出时内部滚动
                    editorScrollContainer(key: config.key)
                }
            } else {
                // 关闭：灰底提示撑满卡片宽、内容居中（62pt）
                disabledHintView(config)
                    .frame(height: 62)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.appleSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    config.enabled
                        ? (config.mode == .unify ? Color.appleBlue.opacity(0.3) : Color.orange.opacity(0.3))
                        : Color.appleDivider,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // 圆形复选框（与单文件重命名弹窗一致，12pt）
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

    // 网格编辑器滚动容器：固定高度，标签溢出时内部滚动（渐变与更名预览同款方案；小区域不放滚动条）
    private func editorScrollContainer(key: String) -> some View {
        let geom = editorScrollGeoms[key] ?? PreviewScrollGeom()
        // 版本单行居中展示；其余网格字段顶对齐
        let vAlignment: Alignment = key == "version" ? .center : .topLeading
        return ScrollView(.vertical, showsIndicators: false) {
            // 外层 VStack 保障 documentView 高度上报可靠（与更名预览同款结构；
            // LazyVGrid 直接做 ScrollView documentView 时高度上报在 SwiftUI 中不可靠，会丢失底部渐变）
            VStack(alignment: .leading, spacing: 0) {
                unifiedEditor(fieldConfig(key: key))
            }
            .frame(maxWidth: .infinity, minHeight: editorViewportHeight, alignment: vAlignment)
            .background(
                PreviewScrollObserver { g in
                    if editorScrollGeoms[key] != g {
                        editorScrollGeoms[key] = g
                    }
                }
            )
        }
        .frame(height: editorViewportHeight)
        // 顶部渐变遮罩：滚动离开顶部后浮现（与更名预览同款，遮罩色 = 卡片底合成到弹窗底的不透明等效色）
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.appleCardOnCanvas, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: editorFadeHeight)
                .allowsHitTesting(false)
                .opacity(geom.offset > 1 ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: geom.offset > 1)
        }
        // 底部渐变遮罩：下方还有未看完的内容时浮现，滚到底自动消失，与顶部对称
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Color.appleCardOnCanvas], startPoint: .top, endPoint: .bottom)
                .frame(height: editorFadeHeight)
                .allowsHitTesting(false)
                .opacity(showEditorBottomFade(geom) ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: showEditorBottomFade(geom))
        }
    }

    /// 编辑器视口固定高度（对齐“状态两行”网格）
    private let editorViewportHeight: CGFloat = 62
    /// 编辑器渐变高度：62pt 视口内 28pt 标签行，10pt 约占一行 1/3（与预览区 14pt/44pt 行同比例）
    private let editorFadeHeight: CGFloat = 10

    /// 底部渐变：下方还有未看完的内容时显示（与更名预览 showPreviewBottomFade 完全同一表达式）
    private func showEditorBottomFade(_ geom: PreviewScrollGeom) -> Bool {
        geom.contentHeight - geom.viewportHeight - geom.offset > 1
    }

    // 保留模式提示（与已关闭提示对称：名字 = 贴内容胶囊块；其他字段 = 撑满卡片宽、整体居中）
    @ViewBuilder
    private func keepHintView(_ config: BatchFieldConfig) -> some View {
        if config.key == "name" {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.orange)
                Text("保留各自原值，如需修改请在下方预览区点击对应标签")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.orange)
                Text("保留各自原值")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // 字段关闭提示（两种形态：名字 = 贴内容的灰底胶囊块，参考保留提示；其他字段 = 撑满卡片宽、整体居中）
    @ViewBuilder
    private func disabledHintView(_ config: BatchFieldConfig) -> some View {
        if config.key == "name" {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.appleMuted)
                Text("已关闭，不参与重命名")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.appleMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.appleSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.appleMuted)
                Text("已关闭，不参与重命名")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.appleMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appleSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func toggleEnabled(_ config: BatchFieldConfig) {
        if let idx = fieldConfigs.firstIndex(where: { $0.key == config.key }) {
            fieldConfigs[idx].enabled.toggle()
            saveCurrentConfig()
        }
    }

    // 胶囊式统/留切换（滑块动画）
    @ViewBuilder
    private func modeCapsule(_ config: BatchFieldConfig) -> some View {
        let isUnify = config.mode == .unify
        let capsuleWidth: CGFloat = 64
        let capsuleHeight: CGFloat = 20
        // 滑块宽度 = 半区(32) 减去两端对称内边距(2+2)，保证与选中文字严格对中、两侧留白一致
        let sliderWidth: CGFloat = capsuleWidth / 2 - 4
        // 滑块偏移：统一=2（贴左缘内边距）；保留=胶囊宽-滑块宽-内边距，镜像到右缘
        let sliderOffset: CGFloat = isUnify ? 2 : (capsuleWidth - sliderWidth - 2)

        ZStack(alignment: .topLeading) {
            // 整体胶囊背景（比 appleSurface3 更深的 appleSurface4，选中区由滑块覆盖）
            Color.appleSurface4
                .frame(width: capsuleWidth, height: capsuleHeight)
                .clipShape(Capsule())

            // 滑块（带动画）
            Capsule()
                .fill(isUnify ? Color.appleBlue : Color.orange)
                .frame(width: sliderWidth, height: capsuleHeight - 4)
                .offset(x: sliderOffset, y: 2)
                .animation(.easeInOut(duration: 0.22), value: config.mode)

            // 文字层（均分两半，与滑块对齐）
            HStack(spacing: 0) {
                Text("统一")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isUnify ? .white : Color.appleMuted)
                    .frame(width: capsuleWidth / 2, height: capsuleHeight)
                Text("保留")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(!isUnify ? .white : Color.appleMuted)
                    .frame(width: capsuleWidth / 2, height: capsuleHeight)
            }
            .allowsHitTesting(false)
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .contentShape(Capsule())
        .onTapGesture {
            if let idx = fieldConfigs.firstIndex(where: { $0.key == config.key }) {
                fieldConfigs[idx].mode = isUnify ? .keep : .unify
                // 切换模式时清除该字段的所有覆盖
                for i in 0..<overrides.count {
                    overrides[i].removeValue(forKey: config.key)
                }
                saveCurrentConfig()
            }
        }
    }

    // MARK: - 统一模式编辑器
    @ViewBuilder
    private func unifiedEditor(_ config: BatchFieldConfig) -> some View {
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
                batchCustomChannelPill(ch)
            }
            if channels.contains("其他") {
                batchChannelOtherInput
            } else {
                batchGridPill("其他", isSelected: false) {
                    toggleChannel("其他")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        customChannelFocused = true
                    }
                }
            }
            if isAddingChannel {
                batchChannelAddInput
            } else {
                batchChannelAddButton
            }
        }
        .onChange(of: channels) { _, _ in saveEditorState(for: "channel") }
    }

    // 名字编辑器
    private var nameEditor: some View {
        TextField("输入名字", text: $namePart)
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

    // MARK: - 预览区

    private var previewArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("更名预览")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                Spacer()
                if hasDuplicates {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .regular))
                        Text("检测到重名，已自动加序号")
                            .font(.system(size: 11, weight: .regular))
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // 默认 3 行 + 2 个行间距；超出后内部滚动（AppKit 通知驱动渐变与细滚动条）
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(Array(files.enumerated()), id: \.offset) { idx, _ in
                        previewRow(idx: idx)
                    }
                }
                .background(
                    PreviewScrollObserver { geom in
                        previewScrollGeom = geom
                    }
                )
            }
            .frame(height: previewListFitHeight)
            // 顶部渐变遮罩：滚动离开顶部后浮现，避免内容生硬截断
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.appleSurface2, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .allowsHitTesting(false)
                    .opacity(showPreviewTopFade ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: showPreviewTopFade)
            }
            // 底部渐变遮罩：下方还有内容时浮现，提示可滚动
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color.appleSurface2], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .allowsHitTesting(false)
                    .opacity(showPreviewBottomFade ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: showPreviewBottomFade)
            }
            // 自绘细滚动条：贴右侧边缘；仅滚动期间显示，停止 0.9s 后淡出（macOS 覆盖式滚动条行为）
            .overlay(alignment: .trailing) {
                GeometryReader { geo in
                    let trackHeight = geo.size.height - 8
                    let ratio = previewScrollGeom.viewportHeight > 0
                        ? previewScrollGeom.viewportHeight / previewScrollGeom.contentHeight
                        : 1
                    let thumbHeight = max(24, trackHeight * ratio)
                    let maxOffset = previewScrollGeom.contentHeight - previewScrollGeom.viewportHeight
                    let yOffset = maxOffset > 0
                        ? previewScrollGeom.offset / maxOffset * (trackHeight - thumbHeight)
                        : 0
                    Capsule()
                        .fill(Color.appleMuted.opacity(0.4))
                        .frame(width: 3, height: thumbHeight)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: 4 + yOffset)
                }
                .padding(.trailing, 3)
                .allowsHitTesting(false)
                .opacity(previewOverflow && scrollbarVisible ? 1 : 0)
            }
            .onChange(of: previewScrollGeom.offset) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { scrollbarVisible = true }
                scrollbarHideTask?.cancel()
                let task = DispatchWorkItem {
                    withAnimation(.easeOut(duration: 0.35)) { scrollbarVisible = false }
                }
                scrollbarHideTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: task)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func previewRow(idx: Int) -> some View {
        let suffixes = duplicateSuffixes
        let dupSuffix = idx < suffixes.count ? suffixes[idx] : nil

        VStack(alignment: .leading, spacing: 4) {
            // 第一行：序号 + 原始文件名（删除线）+ 更改后完整文件名（右对齐）
            HStack(spacing: 6) {
                Text("\(idx + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.appleMuted)
                    .frame(width: 18, height: 18)
                    .background(Color.appleSurface3)
                    .clipShape(Circle())
                Text(originalFullName(fileIdx: idx))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.appleMuted.opacity(0.6))
                    .strikethrough()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .leading)
                Spacer(minLength: 8)
                Text(fullNewName(fileIdx: idx))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.appleBlue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 第二行：新文件名标签组（左上对齐）
            HStack(spacing: 3) {
                // 先算出实际可见（有值）的字段，+ 只出现在非首个可见字段之前，避免行首孤儿 +
                let visibleKeys = fieldConfigs
                    .filter { !fieldValue(fileIdx: idx, key: $0.key).isEmpty }
                    .map(\.key)
                ForEach(Array(fieldConfigs.enumerated()), id: \.element.key) { _, config in
                    let val = fieldValue(fileIdx: idx, key: config.key)
                    // 没值的字段不显示
                    if !val.isEmpty {
                        // 分隔符：仅当前面已有可见字段时显示
                        if visibleKeys.first != config.key {
                            Text("+")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color.appleMuted.opacity(0.4))
                        }
                        // 标签或编辑框
                        if editingTag == EditingTag(fileIdx: idx, fieldKey: config.key) {
                            batchTagEditField(fileIdx: idx, fieldKey: config.key, currentVal: val)
                        } else {
                            batchTagLabel(fileIdx: idx, fieldKey: config.key, value: val)
                        }
                    }
                }
                // 重名后缀：重名组内所有文件（含第 1 个）都显示序号，样式与其他小标签同款
                if let suffix = dupSuffix {
                    Text("\(suffix)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 16, alignment: .center)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                // 扩展名
                let ext = extForFile(fileIdx: idx)
                if !ext.isEmpty {
                    Text(".\(ext)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.appleMuted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 26)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.appleCanvas)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appleDivider.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // 固定每行高度（含标题行与重名气泡所在标签行），垂直居中：行高恒定，重名不撑开窗口
        .frame(height: previewRowHeight, alignment: .center)
    }

    // 预览区标签：名字标签伸展占据中间富余空间；其他字段固定 5 字宽，长内容截断
    @ViewBuilder
    private func batchTagLabel(fileIdx: Int, fieldKey: String, value: String) -> some View {
        let displayText: String = fieldKey == "version" ? "v\(value)" : value
        let fieldConfig = fieldConfigs.first(where: { $0.key == fieldKey })
        let isUnify = fieldConfig?.mode == .unify
        Group {
            if fieldKey == "name" {
                // 名字：占据四个固定标签之外的剩余宽度，内容居中，超长截断
                Text(displayText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(isUnify ? Color.appleBlue : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .center)
                    .padding(6)
            } else {
                // 小标签：文字区固定 36pt，居中
                Text(displayText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(isUnify ? Color.appleBlue : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 36, alignment: .center)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
            }
        }
        .background(isUnify ? Color.appleBlue.opacity(0.10) : Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            editingTag = EditingTag(fileIdx: fileIdx, fieldKey: fieldKey)
        }
    }

    // 预览区标签编辑框
    @ViewBuilder
    private func batchTagEditField(fileIdx: Int, fieldKey: String, currentVal: String) -> some View {
        let binding = Binding<String>(
            get: { overrides[fileIdx][fieldKey] ?? currentVal },
            set: { newVal in
                if fileIdx < overrides.count {
                    overrides[fileIdx][fieldKey] = newVal
                }
            }
        )
        TextField(fieldKey, text: binding, onCommit: {
            editingTag = nil
        })
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(Color.appleInk)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(width: 60)
        .background(Color.appleCanvas)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.appleBlue, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .focused($batchTagFocused)
    }

    @FocusState private var batchTagFocused: Bool

    // MARK: - 重命名按钮

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
        .disabled(!canRename)
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

    // MARK: - 通用网格 Pill / 渠道子组件（批量版）

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

    // 自定义渠道标签：hover 时右上角出现删除按钮（参考单文件改名）
    @ViewBuilder
    private func batchCustomChannelPill(_ ch: String) -> some View {
        let isSelected = channels.contains(ch)
        let isHovering = hoveringChannel == ch
        ZStack(alignment: .topTrailing) {
            // 圆角背景（独立，不裁剪任何前景内容）
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.appleBlue : Color.appleSurface2)
            // 文字（撑满网格列居中，不被红叉遮挡）
            Text(ch)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : Color.appleInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 删除按钮：骑在标签右上角、向外突出（经典角标），纯淡入即时出现
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
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .offset(x: 6, y: -6)
                .buttonStyle(.plain)
                .transition(.opacity)
                .help("删除「\(ch)」")
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { toggleChannel(ch) }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveringChannel = hovering ? ch : nil
            }
        }
    }

    // “其他”输入框（撑满网格列）
    private var batchChannelOtherInput: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.appleBlue)
            TextField("输入", text: $customChannel)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .focused($customChannelFocused)
                .onChange(of: customChannel) { _, _ in saveEditorState(for: "channel") }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appleBlue, lineWidth: 1.5)
                .overlay(alignment: .trailing) {
                    Button {
                        channels.removeAll { $0 == "其他" }
                        customChannelFocused = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.appleSoft)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
        )
    }

    // “新增”输入框（撑满网格列）
    private var batchChannelAddInput: some View {
        HStack(spacing: 4) {
            TextField("输入标签名", text: $newChannelInput)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .focused($newChannelFocused)
                .onSubmit { addChannel() }
            Button {
                isAddingChannel = false
                newChannelInput = ""
                newChannelFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appleBlue, lineWidth: 1.5))
    }

    // “新增”按钮（虚线，撑满网格列）
    private var batchChannelAddButton: some View {
        Button {
            isAddingChannel = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                newChannelFocused = true
            }
        } label: {
            HStack(spacing: 3) {
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
                        .foregroundStyle(.white, Color.red.opacity(0.9))
                        .background(
                            Circle()
                                .fill(Color.appleCanvas)
                                .frame(width: 18, height: 18)
                        )
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
            withAnimation(.easeInOut(duration: 0.15)) {
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

    // MARK: - 重置

    private func resetAll() {
        fieldConfigs = [
            BatchFieldConfig(key: "date", label: "日期", mode: .keep, unifyValue: QuickRenameEngine.formatName(format: "yyMMdd"), dateFormat: "yyMMdd"),
            BatchFieldConfig(key: "channel", label: "渠道", mode: .unify, unifyValue: "线上", dateFormat: ""),
            BatchFieldConfig(key: "name", label: "名字", mode: .unify, unifyValue: "", dateFormat: ""),
            BatchFieldConfig(key: "version", label: "版本", mode: .unify, unifyValue: "1", dateFormat: ""),
            BatchFieldConfig(key: "status", label: "状态", mode: .keep, unifyValue: "草稿", dateFormat: "")
        ]
        overrides = files.map { _ in [:] }
        editingTag = nil
        channels = ["线上"]
        status = "草稿"
        namePart = ""
        versionNumber = 1
        dateFormat = "yyMMdd"
        customChannel = ""
        isAddingChannel = false
        isAddingStatus = false
        newChannelInput = ""
        newStatusInput = ""
        syncAllEditorsFromConfig()
        saveCurrentConfig()
    }

    // MARK: - 执行重命名

    private func rename() {
        guard QuickRenameEngine.tryAcquireCreateLock() else {
            AppLog.shared.log("batch rename() 被拦截：已有重命名进行中", category: "QuickRename", level: .warn)
            return
        }
        guard !files.isEmpty else {
            QuickRenameEngine.releaseCreateLock()
            return
        }

        // 保存所有字段的编辑器缓冲
        saveAllEditors()

        isRenaming = true
        let suffixes = duplicateSuffixes

        Task {
            var successCount = 0
            var lastError: String?

            for (idx, url) in files.enumerated() {
                let newName = buildNameForFile(fileIdx: idx, dupSuffix: idx < suffixes.count ? suffixes[idx] : nil)
                let ext = url.pathExtension
                let fullNewName = ext.isEmpty ? newName : "\(newName).\(ext)"

                do {
                    let directory = url.deletingLastPathComponent()
                    let targetURL = QuickRenameEngine.resolveUniqueURL(directory: directory, name: fullNewName)
                    if targetURL != url {
                        try FileManager.default.moveItem(at: url, to: targetURL)
                    }
                    successCount += 1
                    AppLog.shared.log("批量重命名 \(url.lastPathComponent) → \(targetURL.lastPathComponent)", category: "QuickRename", level: .success)
                } catch {
                    lastError = error.localizedDescription
                    AppLog.shared.log("批量重命名失败 \(url.lastPathComponent): \(error)", category: "QuickRename", level: .error)
                }
            }

            await MainActor.run {
                if successCount > 0 {
                    AppNotification.send(title: "已批量重命名", body: "成功处理 \(successCount)/\(files.count) 个文件")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        for window in NSApp.windows where window.level == .screenSaver {
                            window.close()
                        }
                        isRenaming = false
                        QuickRenameEngine.releaseCreateLock()
                    }
                } else {
                    errorMessage = lastError ?? "重命名失败"
                    showError = true
                    isRenaming = false
                    QuickRenameEngine.releaseCreateLock()
                }
            }
        }
    }
}
