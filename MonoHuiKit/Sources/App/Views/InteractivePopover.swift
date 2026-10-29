import SwiftUI

struct InteractivePopover: View {
    @Environment(AppState.self) var state
    @State private var imageItems: [ImageItem] = []
    @State private var isCompressing = false
    @State private var showResult = false
    @State private var progress: CompressionProgress?
    @State private var report: CompressionReport?
    @State private var workTask: Task<Void, Never>?

    private let panelHeight: CGFloat = 470

    var body: some View {
        VStack(spacing: 14) {
            headerArea
            Divider().padding(.horizontal, -24)
            pillPickers
            if isCompressing { progressRow }
            if let report, report.failedCount > 0 { failureArea(report) }
            Spacer(minLength: 0)
            compressButton
        }
        .padding(24)
        .frame(width: 580, height: panelHeight)
        .background(Color.appleCanvas)
        .onAppear {
            if !state.preloadedURLs.isEmpty {
                let urls = state.preloadedURLs.filter { ImageItem.isSupportedImage($0) }
                imageItems = urls.map { ImageItem(url: $0) }
            }
            AppLog.shared.log("压缩弹窗 onAppear preloadedURLs=\(state.preloadedURLs.count) imageItems=\(imageItems.count)", category: "Dispatcher")
            DispatchQueue.main.async {
                guard let window = HotKeyDispatcher.popupWindow else { return }
                window.setContentSize(NSSize(width: 580 + 2 * Motion.popupShadowInset,
                                             height: panelHeight + 2 * Motion.popupShadowInset))
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
        VStack(spacing: 8) {
            HStack {
                Text("压缩参数")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.appleInk)
                Spacer()
                if imageItems.count > 0 {
                    Text("\(imageItems.count) 个文件")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                }
                PopoverCloseButton()
            }

            if !imageItems.isEmpty {
                let previewItems = Array(imageItems.prefix(8))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(previewItems) { item in
                            ThumbnailView(url: item.url, size: 48, cornerRadius: 10)
                        }
                        if imageItems.count > 8 {
                            Text("+\(imageItems.count - 8)")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.appleSoft)
                                .frame(width: 48, height: 48)
                                .background(Color.appleSurface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } else {
                Text("未检测到图片")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
                    .frame(height: 48)
            }
        }
    }

    private var pillPickers: some View {
        @Bindable var bindableState = state
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("格式")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
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
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("质量")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
                ForEach(QualityLevel.allCases) { ql in
                    PillButton(
                        label: ql.displayName,
                        isSelected: bindableState.selectedQuality.id == ql.id,
                        action: { bindableState.selectedQuality = ql }
                    )
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text("")
                    .frame(width: 28)
                PillButton(
                    label: state.keepOriginalFormat ? "✓ 保持原格式" : "保持原格式",
                    isSelected: state.keepOriginalFormat,
                    action: { bindableState.keepOriginalFormat.toggle() }
                )
                Text("按每个文件自身格式压缩，不转换")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleMuted)
                Spacer(minLength: 0)
            }
        }
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

    private func failureArea(_ report: CompressionReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                Text("\(report.failedCount) 个文件失败")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appleInk)
                Spacer()
                Button("查看全部") {
                    CompressionResultWindowController.shared.show(report: report)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.appleBlue)
            }

            ForEach(report.failures.prefix(3)) { failure in
                HStack(alignment: .top, spacing: 6) {
                    Text(failure.fileName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 170, alignment: .leading)
                    Text(failure.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if report.failedCount > 3 {
                Text("另有 \(report.failedCount - 3) 个失败…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appleMuted)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var compressButton: some View {
        Button(action: compress) {
            HStack(spacing: 8) {
                if isCompressing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isCompressing ? "压缩中…" : (showResult ? "完成" : "开始压缩"))
                    .font(.system(size: 17, weight: .regular))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isCompressing ? Color.appleBlue.opacity(0.7) : (showResult ? Color.appleSuccess : Color.appleBlue))
            .clipShape(RoundedRectangle(cornerRadius: 980))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(isCompressing || imageItems.isEmpty || showResult)
    }

    private func compress() {
        // 用 NSLock 保证原子性，防止 onSubmit + keyboardShortcut 同时触发 compress()
        guard CompressionEngine.tryAcquireCompressLock() else {
            AppLog.shared.log("compress() 被拦截：已有压缩进行中", category: "Dispatcher", level: .warn)
            return
        }
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
                let result = outcome.report
                self.report = result
                self.progress = nil
                self.isCompressing = false
                AppLog.shared.log("压缩弹窗完成 \(result.summaryLine)", category: "Dispatcher",
                                  level: result.failedCount > 0 ? .warn : .success)
                if result.failedCount > 0 { result.writeToDisk() }

                if result.failedCount == 0 && result.succeeded > 0 {
                    // 全部成功：标记完成并自动关闭
                    showResult = true
                    AppNotification.send(title: "压缩完成", body: "\(result.succeeded) 个文件已压缩")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        AppLog.shared.log("压缩弹窗完成，关闭窗口", category: "Dispatcher")
                        for window in NSApp.windows where window.level == .screenSaver {
                            window.close()
                        }
                        isCompressing = false
                        CompressionEngine.releaseCompressLock()
                    }
                } else {
                    // 有失败（或全部失败）：保留窗口展示失败清单，释放锁允许重试
                    showResult = false
                    AppNotification.send(
                        title: "压缩完成，有文件失败",
                        body: result.notificationBody
                    )
                    CompressionEngine.releaseCompressLock()
                }
            }
        }
    }
}
