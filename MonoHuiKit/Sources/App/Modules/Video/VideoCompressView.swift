import SwiftUI
import UniformTypeIdentifiers

struct VideoCompressView: View {
    @Environment(AppState.self) var state

    @State private var items: [VideoItem] = []
    @State private var isDropTargeted = false
    @State private var isCompressing = false
    @State private var progress: CompressionProgress?
    @State private var report: CompressionReport?
    @State private var showFilePicker = false
    @State private var hoveredItemID: UUID?
    @State private var workTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("视频压缩")
                .padding(.top, 20)
                .padding(.horizontal, 20)

            ZStack {
                if items.isEmpty {
                    dropZone
                } else {
                    VStack(spacing: 0) {
                        list
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let report {
                            Divider()
                            summaryBar(report)
                        }
                        Divider()
                        bottomBar
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appleCanvas)
        .background(VideoDropTargetView(items: $items, isTargeted: $isDropTargeted))
        .onAppear {
            if !state.preloadedURLs.isEmpty {
                let urls = state.preloadedURLs.filter { VideoItem.isSupportedVideo($0) }
                if !urls.isEmpty { items = urls.map { VideoItem(url: $0) } }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                items = urls.map { VideoItem(url: $0) }
                report = nil
            }
        }
    }

    // MARK: - 空状态

    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 36))
                .foregroundStyle(isDropTargeted ? Color.appleBlue : Color.appleSoft)

            VStack(spacing: 8) {
                Text("拖拽视频到这里")
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

            Text("支持 MP4, MOV, M4V, 3GP, TS")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.appleMuted)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isDropTargeted ? Color.appleBlue : Color.appleDropBorder,
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 0.5, dash: [8]))
                .padding(20)
        )
    }

    // MARK: - 列表

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(items) { item in
                    videoRow(item)
                }
                addRow
            }
            .padding(24)
        }
    }

    private var addRow: some View {
        Button { showFilePicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("添加视频")
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.appleSoft)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.appleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func videoRow(_ item: VideoItem) -> some View {
        let isHovered = hoveredItemID == item.id
        return HStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 18))
                .foregroundStyle(Color.appleSoft)
                .frame(width: 44, height: 44)
                .background(Color.appleSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleInk)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(formatFileSize(item.fileSize))
                    if !item.durationText.isEmpty { Text(item.durationText) }
                    if !item.resolutionText.isEmpty { Text(item.resolutionText) }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.appleSoft)
            }

            Spacer(minLength: 8)

            statusLabel(item)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor(item))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .trailing)

            if isHovered && !isCompressing {
                Button {
                    items.removeAll { $0.id == item.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(Color.appleSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appleDivider, lineWidth: 1)
        )
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : nil
        }
    }

    private func statusLabel(_ item: VideoItem) -> Text {
        switch item.status {
        case .pending:
            return Text("")
        case .compressing:
            return Text("压缩中…")
        case .completed(let result):
            let pct = String(format: "%.0f", abs(result.savedPercent))
            let arrow = result.savedBytes >= 0 ? "↓" : "↑"
            return Text("\(formatFileSize(result.inputSize)) → \(formatFileSize(result.outputSize))  \(arrow)\(pct)%")
        case .failed(let reason):
            return Text(reason)
        case .skipped(let reason):
            return Text(reason)
        }
    }

    private func statusColor(_ item: VideoItem) -> Color {
        switch item.status {
        case .failed: return Color.red
        case .skipped: return Color.appleMuted
        case .completed: return Color.appleSuccess
        default: return Color.appleSoft
        }
    }

    // MARK: - 汇总

    private func summaryBar(_ report: CompressionReport) -> some View {
        HStack(spacing: 8) {
            Text(report.summaryLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(report.failedCount > 0 ? Color.orange : Color.appleSuccess)
            Text("· 耗时 \(report.elapsedText)")
                .font(.system(size: 12))
                .foregroundStyle(Color.appleSoft)
            Spacer()
            if report.hasIssues {
                Button(report.failedCount > 0 ? "查看失败明细" : "查看跳过明细") {
                    CompressionResultWindowController.shared.show(report: report)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.appleBlue)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.appleSurface)
    }

    // MARK: - 底部参数区

    /// 参数区：质量 / 分辨率 / 编码 三行 + 操作行。
    /// 编码原来挤在「分辨率」行右端、没有标签，看不出是编码器，这里独立成行。
    private var bottomBar: some View {
        @Bindable var bindableState = state
        return VStack(spacing: ParamLayout.rowGap) {
            if isCompressing {
                progressRow
            }

            ParamRow("质量") {
                ForEach(VideoQuality.allCases) { q in
                    PillButton(label: q.displayName,
                               isSelected: bindableState.videoQuality == q,
                               action: { bindableState.videoQuality = q })
                }
            }

            ParamRow("分辨率") {
                ForEach(VideoResolution.allCases) { r in
                    PillButton(label: r.displayName,
                               isSelected: bindableState.videoResolution == r,
                               action: { bindableState.videoResolution = r })
                }
            }

            ParamRow("编码") {
                ForEach(VideoCodec.allCases) { c in
                    PillButton(label: c.displayName,
                               isSelected: bindableState.videoCodec == c,
                               action: { bindableState.videoCodec = c })
                }
            }

            PrimaryActionBar(
                title: "压缩 \(items.count) 个视频",
                isBusy: isCompressing,
                isEnabled: !items.isEmpty,
                onCancel: { workTask?.cancel() },
                action: compress
            ) {
                Text(state.videoCodec.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleMuted)
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
                Text("\(progress?.completed ?? 0)/\(items.count)")
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
        progress = CompressionProgress(completed: 0, total: items.count, currentFileName: "")

        let snapshot = items
        let quality = state.videoQuality
        let resolution = state.videoResolution
        let codec = state.videoCodec
        let engine = VideoCompressionEngine()

        workTask = Task {
            let outcome = await engine.compress(
                items: snapshot,
                quality: quality,
                resolution: resolution,
                codec: codec,
                onProgress: { p in
                    Task { @MainActor in
                        self.progress = p
                    }
                }
            )
            await MainActor.run {
                self.items = outcome.items
                self.report = outcome.report
                self.isCompressing = false
                self.progress = nil
                self.workTask = nil
                AppNotification.send(
                    title: outcome.report.failedCount > 0 ? "视频压缩完成，有文件失败" : "视频压缩完成",
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

// MARK: - 拖拽

private struct VideoDropTargetView: NSViewRepresentable {
    @Binding var items: [VideoItem]
    @Binding var isTargeted: Bool

    func makeNSView(context: Context) -> NSView {
        let view = VideoDropTargetNSView()
        view.items = $items
        view.isTargeted = $isTargeted
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject {}
}

private class VideoDropTargetNSView: NSView {
    var items: Binding<[VideoItem]>?
    var isTargeted: Binding<Bool>?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted?.wrappedValue = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted?.wrappedValue = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted?.wrappedValue = false
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return false }
        let videos = urls.filter { VideoItem.isSupportedVideo($0) }
        let existing = Set(items?.wrappedValue.map { $0.url.path } ?? [])
        for url in videos where !existing.contains(url.path) {
            items?.wrappedValue.append(VideoItem(url: url))
        }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isTargeted?.wrappedValue = false
    }
}
