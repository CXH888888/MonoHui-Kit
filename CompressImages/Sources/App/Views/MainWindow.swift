import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @Environment(AppState.self) var state
    @State private var imageItems: [ImageItem] = []
    @State private var isDropTargeted = false
    @State private var isCompressing = false
    @State private var compressionResults: [String] = []
    @State private var showFilePicker = false
    @State private var hoveredItemID: UUID?
    @State private var showQuickCompressSettings = false

    var body: some View {
        ZStack {
            if imageItems.isEmpty {
                dropZone
            } else {
                VStack(spacing: 0) {
                    thumbnailGrid
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !compressionResults.isEmpty {
                        Divider().padding(.horizontal, 20)
                        resultsList
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
                imageItems = state.preloadedURLs.map { ImageItem(url: $0) }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                imageItems = urls.map { ImageItem(url: $0) }
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
                    .padding(.horizontal, 20)
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

                Text("支持 PNG, JPEG, GIF, WebP, AVIF, JPEG XL, SVG")
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

    private func thumbnailCard(item: ImageItem) -> some View {
        let isHovered = hoveredItemID == item.id

        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let image = NSImage(contentsOf: item.url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appleSurface2)
                        .frame(width: 116, height: 116)
                        .overlay(Image(systemName: "doc.fill").foregroundStyle(Color.appleSoft))
                }

                if isHovered {
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

            Text(formatFileSize(item.fileSize))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.appleSoft)
        }
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : nil
        }
    }

    private var bottomBar: some View {
        @Bindable var bindableState = state
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("格式")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 24, alignment: .leading)
                ForEach(CompressionFormat.allCases) { fmt in
                    PillButton(
                        label: fmt.displayName,
                        isSelected: bindableState.selectedFormat.id == fmt.id,
                        action: { bindableState.selectedFormat = fmt }
                    )
                }
                Spacer(minLength: 0)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.appleSurface)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(compressionResults, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("合计") ? Color.appleInk : Color.appleSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(height: 120)
        .background(Color.appleSurface)
    }

    private func compress() {
        isCompressing = true
        compressionResults = []
        let items = imageItems

        Task {
            let engine = CompressionEngine()
            let results = await engine.compress(
                items: items,
                format: state.selectedFormat,
                quality: state.selectedQuality
            )

            await MainActor.run {
                var lines: [String] = []
                var totalIn: UInt64 = 0
                var totalOut: UInt64 = 0

                for (_, r) in results.enumerated() {
                    switch r.status {
                    case .completed(let cr):
                        totalIn += cr.inputSize
                        totalOut += cr.outputSize
                        let pct = String(format: "%.1f", abs(cr.savedPercent))
                        let arrow = cr.savedBytes >= 0 ? "↓" : "↑"
                        lines.append("\(r.fileName)  \(formatFileSize(cr.inputSize)) → \(formatFileSize(cr.outputSize))  \(arrow)\(pct)%")
                    case .failed(let err):
                        lines.append("\(r.fileName)  ✕ \(err)")
                    default:
                        break
                    }
                }

                if totalIn > 0 {
                    let totalPct = String(format: "%.1f", (1 - Double(totalOut) / Double(totalIn)) * 100)
                    lines.append("")
                    lines.append("合计: \(formatFileSize(totalIn)) → \(formatFileSize(totalOut))  ↓\(totalPct)%")
                }

                compressionResults = lines
                imageItems = results
                isCompressing = false
            }
        }
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
