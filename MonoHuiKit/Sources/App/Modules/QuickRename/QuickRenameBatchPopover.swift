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

struct PreviewRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - 批量重命名弹窗
struct QuickRenameBatchPopover: View {
    @Environment(AppState.self) var state

    // 解析后的文件列表
    @State var files: [URL] = []

    // 字段配置
    @State var fieldConfigs: [BatchFieldConfig] = []

    // 每个文件每个字段的手动覆盖
    @State var overrides: [[String: String]] = []

    // 预览区正在编辑的标签
    @State var editingTag: EditingTag?

    // 自定义渠道和状态（与单文件改名共享）
    @AppStorage("datefolder_custom_channels_json") var customChannelsJSON: String = "[]"
    @AppStorage("quickrename_custom_statuses_json") var customStatusesJSON: String = "[]"

    // 渠道编辑状态（可多选，命名时用 - 连接）
    @State var channels: [String] = ["线上"]
    @State var customChannel: String = ""
    @State var isAddingChannel = false
    @State var newChannelInput = ""
    @State var hoveringChannel: String? = nil
    /// 弹窗唤起时自动聚焦名称输入框
    @FocusState var nameFocused: Bool
    @FocusState var newChannelFocused: Bool
    @FocusState var customChannelFocused: Bool

    // 状态编辑状态
    @State var status: String = "草稿"
    @State var isAddingStatus = false
    @State var newStatusInput = ""
    @State var hoveringStatus: String? = nil
    @FocusState var newStatusFocused: Bool

    // 名字
    @State var namePart: String = ""

    // 版本
    @State var versionNumber: Int = 1

    // 日期
    @State var dateFormat: String = "yyMMdd"

    // 重命名状态
    @State private var isRenaming = false
    @State private var showError = false
    @State private var errorMessage = ""

    // 预览区滚动状态（默认 3 行，超出滚动 + 顶/底渐变遮罩）
    // 更名预览每行固定高度：重名加序号标签等不再改变行高，整个窗口高度稳定不撑开
    let previewRowHeight: CGFloat = 60
    @State var previewScrollGeom = ScrollEdgeGeom()
    // 细滚动条：仅滚动期间显示，停止 0.9s 后淡出
    @State var scrollbarVisible = false
    @State var scrollbarHideTask: DispatchWorkItem?

    // 字段编辑器滚动状态（渠道/状态等网格编辑器内部滚动），key = 字段 key
    @State private var editorScrollGeoms: [String: ScrollEdgeGeom] = [:]

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

    let dateFormats: [(label: String, format: String)] = [
        ("月日", "MMdd"),
        ("年月", "yyMM"),
        ("年月日", "yyMMdd")
    ]

    // MARK: - 数据计算

    var customChannels: [String] {
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

    func toggleChannel(_ ch: String) {
        if let index = channels.firstIndex(of: ch) {
            channels.remove(at: index)
        } else {
            channels.append(ch)
        }
    }

    var customStatuses: [String] {
        guard let data = customStatusesJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    var allStatuses: [String] {
        QuickRenameEngine.defaultStatuses + customStatuses
    }

    /// 获取某文件某字段的最终值
    func fieldValue(fileIdx: Int, key: String) -> String {
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
    func extForFile(fileIdx: Int) -> String {
        guard fileIdx < files.count else { return "" }
        return files[fileIdx].pathExtension
    }

    /// 获取某文件的原始完整文件名
    func originalFullName(fileIdx: Int) -> String {
        guard fileIdx < files.count else { return "" }
        return files[fileIdx].lastPathComponent
    }

    /// 预览区右对齐展示的更改后完整文件名（含重名后缀与扩展名）
    func fullNewName(fileIdx: Int) -> String {
        let suffixes = duplicateSuffixes
        let dupSuffix = fileIdx < suffixes.count ? suffixes[fileIdx] : nil
        let newName = buildNameForFile(fileIdx: fileIdx, dupSuffix: dupSuffix)
        let ext = extForFile(fileIdx: fileIdx)
        return ext.isEmpty ? newName : "\(newName).\(ext)"
    }

    /// 检测重名并返回每个文件的序号后缀
    var duplicateSuffixes: [Int?] {
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

    var hasDuplicates: Bool {
        duplicateSuffixes.contains { $0 != nil }
    }

    // MARK: - 预览区滚动计算

    /// 预览列表最大高度 = 3 行 + 2 个行间距（行高运行时测量）
    private var previewListMaxHeight: CGFloat {
        previewRowHeight * 3 + 6 * 2
    }

    /// 列表实际高度：内容不足 3 行时按内容高度收缩，超出封顶 3 行（此时可滚动）
    var previewListFitHeight: CGFloat {
        previewScrollGeom.contentLength > 0
            ? min(previewScrollGeom.contentLength, previewListMaxHeight)
            : previewListMaxHeight
    }

    /// 顶部渐变：已向下滚动（离开顶部）时显示
    var showPreviewTopFade: Bool {
        previewScrollGeom.offset > 1
    }

    /// 底部渐变：下方还有未看完的内容时显示
    var showPreviewBottomFade: Bool {
        previewScrollGeom.contentLength - previewScrollGeom.viewportLength - previewScrollGeom.offset > 1
    }

    /// 内容是否溢出视口（决定是否显示细滚动条）
    var previewOverflow: Bool {
        previewScrollGeom.contentLength > previewScrollGeom.viewportLength + 1
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
        .background(Color.applePopupCanvas)
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
        HotKeyDispatcher.calibratePopupWindow(width: 560, minHeight: 500, maxHeight: 1200)

        // 唤起即聚焦名称输入框，省掉一次点击
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            nameFocused = true
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
    func saveEditorState(for key: String) {
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

    func saveCurrentConfig() {
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
            Spacer()
            PopoverCloseButton()
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
        let geom = editorScrollGeoms[key] ?? ScrollEdgeGeom()
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
                ScrollEdgeObserver(axis: .vertical) { g in
                    if editorScrollGeoms[key] != g {
                        editorScrollGeoms[key] = g
                    }
                }
            )
        }
        .frame(height: editorViewportHeight)
        // 顶/底渐变：滚动离开边界后淡出内容（与状态卡片、更名预览同款 mask 方案）
        .scrollEdgeFade(top: geom.offset > 1, bottom: showEditorBottomFade(geom),
                        length: editorFadeHeight)
    }

    /// 编辑器视口固定高度（对齐“状态两行”网格）
    private let editorViewportHeight: CGFloat = 62
    /// 编辑器渐变高度：62pt 视口内 28pt 标签行，10pt 约占一行 1/3（与预览区 14pt/44pt 行同比例）
    private let editorFadeHeight: CGFloat = 10

    /// 底部渐变：下方还有未看完的内容时显示（与更名预览 showPreviewBottomFade 完全同一表达式）
    private func showEditorBottomFade(_ geom: ScrollEdgeGeom) -> Bool {
        geom.contentLength - geom.viewportLength - geom.offset > 1
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
                .animation(Motion.move, value: config.mode)

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

    @FocusState var batchTagFocused: Bool

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
