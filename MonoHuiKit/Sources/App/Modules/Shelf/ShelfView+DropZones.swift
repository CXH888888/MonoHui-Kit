import SwiftUI
import AppKit

// MARK: - 底部双投递区
extension ShelfView {
    // MARK: - 底部双投递区（AirDrop + 压缩暂存）

    /// 单个投递区尺寸：面板宽度的一半减去间距和 padding
    private var dropZoneSize: CGFloat {
        // 面板宽度 - 左右各 10 padding - 中间 6 间距，再除以 2
        (CGFloat(panelWidth) - 10 * 2 - 6) / 2
    }

    var airDropZone: some View {
        VStack(spacing: 3) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isAirDropTargeted ? .white : Color.white.opacity(0.7))
            Text("AirDrop")
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(isAirDropTargeted ? .white : Color.white.opacity(0.7))
        }
        .frame(width: dropZoneSize, height: dropZoneSize)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isAirDropTargeted ? Color.appleBlue.opacity(0.85) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isAirDropTargeted ? Color.appleBlue.opacity(0.9) : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isAirDropTargeted ? 1.03 : 1)
        .animation(Motion.move, value: isAirDropTargeted)
        .overlay {
            // 用 NSViewRepresentable 包装的拖放接收视图，比 SwiftUI onDrop 在 nonactivatingPanel 上可靠
            ShelfDropTargetView(
                isTargeted: $isAirDropTargeted,
                onDrop: { urls in
                    AppLog.shared.log("AirDrop 区 ShelfDropTargetView 触发，urls=\(urls.count)", category: "Shelf")
                    handleAirDrop(urls: urls)
                },
                allowsSelfDrop: true
            )
        }
        .onTapGesture {
            triggerAirDropForAll()
        }
    }

    /// 压缩并暂存区：拖入文件按原格式快速压缩后加入暂存箱
    var compressZone: some View {
        VStack(spacing: 3) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isCompressTargeted ? .white : Color.white.opacity(0.7))
            Text("压缩")
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(isCompressTargeted ? .white : Color.white.opacity(0.7))
        }
        .frame(width: dropZoneSize, height: dropZoneSize)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCompressTargeted ? Color.appleBlue.opacity(0.85) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isCompressTargeted ? Color.appleBlue.opacity(0.9) : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isCompressTargeted ? 1.03 : 1)
        .animation(Motion.move, value: isCompressTargeted)
        .overlay {
            ShelfDropTargetView(
                isTargeted: $isCompressTargeted,
                onDrop: { urls in
                    AppLog.shared.log("压缩区 ShelfDropTargetView 触发，urls=\(urls.count)", category: "Shelf")
                    handleCompressAndShelf(urls: urls)
                },
                allowsSelfDrop: true
            )
        }
    }

    /// AirDrop 拖入处理：拖入的文件直接 AirDrop，并加入中转站
    private func handleAirDrop(urls: [URL]) {
        Task { @MainActor in
            guard !urls.isEmpty else { return }
            // 先加入暂存箱（注释承诺的行为）
            store.addItems(urls: urls, sourceBundleId: "airdrop.zone")
            // 直接触发 AirDrop 投送
            AirDropHelper.share(urls: urls)
            AppLog.shared.log("AirDrop 区拖入投送：\(urls.count) 个文件", category: "Shelf")
        }
    }

    /// 点击 AirDrop 区：投送中转站内所有文件
    private func triggerAirDropForAll() {
        let allItems = store.items.map { $0.url }
        guard !allItems.isEmpty else { return }
        AirDropHelper.share(urls: allItems)
        AppLog.shared.log("AirDrop 区点击投送：\(allItems.count) 个文件", category: "Shelf")
    }

    /// 压缩并暂存：拖入的文件按原格式快速压缩后加入暂存箱
    /// 从暂存箱内部拖入的文件（cacheDir 路径）不重复添加，仅触发压缩
    private func handleCompressAndShelf(urls: [URL]) {
        Task { @MainActor in
            guard !urls.isEmpty else { return }
            AppLog.shared.log("压缩并暂存：拖入 \(urls.count) 个文件", category: "Shelf")
            // 区分已在暂存箱中的文件（cacheDir 路径）和新文件
            let cacheDir = ShelfStore.cacheDirectory
            var existingUrls: [URL] = []
            var newUrls: [URL] = []
            for url in urls {
                if url.path.hasPrefix(cacheDir.path) {
                    existingUrls.append(url)
                } else {
                    newUrls.append(url)
                }
            }
            // 新文件：加入暂存箱并触发压缩
            if !newUrls.isEmpty {
                let newItems = store.addItems(urls: newUrls, sourceBundleId: "compress.zone")
                for item in newItems {
                    await store.compressAndShelf(id: item.id)
                }
            }
            // 已在暂存箱的文件：仅触发压缩（不重复添加）
            // 用 id 查找 item，避免规则转换后 url 变化导致匹配失败
            for url in existingUrls {
                guard let item = store.items.first(where: { $0.url == url || $0.url.path == url.path }) else {
                    AppLog.shared.log("压缩区：未找到对应 item - \(url.lastPathComponent)", category: "Shelf", level: .warn)
                    continue
                }
                await store.compressAndShelf(id: item.id)
            }
        }
    }
}
