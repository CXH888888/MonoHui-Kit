import Foundation
import UniformTypeIdentifiers

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: Status = .pending
    let fileSize: UInt64

    init(url: URL) {
        self.url = url
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    enum Status {
        case pending
        case compressing
        case completed(CompressionResult)
        case failed(String)
    }

    var fileName: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    var estimatedFormat: CompressionFormat? {
        CompressionFormat.from(fileExtension: fileExtension)
    }

    /// 拖入/选择文件时过滤非图片文件
    static func isSupportedImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if ["png", "jpg", "jpeg", "gif", "webp", "avif", "jxl", "svg", "tiff", "tif", "psd", "psb"].contains(ext) {
            return true
        }
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }
}

struct CompressionResult {
    let inputSize: UInt64
    let outputSize: UInt64
    let outputURL: URL

    var savedBytes: Int64 { Int64(inputSize) - Int64(outputSize) }
    var savedPercent: Double {
        guard inputSize > 0 else { return 0 }
        return (1 - Double(outputSize) / Double(inputSize)) * 100
    }
}
