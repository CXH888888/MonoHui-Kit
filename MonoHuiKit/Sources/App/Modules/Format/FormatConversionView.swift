import SwiftUI
import UniformTypeIdentifiers

struct FormatConversionView: View {
    @State private var items: [FormatItem] = []
    @State private var isDropTargeted = false
    @State private var isConverting = false
    @State private var statusMessage: String?
    @State private var statusHasFailure = false
    @State private var showFilePicker = false
    @State private var hoveredItemID: UUID?
    @State private var targetFormat: TargetFormat = .png {
        didSet { UserDefaults.standard.set(targetFormat.rawValue, forKey: "format_target") }
    }
    @State private var trimEdges: Bool = UserDefaults.standard.bool(forKey: "format_trim_edges") {
        didSet { UserDefaults.standard.set(trimEdges, forKey: "format_trim_edges") }
    }

    var body: some View {
        ZStack {
            if items.isEmpty {
                dropZone
            } else {
                VStack(spacing: 0) {
                    itemGrid
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    bottomBar
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.appleCanvas)
        .background(FormatDropTargetView(items: $items, isTargeted: $isDropTargeted, statusMessage: $statusMessage))
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: "format_target"),
               let fmt = TargetFormat(rawValue: raw) {
                targetFormat = fmt
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.image, .init(filenameExtension: "psd")!],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let newItems = urls.filter { ImageItem.isSupportedImage($0) }.map { FormatItem(url: $0) }
                if !newItems.isEmpty {
                    // 换新批次，清掉上一轮的状态提示
                    items = newItems
                    statusMessage = nil
                }
            }
        }
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

            Text("支持 PSD, PNG, JPEG, TIFF, GIF, WebP 等")
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

    private var itemGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    itemCard(item: item)
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

                // 占位行：与文件卡片的文件名/状态两行同字体同间距，保证网格行内顶部对齐
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

    private func itemCard(item: FormatItem) -> some View {
        let isHovered = hoveredItemID == item.id

        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: item.url, size: 116, cornerRadius: 12)

                if isHovered {
                    Button(action: { items.removeAll { $0.id == item.id } }) {
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

            Text(statusLabel(for: item, size: item.fileSize))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor(for: item))
        }
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : nil
        }
    }

    private func statusLabel(for item: FormatItem, size: UInt64) -> String {
        switch item.status {
        case .pending:
            return formatFileSize(size)
        case .converting:
            return "转换中…"
        case .completed:
            return formatFileSize(size)
        case .failed:
            return "失败"
        }
    }

    private func statusColor(for item: FormatItem) -> Color {
        switch item.status {
        case .failed:
            return Color.red
        default:
            return Color.appleSoft
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusHasFailure ? Color.red : Color.appleSuccess)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                Text("转为")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 24, alignment: .leading)
                ForEach(TargetFormat.allCases) { fmt in
                    PillButton(
                        label: fmt.displayName,
                        isSelected: targetFormat == fmt,
                        action: { targetFormat = fmt }
                    )
                }
                Spacer(minLength: 0)

                Toggle("裁剪空白", isOn: $trimEdges)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12, weight: .regular))

                Button(action: convert) {
                    HStack(spacing: 6) {
                        if isConverting {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        Text("转换 \(items.count) 个文件")
                            .font(.system(size: 15, weight: .regular))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 40)
                    .background(isConverting ? Color.appleBlue.opacity(0.7) : Color.appleBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 980))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isConverting || items.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.appleSurface)
    }

    private func convert() {
        isConverting = true
        statusMessage = nil
        let currentItems = items

        Task {
            let engine = FormatConversionEngine()
            let converted = await engine.convert(items: currentItems, target: targetFormat, trimEdges: trimEdges)
            await MainActor.run {
                let successCount = converted.filter {
                    if case .completed = $0.status { return true }
                    return false
                }.count
                let failedCount = converted.count - successCount
                if failedCount == 0 {
                    statusMessage = "转换成功（\(successCount) 个文件）"
                    statusHasFailure = false
                } else if successCount > 0 {
                    statusMessage = "转换完成：成功 \(successCount) · 失败 \(failedCount)"
                    statusHasFailure = true
                } else {
                    statusMessage = "转换失败"
                    statusHasFailure = true
                }
                items = converted
                isConverting = false
            }
        }
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// 接受文件拖入（含 PSD），写入 FormatItem 列表。
private struct FormatDropTargetView: NSViewRepresentable {
    @Binding var items: [FormatItem]
    @Binding var isTargeted: Bool
    @Binding var statusMessage: String?

    func makeNSView(context: Context) -> NSView {
        let view = FormatDropTargetNSView()
        view.items = $items
        view.isTargeted = $isTargeted
        view.statusMessage = $statusMessage
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {}
}

private class FormatDropTargetNSView: NSView {
    var items: Binding<[FormatItem]>?
    var isTargeted: Binding<Bool>?
    var statusMessage: Binding<String?>?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted?.wrappedValue = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted?.wrappedValue = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted?.wrappedValue = false
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return false }
        let newItems = urls.filter { ImageItem.isSupportedImage($0) }.map { FormatItem(url: $0) }
        guard !newItems.isEmpty else { return true }

        let hasCompleted = (items?.wrappedValue ?? []).contains { item in
            if case .completed = item.status { return true }
            return false
        }
        if hasCompleted {
            // 上一批已转换成功：拖入视为开启新批次，清空旧文件与状态提示
            items?.wrappedValue = newItems
            statusMessage?.wrappedValue = nil
        } else {
            // 未转换时追加并按路径去重（与压缩窗口行为一致）
            let existing = Set(items?.wrappedValue.map { $0.url.path } ?? [])
            for item in newItems where !existing.contains(item.url.path) {
                items?.wrappedValue.append(item)
            }
        }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isTargeted?.wrappedValue = false
    }
}