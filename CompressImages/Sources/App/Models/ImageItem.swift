import Foundation

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: Status = .pending

    enum Status {
        case pending
        case compressing
        case completed(CompressionResult)
        case failed(String)
    }

    var fileName: String { url.lastPathComponent }
    var fileSize: UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }
    var fileExtension: String { url.pathExtension.lowercased() }

    var estimatedFormat: CompressionFormat? {
        CompressionFormat.from(fileExtension: fileExtension)
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
