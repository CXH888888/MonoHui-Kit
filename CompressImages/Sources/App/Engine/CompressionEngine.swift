import Foundation

/// 批量压缩的返回值：逐文件状态 + 可落盘的失败报告
struct CompressionOutcome {
    let items: [ImageItem]
    let report: CompressionReport
}

actor CompressionEngine {
    let toolResolver: ToolResolver

    // MARK: - 压缩锁（防止 compress() 重复触发）
    // @State 的更新在 SwiftUI 中可能有延迟，用 NSLock 保证原子性
    // let 是常量自带 Sendable，不需要 nonisolated(unsafe)；var 需要绕过 actor 隔离
    private static let compressLock = NSLock()
    private nonisolated(unsafe) static var compressInProgress = false

    /// 单文件压缩超时（秒）。超过后强杀进程并记为失败，
    /// 避免一张异常图片把整批几百个文件永久卡住。
    static let fileTimeout: TimeInterval = 240

    /// 并发上限。早先的实现对每个文件同时起一个进程，几百个文件会瞬间拉起
    /// 几百个 pngquant/cjpeg 进程，触发系统进程数上限与内存压力而随机失败。
    static let maxConcurrent = 4

    /// 本轮批次已占用的输出路径，避免同批次内同名不同扩展的文件互相覆盖
    private var reservedOutputPaths: Set<String> = []

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

    // MARK: - 批量入口

    /// 批量压缩。带并发上限、逐文件进度回调与失败汇总。
    /// - Parameters:
    ///   - keepOriginal: true 时按每个文件自身格式压缩，不做格式转换
    ///   - onProgress: 每完成一个文件回调一次（可能在任意线程）
    func compress(
        items: [ImageItem],
        format: CompressionFormat,
        quality: QualityLevel,
        keepOriginal: Bool,
        onProgress: (@Sendable (CompressionProgress) -> Void)? = nil
    ) async -> CompressionOutcome {
        let startedAt = Date()
        reservedOutputPaths.removeAll()

        var results = items
        var completed = 0
        let total = items.count
        var cancelled = false

        await withTaskGroup(of: (Int, ImageItem).self) { group in
            var nextIndex = 0
            let seed = min(CompressionEngine.maxConcurrent, total)

            // 先放满并发窗口，之后「完成一个补一个」，全程最多 maxConcurrent 个进程
            for _ in 0..<seed {
                let index = nextIndex
                let item = items[index]
                nextIndex += 1
                group.addTask { [self] in
                    let result = await compressSingle(
                        item: item, format: format, quality: quality, keepOriginal: keepOriginal)
                    return (index, result)
                }
            }

            for await (index, updated) in group {
                results[index] = updated
                completed += 1
                onProgress?(CompressionProgress(
                    completed: completed,
                    total: total,
                    currentFileName: updated.fileName
                ))

                if Task.isCancelled {
                    cancelled = true
                    continue
                }

                if nextIndex < total {
                    let index = nextIndex
                    let item = items[index]
                    nextIndex += 1
                    group.addTask { [self] in
                        let result = await compressSingle(
                            item: item, format: format, quality: quality, keepOriginal: keepOriginal)
                        return (index, result)
                    }
                }
            }
        }

        // 取消后未开始的条目停在 pending，统一标为「已取消」，避免被算进成功数
        if cancelled {
            for index in results.indices where results[index].status.isPendingOrCompressing {
                results[index].status = .skipped("已取消")
            }
        }

        let failures = results.compactMap { item -> CompressionFailure? in
            guard case .failed(let reason) = item.status else { return nil }
            return CompressionFailure(
                fileName: item.fileName,
                path: item.url.path,
                reason: reason,
                detail: ""
            )
        }
        let skipped = results.compactMap { item -> CompressionFailure? in
            guard case .skipped(let reason) = item.status else { return nil }
            return CompressionFailure(
                fileName: item.fileName,
                path: item.url.path,
                reason: reason,
                detail: ""
            )
        }

        let report = CompressionReport(
            startedAt: startedAt,
            finishedAt: Date(),
            total: total,
            succeeded: total - failures.count - skipped.count,
            failures: failures,
            skipped: skipped,
            cancelled: cancelled
        )

        if report.failedCount > 0 || report.skippedCount > 0 {
            AppLog.shared.log("压缩汇总 \(report.summaryLine)", category: "Compress", level: report.failedCount > 0 ? .warn : .info)
            for failure in failures.prefix(50) {
                AppLog.shared.log("失败 \(failure.path)：\(failure.reason)", category: "Compress", level: .error)
            }
        }
        return CompressionOutcome(items: results, report: report)
    }

    /// 单文件压缩（快速压缩逐条调用时也可用）
    func compressSingle(
        item: ImageItem,
        format: CompressionFormat,
        quality: QualityLevel,
        keepOriginal: Bool = false
    ) async -> ImageItem {
        var updated = item
        updated.status = .compressing

        if Task.isCancelled {
            updated.status = .skipped("已取消")
            return updated
        }

        // 1) 预检：非图片直接跳过，不再让 sips 报「Cannot extract image from file」
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            updated.status = .failed("文件不存在或已被移动")
            return updated
        }
        guard ImageItem.isSupportedImage(item.url) else {
            updated.status = .skipped("不是图片文件（视频请用「视频压缩」）")
            return updated
        }

        // 2) 解析实际目标：保持原格式时按文件自身格式走
        let sourceFormat = item.estimatedFormat
        let ext = item.fileExtension

        if keepOriginal, sourceFormat == nil {
            if InputNormalizer.canReencodeWithSips(extension: ext) {
                return await reencodeWithSips(item: item, quality: quality, updated: updated)
            }
            updated.status = .skipped("保持原格式暂不支持 .\(ext)，请改为指定输出格式")
            return updated
        }

        let target = keepOriginal ? (sourceFormat ?? format) : format

        if target == .svg, ext != "svg" {
            updated.status = .failed("SVG 只能由 SVG 源文件生成，请换一个输出格式")
            return updated
        }

        var prepared: PreparedInput?
        defer { prepared?.cleanup() }

        do {
            prepared = try InputNormalizer.prepare(url: item.url, target: target)
            guard let prepared else {
                updated.status = .failed("无法准备输入文件")
                return updated
            }

            let outputURL = try determineOutputURL(for: item, format: target, quality: quality)
            let inputPath = prepared.url.path
            let outputPath = outputURL.path

            let proc = try toolResolver.buildProcess(
                format: target,
                quality: quality,
                input: inputPath,
                output: outputPath
            )

            var outputData: Data
            do {
                outputData = try await run(proc, outputURL: outputURL)
            } catch CompressionEngine.CompressionError.skipped
                where target == .png && quality != .lossless {
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
            if target == .jpeg, quality != .lossless,
               let profile = ColorProfileKit.profile(of: item.url) {
                ColorProfileKit.embedProfile(profile, intoJPEGAt: outputURL)
                outputData = (try? Data(contentsOf: outputURL)) ?? outputData
            }

            updated.status = .completed(CompressionResult(
                inputSize: item.fileSize,
                outputSize: UInt64(outputData.count),
                outputURL: outputURL
            ))

            // 保持原格式＝纯压缩诉求：产物反而更大时删掉，不留下更占空间的文件
            if keepOriginal, updated.isLargerThanSource {
                try? FileManager.default.removeItem(at: outputURL)
                updated.status = .skipped("压缩后体积未减小（源文件已足够紧凑）")
            }
        } catch {
            updated.status = .failed(Self.friendlyMessage(for: error))
        }

        return updated
    }

    /// HEIC/HEIF/TIFF 保持原格式：交给系统 sips 重编码（App 内没有对应编码器）
    private func reencodeWithSips(item: ImageItem, quality: QualityLevel, updated: ImageItem) async -> ImageItem {
        var result = updated
        do {
            let outputURL = try determineOutputURL(for: item, format: nil, quality: quality, overrideExtension: item.fileExtension)
            try InputNormalizer.sipsReencode(
                url: item.url,
                format: item.fileExtension,
                formatOptions: InputNormalizer.sipsFormatOptions(
                    for: item.fileExtension, quality: sipsQualityValue(quality)),
                outputURL: outputURL
            )
            let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            result.status = .completed(CompressionResult(
                inputSize: item.fileSize,
                outputSize: size,
                outputURL: outputURL
            ))
            if result.isLargerThanSource {
                try? FileManager.default.removeItem(at: outputURL)
                result.status = .skipped("压缩后体积未减小（源文件已足够紧凑）")
            }
        } catch {
            result.status = .failed(Self.friendlyMessage(for: error))
        }
        return result
    }

    // MARK: - 进程执行

    /// 执行压缩进程并读取输出。自带 DYLD_LIBRARY_PATH 注入，并捕获 stderr
    /// 以便失败时把工具的真实报错展示给用户。
    ///
    /// stderr 必须在进程运行期间异步读取：pngquant/cjpeg 的告警一旦超过管道
    /// 缓冲区（64KB）就会阻塞在 write 上，而旧的实现在进程退出后才读，直接死锁。
    private func run(_ proc: Process, outputURL: URL) async throws -> Data {
        if toolResolver.libExists {
            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = toolResolver.libDir
            proc.environment = env
        }

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()

        let stderrRead = Task.detached(priority: .utility) { () -> String in
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }

        let state = ProcessRunState()
        let watchdog = DispatchWorkItem {
            state.markTimedOut()
            if proc.isRunning { proc.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + CompressionEngine.fileTimeout, execute: watchdog)
        defer { watchdog.cancel() }

        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            proc.terminationHandler = { process in
                cont.resume(returning: process.terminationStatus)
            }
            do {
                try proc.run()
                // 父进程持有的写端必须关掉，否则 readDataToEndOfFile 永远等不到 EOF
                stderrPipe.fileHandleForWriting.closeFile()
            } catch {
                stderrPipe.fileHandleForWriting.closeFile()
                cont.resume(throwing: error)
            }
        }

        let stderrText = await stderrRead.value
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if state.timedOut {
            throw CompressionError.timeout(Int(CompressionEngine.fileTimeout))
        }
        if status == 99 {
            // pngquant 专用退出码：该图即使 256 色也达不到质量下限而跳过
            throw CompressionError.skipped
        }
        if status == 0 {
            guard let data = try? Data(contentsOf: outputURL), !data.isEmpty else {
                throw CompressionError.outputMissing
            }
            return data
        }
        throw CompressionError.toolFailed(status, stderrText)
    }

    // MARK: - 输出路径

    private func determineOutputURL(
        for item: ImageItem,
        format: CompressionFormat?,
        quality: QualityLevel,
        overrideExtension: String? = nil
    ) throws -> URL {
        let sourceDir = item.url.deletingLastPathComponent()
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let ext = overrideExtension ?? format?.fileExtension ?? item.fileExtension
        let compressedName = "\(baseName)-\(quality.shortLabel).\(ext)"
        var candidate = sourceDir.appendingPathComponent(compressedName)

        // 同批次内同名不同扩展（a.png 与 a.jpg 都压成 jpg）会撞车，
        // 给后来者加序号，避免悄悄覆盖前一个产物。
        var counter = 2
        while reservedOutputPaths.contains(candidate.path) {
            candidate = sourceDir.appendingPathComponent("\(baseName)-\(quality.shortLabel)-\(counter).\(ext)")
            counter += 1
        }
        reservedOutputPaths.insert(candidate.path)
        return candidate
    }

    // MARK: - 错误信息

    /// 把工具 stderr 归类成用户能看懂的一句话，原始输出保留在括号里
    static func friendlyMessage(for error: Error) -> String {
        if let error = error as? CompressionError {
            return error.errorDescription ?? "压缩失败"
        }
        return error.localizedDescription
    }

    enum CompressionError: Error, LocalizedError {
        case toolFailed(Int32, String)
        case unsupportedConversion(String, String)
        case decodeFailed(String)
        case invalidInput
        case outputMissing
        case timeout(Int)
        case skipped

        var errorDescription: String? {
            switch self {
            case .toolFailed(let code, let message):
                let reason = CompressionError.classify(stderr: message, code: code)
                let detail = message.isEmpty ? "" : " — \(message)"
                return "\(reason)（错误码 \(code)）\(detail)"
            case .unsupportedConversion(let from, let to):
                return "不支持 .\(from) → \(to) 的转换，请换一个输出格式"
            case .decodeFailed(let message):
                return "无法解码源文件 — \(message)"
            case .invalidInput:
                return "不支持的输入文件"
            case .outputMissing:
                return "压缩工具未生成输出文件"
            case .timeout(let seconds):
                return "压缩超时（超过 \(seconds) 秒），已中止该文件"
            case .skipped:
                return "图片色彩过于复杂，该质量档无法保证画质，已跳过"
            }
        }

        /// stderr 关键词归类。工具报错原文往往很晦涩，先给结论再给原文。
        private static func classify(stderr: String, code: Int32) -> String {
            let text = stderr.lowercased()
            if text.contains("cannot extract image")
                || text.contains("unsupported file format")
                || text.contains("couldn't read")
                || text.contains("cannot read input")
                || text.contains("unrecognized file format")
                || text.contains("no decode delegate") {
                return "无法解码该文件（格式与目标不兼容或文件已损坏）"
            }
            if text.contains("not overwriting") || text.contains("exists") {
                return "输出文件已存在且不允许覆盖"
            }
            if text.contains("no space left") {
                return "磁盘空间不足"
            }
            if text.contains("permission denied") || text.contains("operation not permitted") {
                return "没有写入权限（请在系统设置中授权访问该文件夹）"
            }
            return "压缩工具返回错误码 \(code)"
        }
    }
}

/// 超时看门狗与 terminationHandler 之间的状态共享
private final class ProcessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var _timedOut = false

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _timedOut
    }

    func markTimedOut() {
        lock.lock()
        _timedOut = true
        lock.unlock()
    }
}

/// sips 质量值：与 JPEG 档位保持一致
private func sipsQualityValue(_ q: QualityLevel) -> Int {
    switch q {
    case .lossless: return 100
    case .highest:  return 100
    case .high:     return 90
    case .medium:   return 75
    case .low:      return 50
    case .lowest:   return 20
    }
}
