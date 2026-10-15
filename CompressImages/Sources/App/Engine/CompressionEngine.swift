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

            var outputData: Data
            do {
                outputData = try await run(proc, outputURL: outputURL)
            } catch CompressionEngine.CompressionError.skipped
                where format == .png && quality != .lossless {
                // pngquant 退出码 99 = 该图即使 256 色也达不到质量下限。
                // 先放宽质量区间重试；仍被跳过则退回 oxipng 无损重编码，保证必有产物。
                let retryProc = toolResolver.buildPNGRetryProcess(
                    input: inputPath, output: outputPath)
                do {
                    outputData = try await run(retryProc, outputURL: outputURL)
                } catch CompressionEngine.CompressionError.skipped {
                    let fallbackProc = toolResolver.buildLosslessProcess(
                        input: inputPath, output: outputPath)
                    outputData = try await run(fallbackProc, outputURL: outputURL)
                }
            }

            // JPEG 有损链路（djpeg | cjpeg）不传递 ICC profile，
            // 编码后把源 profile 写回输出，避免 Adobe RGB / Display P3 等
            // 源文件被查看器按 sRGB 解释而整体偏色。
            // jpegtran 无损档用 -copy all 保留全部 marker，无需回写。
            if format == .jpeg, quality != .lossless,
               let profile = ColorProfileKit.profile(of: item.url) {
                ColorProfileKit.embedProfile(profile, intoJPEGAt: outputURL)
                outputData = (try? Data(contentsOf: outputURL)) ?? outputData
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

    /// 执行压缩进程并读取输出。自带 DYLD_LIBRARY_PATH 注入，并捕获 stderr
    /// 以便失败时把工具的真实报错（如输出文件已存在）展示给用户。
    private func run(_ proc: Process, outputURL: URL) async throws -> Data {
        if toolResolver.libExists {
            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = toolResolver.libDir
            proc.environment = env
        }

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            proc.terminationHandler = { process in
                let stderrText = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 99 {
                    // pngquant 专用退出码：该图即使 256 色也达不到质量下限而跳过
                    cont.resume(throwing: CompressionError.skipped)
                } else if process.terminationStatus == 0 {
                    if let data = try? Data(contentsOf: outputURL) {
                        cont.resume(returning: data)
                    } else {
                        cont.resume(throwing: CompressionError.outputMissing)
                    }
                } else {
                    cont.resume(throwing: CompressionError.toolFailed(process.terminationStatus, stderrText))
                }
            }
            do {
                try proc.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
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
        case toolFailed(Int32, String)
        case invalidInput
        case outputExists
        case outputMissing
        case skipped

        var errorDescription: String? {
            switch self {
            case .toolFailed(let code, let message):
                // message 为工具 stderr 原文，失败时一并展示，便于定位
                let detail = message.isEmpty ? "" : " — \(message)"
                return "压缩工具返回错误码: \(code)\(detail)"
            case .invalidInput: return "不支持的输入文件"
            case .outputExists: return "输出文件已存在"
            case .outputMissing: return "压缩工具未生成输出文件"
            case .skipped: return "图片色彩过于复杂，该质量档无法保证画质，已跳过"
            }
        }
    }
}
