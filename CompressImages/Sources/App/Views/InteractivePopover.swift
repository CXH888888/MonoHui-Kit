import SwiftUI

struct InteractivePopover: View {
    @Environment(AppState.self) var state
    @State private var imageItems: [ImageItem] = []
    @State private var isCompressing = false
    @State private var showResult = false

    var body: some View {
        VStack(spacing: 16) {
            headerArea
            Divider().padding(.horizontal, -24)
            pillPickers
            Spacer()
            compressButton
        }
        .padding(24)
        .frame(width: 580, height: 420)
        .background(Color.appleCanvas)
        .onAppear {
            if !state.preloadedURLs.isEmpty {
                imageItems = state.preloadedURLs.map { ImageItem(url: $0) }
            }
            AppLog.shared.log("压缩弹窗 onAppear preloadedURLs=\(state.preloadedURLs.count) imageItems=\(imageItems.count)", category: "Dispatcher")
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: { $0.level == .screenSaver }) else { return }
                window.setContentSize(NSSize(width: 580, height: 420))
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
            }

            if !imageItems.isEmpty {
                let previewItems = Array(imageItems.prefix(8))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(previewItems) { item in
                            VStack {
                                if let nsImg = NSImage(contentsOf: item.url) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.appleSurface2)
                                        .frame(width: 48, height: 48)
                                        .overlay(Image(systemName: "doc.fill").foregroundStyle(Color.appleSoft).font(.callout))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
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
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("格式")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                    .frame(width: 28, alignment: .leading)
                ForEach(CompressionFormat.allCases) { fmt in
                    PillButton(
                        label: fmt.displayName,
                        isSelected: state.selectedFormat.id == fmt.id,
                        action: { state.selectedFormat = fmt }
                    )
                }
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
                        isSelected: state.selectedQuality.id == ql.id,
                        action: { state.selectedQuality = ql }
                    )
                }
                Spacer(minLength: 0)
            }
        }
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
        let items = imageItems

        Task {
            let engine = CompressionEngine()
            let results = await engine.compress(
                items: items,
                format: state.selectedFormat,
                quality: state.selectedQuality
            )

            await MainActor.run {
                var successCount = 0
                var failCount = 0
                for item in results {
                    switch item.status {
                    case .completed:
                        successCount += 1
                        AppLog.shared.log("压缩成功 \(item.url.lastPathComponent)", category: "Dispatcher", level: .success)
                    case .failed(let reason):
                        failCount += 1
                        AppLog.shared.log("压缩失败 \(item.url.lastPathComponent): \(reason)", category: "Dispatcher", level: .error)
                    default:
                        break
                    }
                }
                AppLog.shared.log("压缩完成 成功=\(successCount)/\(items.count) 失败=\(failCount)", category: "Dispatcher", level: .success)
                if successCount > 0 {
                    // 仅成功时设 showResult，全失败时保持 false 让用户能重试
                    showResult = true
                    AppNotification.send(title: "压缩完成", body: "\(successCount) 个文件已压缩")
                }
                // 压缩成功后 0.6s 自动关弹窗（全失败时不关，保留状态供查看）
                // 注意：锁和 isCompressing 延迟到窗口关闭时才重置，防止 0.6s 窗口期内重复触发
                if successCount > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        AppLog.shared.log("压缩弹窗完成，关闭窗口", category: "Dispatcher")
                        for window in NSApp.windows where window.level == .screenSaver {
                            window.close()
                        }
                        isCompressing = false
                        CompressionEngine.releaseCompressLock()
                    }
                } else {
                    // 全失败：保留窗口供查看，但仍需释放锁让用户能重试
                    isCompressing = false
                    CompressionEngine.releaseCompressLock()
                }
            }
        }
    }
}
