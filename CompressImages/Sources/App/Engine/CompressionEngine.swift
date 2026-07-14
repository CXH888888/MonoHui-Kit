import Foundation

actor CompressionEngine {
    let toolResolver: ToolResolver

    // MARK: - 压缩锁（防止 compress() 重复触发）
    // @State 的更新在 SwiftUI 中可能有延迟，用 NSLock 保证原子性
    // let 是常量自带 Sendable，不需要 nonisolated(unsafe)；var 需要绕过 actor 隔离
    private static let compressLock = NSLock()
    private nonisolated(unsafe) static var compressInProgress = false

    /// 尝试获取压缩锁。成功返回 true，失败返回 false（已有压缩在进行中）
    nonisolated static func tryAcquireCompressLock() -> Bool {
        compressLock.lock()
        defer { compressLock.unlock() }
        if compressInProgress { return false }
        compressInProgress = true
        return true
    }

    /// 释放压缩锁
    nonisolated static func releaseCompressLock() {
        compressLock.lock()
        defer { compressLock.unlock() }
        compressInProgress = false
    }

    init(toolsDir: String? = nil) {
        self.toolResolver = ToolResolver(toolsDir: toolsDir)
    }

    func compress(items: [ImageItem], format: CompressionFormat, quality: QualityLevel) async -> [ImageItem] {
        await withTaskGroup(of: (Int, ImageItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { [self] in
                    let result = await self.compressSingle(item: item, format: format, quality: quality)
                    return (index, result)
                }
            }

            var results = items
            for await (index, updated) in group {
                results[index] = updated
            }
            return results
        }
    }

    func compressSingle(item: ImageItem, format: CompressionFormat, quality: QualityLevel) async -> ImageItem {
        var updated = item
        updated.status = .compressing

        do {
            let inputPath = item.url.path
            let outputURL = try determineOutputURL(for: item, format: format, quality: quality)
            let outputPath = outputURL.path

            let proc = try toolResolver.buildProcess(
                format: format,
                quality: quality,
                input: inputPath,
                output: outputPath
            )

            if toolResolver.libExists {
                var env = ProcessInfo.processInfo.environment
                env["DYLD_LIBRARY_PATH"] = toolResolver.libDir
                proc.environment = env
            }

            let outputData = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                proc.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        if let data = try? Data(contentsOf: outputURL) {
                            cont.resume(returning: data)
                        } else {
                            cont.resume(throwing: CompressionError.toolFailed(process.terminationStatus))
                        }
                    } else {
                        cont.resume(throwing: CompressionError.toolFailed(process.terminationStatus))
                    }
                }
                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: error)
                }
            }

            let inputSize = item.fileSize
            let outputSize = UInt64(outputData.count)

            updated.status = .completed(CompressionResult(
                inputSize: inputSize,
                outputSize: outputSize,
                outputURL: outputURL
            ))
        } catch {
            updated.status = .failed(error.localizedDescription)
        }

        return updated
    }

    private func determineOutputURL(for item: ImageItem, format: CompressionFormat, quality: QualityLevel) throws -> URL {
        let sourceDir = item.url.deletingLastPathComponent()
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let ext = format.fileExtension
        let compressedName = "\(baseName)-\(quality.shortLabel).\(ext)"
        let directURL = sourceDir.appendingPathComponent(compressedName)
        return directURL
    }

    enum CompressionError: Error, LocalizedError {
        case toolFailed(Int32)
        case invalidInput
        case outputExists

        var errorDescription: String? {
            switch self {
            case .toolFailed(let code): return "压缩工具返回错误码: \(code)"
            case .invalidInput: return "不支持的输入文件"
            case .outputExists: return "输出文件已存在"
            }
        }
    }
}
