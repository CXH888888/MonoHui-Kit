import SwiftUI
import UniformTypeIdentifiers

struct FormatConversionView: View {
    @State private var items: [FormatItem] = []
    @State private var isDropTargeted = false
    @State private var isConverting = false
    @State private var results: [String] = []
    @State private var showFilePicker = false
    @State private var hoveredItemID: UUID?
    @State private var targetFormat: TargetFormat = .png {
        didSet { UserDefaults.standard.set(targetFormat.rawValue, forKey: "format_target") }
    }

    var body: some View {
        ZStack {
            if items.isEmpty {
                dropZone
            } else {
                VStack(spacing: 0) {
                    itemGrid
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !results.isEmpty {
                        Divider().padding(.horizontal, 20)
                        resultsList
                    }

                    Divider()
                    bottomBar
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.appleCanvas)
        .background(FormatDropTargetView(items: $items, isTargeted: $isDropTargeted))
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
                items = urls.map { FormatItem(url: $0) }
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
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                Text("添加")
                    .font(.system(size: 13, weight: .regular))
            }
            .foregroundStyle(Color.appleSoft)
            .frame(width: 116, height: 116)
            .background(Color.appleSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.appleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func itemCard(item: FormatItem) -> some View {
        let isHovered = hoveredItemID == item.id

        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let image = NSImage(contentsOf: item.url) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(Color.appleSoft)
                    }
                }
                .frame(width: 116, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 12))

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
        case .completed(let url):
            return "→ \(url.lastPathComponent)"
        case .failed:
            return "失败"
        }
    }

    private func statusColor(for item: FormatItem) -> Color {
        switch item.status {
        case .failed:
            return Color.red
        case .completed:
            return Color.appleSuccess
        default:
            return Color.appleSoft
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
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

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(results, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.appleSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(height: 120)
        .background(Color.appleSurface)
    }

    private func convert() {
        isConverting = true
        results = []
        let currentItems = items

        Task {
            let engine = FormatConversionEngine()
            let converted = await engine.convert(items: currentItems, target: targetFormat)
            await MainActor.run {
                var lines: [String] = []
                var successCount = 0
                for item in converted {
                    switch item.status {
                    case .completed(let url):
                        successCount += 1
                        lines.append("\(item.fileName)  →  \(url.lastPathComponent)")
                    case .failed(let err):
                        lines.append("\(item.fileName)  ✕ \(err)")
                    default:
                        break
                    }
                }
                if successCount > 0 {
                    lines.append("")
                    lines.append("合计: 成功 \(successCount) / \(converted.count)")
                }
                results = lines
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

    func makeNSView(context: Context) -> NSView {
        let view = FormatDropTargetNSView()
        view.items = $items
        view.isTargeted = $isTargeted
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
        // 每次拖入替换旧列表（与「选择文件」一致）
        items?.wrappedValue = urls.map { FormatItem(url: $0) }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isTargeted?.wrappedValue = false
    }
}