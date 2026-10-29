import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @Environment(AppState.self) var state
    @State private var imageItems: [ImageItem] = []
    @State private var isDropTargeted = false
    @State private var isCompressing = false
    @State private var progress: CompressionProgress?
    @State private var report: CompressionReport?
    @State private var showFilePicker = false
    @State private var hoveredItemID: UUID?
    @State private var showQuickCompressSettings = false
    @State private var workTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if imageItems.isEmpty {
                dropZone
            } else {
                VStack(spacing: 0) {
                    thumbnailGrid
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let report {
                        Divider()
                        resultsPanel(report)
                    }

                    Divider()
                    bottomBar
                }
            }

            // 右上角快速压缩设置按钮
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showQuickCompressSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.appleSoft)
                            .frame(width: 28, height: 28)
                            .background(Color.appleSurface2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("快速压缩设置")
                }
                .padding([.top, .trailing], 20)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.appleCanvas)
        .background(DropTargetView(imageItems: $imageItems, isTargeted: $isDropTargeted))
        .onAppear {
            if !state.preloadedURLs.isEmpty {
                let urls = state.preloadedURLs.filter { ImageItem.isSupportedImage($0) }
                if !urls.isEmpty { imageItems = urls.map { ImageItem(url: $0) } }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                imageItems = urls.map { ImageItem(url: $0) }
                report = nil
            }
        }
        .sheet(isPresented: $showQuickCompressSettings) {
            quickCompressSettingsSheet
        }
    }

    // 快速压缩设置弹窗（右键"图片·快速压缩"时使用的默认档位）
    private var quickCompressSettingsSheet: some View {
        @Bindable var bindableState = state
        return VStack(alignment: .leading, spacing: 16) {
            Text("快速压缩设置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            Text("以下参数用于 Finder 右键菜单中的「图片·快速压缩」")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleSoft)

            VStack(alignment: .leading, spacing: 8) {
                Text("默认压缩档位")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                HStack(spacing: 6) {
                    ForEach(QualityLevel.allCases) { ql in
                        PillButton(
                            label: ql.displayName,
                            isSelected: bindableState.quickQuality.id == ql.id,
                            action: { bindableState.quickQuality = ql }
                        )
                    }
                }
            }

            Toggle("保持原格式（不转换）", isOn: $bindableState.quickKeepOriginal)
                .font(.system(size: 13, weight: .regular))

            if !bindableState.quickKeepOriginal {
                VStack(alignment: .leading, spacing: 8) {
                    Text("默认转换格式")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appleSoft)
                    HStack(spacing: 6) {
                        ForEach(CompressionFormat.allCases) { fmt in
                            PillButton(
                                label: fmt.displayName,
                                isSelected: bindableState.quickFormat.id == fmt.id,
                                action: { bindableState.quickFormat = fmt }
                            )
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("完成") { showQuickCompressSettings = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 32)
                    .background(Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 36))
                .foregroundStyle(isDropTargeted ? Color.appleBlue : Color.appleSoft)

            VStack(spacing: 8) {
                Text("拖拽图片到这里")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.appleInk)

                Text("或")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.appleSoft)

                Button("选择文件") { showFilePicker = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 40)
                    .background(Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
                    .contentShape(Rectangle())
            }

            Text("支持 PNG, JPEG, GIF, WebP, AVIF, JPEG XL, SVG, HEIC, TIFF")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.appleMuted)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isDropTargeted ? Color.appleBlue : Color.black.opacity(0.1),
                        style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(16)
        )
    }

    private var thumbnailGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
                ForEach(imageItems) { item in
                    thumbnailCard(item: item)
                }
                addButton
            }
            .padding(24)
        }
    }

    private var addButton: some View {
        Button {
            showFilePicker = true
        } label: {
            VStack(spacing: 6) {
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                    Text("添加")
                        .font(.system(size: 13, weight: .regular))
                }
                .foregroundStyle(Color.appleSoft)
                .frame(width: 116, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.appleBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .contentShape(Rectangle())

                // 占位行：与缩略卡片的文件名/大小两行同字体同间距，保证网格行内顶部对齐
                Text(" ")
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .frame(width: 116)
                Text(" ")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(.plain)
    }

    private func thumbnailCard(item: ImageItem) -> some View {
        let isHovered = hoveredItemID == item.id

        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: item.url, size: 116, cornerRadius: 12)

                if isHovered && !isCompressing {
                    Button(action: { imageItems.removeAll { $0.id == item.id } }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.44))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }

            Text(item.fileName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 116)

            Text(cardSubtitle(item))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(cardSubtitleColor(item))
                .lineLimit(1)
                .frame(width: 116)
        }
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : nil
        }
    }

    private func cardSubtitle(_ item: ImageItem) -> String {
        switch item.status {
        case .completed(let result):
            return "\(formatFileSize(result.outputSize))  ↓\(String(format: "%.0f", abs(result.savedPercent)))%"
        case .failed:
            return "失败"
        case .skipped:
            return "已跳过"
        case .compressing:
            return "压缩中…"
        case .pending:
            return formatFileSize(item.fileSize)
        }
    }

    private func cardSubtitleColor(_ item: ImageItem) -> Color {
        switch item.status {
        case .failed: return Color.red
        case .completed: return Color.appleSuccess
        case .skipped: return Color.appleMuted
        default: return Color.appleSoft
        }
    }

    // MARK: - 结果面板

    private func resultsPanel(_ report: CompressionReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: report.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(report.failedCount > 0 ? Color.orange : Color.appleSuccess)
                Text(report.summaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Text("· \(report.elapsedText)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleSoft)
                Spacer()

                if report.failedCount > 0 {
                    Button("复制清单") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.plainText(), forType: .string)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleBlue)

                    Button("定位失败文件") {
                        let urls = report.failures.map { URL(fileURLWithPath: $0.path) }
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleBlue)

                    Button("完整报告") {
                        CompressionResultWindowController.shared.show(report: report)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleBlue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if report.failures.isEmpty {
                Text("全部文件压缩成功")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleSoft)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(report.failures) { failure in
                            HStack(alignment: .top, spacing: 8) {
                                Text(failure.fileName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.appleInk)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 180, alignment: .leading)
                                Text(failure.reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.red.opacity(0.85))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(height: 84)
            }
        }
        .background(Color.appleSurface)
    }

    // MARK: - 底部参数区

    private var bottomBar: some View {
        @Bindable var bindableState = state
        return VStack(spacing: 10) {
            if isCompressing {
                progressRow
            }

            HStack(spacing: 8) {
                Text("格式")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 24, alignment: .leading)
                ForEach(CompressionFormat.allCases) { fmt in
                    PillButton(
                        label: fmt.displayName,
                        isSelected: bindableState.selectedFormat.id == fmt.id && !state.keepOriginalFormat,
                        action: {
                            // 点格式＝明确要转换，自动退出「保持原格式」
                            bindableState.keepOriginalFormat = false
                            bindableState.selectedFormat = fmt
                        }
                    )
                }
                .opacity(state.keepOriginalFormat ? 0.45 : 1)

                Spacer(minLength: 8)

                PillButton(
                    label: state.keepOriginalFormat ? "✓ 保持原格式" : "保持原格式",
                    isSelected: state.keepOriginalFormat,
                    action: { bindableState.keepOriginalFormat.toggle() }
                )
                .help("按每个文件自身的格式压缩，不做格式转换（HEIC 用系统编码器）")
            }

            HStack(spacing: 8) {
                Text("质量")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 24, alignment: .leading)
                ForEach(QualityLevel.allCases) { ql in
                    PillButton(
                        label: ql.displayName,
                        isSelected: bindableState.selectedQuality.id == ql.id,
                        action: { bindableState.selectedQuality = ql }
                    )
                }
                Spacer(minLength: 0)

                if isCompressing {
                    Button("取消") { workTask?.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appleSoft)
                }

                Button(action: compress) {
                    HStack(spacing: 6) {
                        if isCompressing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        Text("压缩 \(imageItems.count) 个文件")
                            .font(.system(size: 15, weight: .regular))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 40)
                    .background(isCompressing ? Color.appleBlue.opacity(0.7) : Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCompressing || imageItems.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.appleSurface)
    }

    private var progressRow: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appleSurface3)
                    Capsule()
                        .fill(Color.appleBlue)
                        .frame(width: max(0, geo.size.width * (progress?.fraction ?? 0)))
                        .animation(Motion.progress, value: progress?.fraction ?? 0)
                }
            }
            .frame(height: 4)

            HStack {
                Text(progress?.currentFileName ?? "准备中…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(progress?.completed ?? 0)/\(imageItems.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.appleSoft)
            }
        }
    }

    // MARK: - 执行

    private func compress() {
        guard !isCompressing else { return }
        isCompressing = true
        report = nil
        progress = CompressionProgress(completed: 0, total: imageItems.count, currentFileName: "")

        let items = imageItems
        let format = state.selectedFormat
        let quality = state.selectedQuality
        let keepOriginal = state.keepOriginalFormat
        let engine = CompressionEngine()

        workTask = Task {
            let outcome = await engine.compress(
                items: items,
                format: format,
                quality: quality,
                keepOriginal: keepOriginal,
                onProgress: { p in
                    Task { @MainActor in
                        self.progress = p
                    }
                }
            )

            await MainActor.run {
                self.imageItems = outcome.items
                self.report = outcome.report
                self.isCompressing = false
                self.progress = nil
                self.workTask = nil
                if outcome.report.failedCount > 0 { outcome.report.writeToDisk() }
                AppNotification.send(
                    title: outcome.report.failedCount > 0 ? "压缩完成，有文件失败" : "压缩完成",
                    body: outcome.report.notificationBody
                )
            }
        }
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
