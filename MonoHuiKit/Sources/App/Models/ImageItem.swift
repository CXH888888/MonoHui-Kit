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
        /// 主动跳过（非图片、保持原格式不支持该扩展名等），不计入失败
        case skipped(String)
    }

    var fileName: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
    var estimatedFormat: CompressionFormat? {
        CompressionFormat.from(fileExtension: fileExtension)
    }

    /// 压缩产物是否反而比源文件大
    var isLargerThanSource: Bool {
        if case .completed(let result) = status {
            return result.outputSize >= result.inputSize
        }
        return false
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

extension ImageItem.Status {
    /// 取消后用于识别「还没开始就被中止」的条目
    var isPendingOrCompressing: Bool {
        switch self {
        case .pending, .compressing: return true
        default: return false
        }
    }
}
