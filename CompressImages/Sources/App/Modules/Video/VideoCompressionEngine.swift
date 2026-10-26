import Foundation
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

// MARK: - 参数模型

enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case high, balanced, small

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high:     return "高质量"
        case .balanced: return "平衡"
        case .small:    return "小体积"
        }
    }

    /// 每像素每帧的目标比特数（bpp）。数值越高画质越好、体积越大。
    var bitsPerPixel: Double {
        switch self {
        case .high:     return 0.085
        case .balanced: return 0.055
        case .small:    return 0.032
        }
    }

    var shortLabel: String {
        switch self {
        case .high:     return "hq"
        case .balanced: return "std"
        case .small:    return "small"
        }
    }
}

enum VideoResolution: String, CaseIterable, Identifiable, Codable {
    case original, p1080, p720, p480

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "原分辨率"
        case .p1080:    return "1080p"
        case .p720:     return "720p"
        case .p480:     return "480p"
        }
    }

    /// 长边上限；nil 表示不缩放
    var maxDimension: CGFloat? {
        switch self {
        case .original: return nil
        case .p1080:    return 1920
        case .p720:     return 1280
        case .p480:     return 854
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable, Codable {
    case h264, hevc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        }
    }

    var detail: String {
        switch self {
        case .h264: return "兼容性最好，任何设备都能播放"
        case .hevc: return "同画质体积约小 40%，旧设备可能不支持"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

// MARK: - 条目与结果

struct VideoResult {
    let inputSize: UInt64
    let outputSize: UInt64
    let outputURL: URL
    let width: Int
    let height: Int

    var savedBytes: Int64 { Int64(inputSize) - Int64(outputSize) }
    var savedPercent: Double {
        guard inputSize > 0 else { return 0 }
        return (1 - Double(outputSize) / Double(inputSize)) * 100
    }
}

struct VideoItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: Status = .pending
    let fileSize: UInt64
    var duration: Double = 0
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0

    init(url: URL) {
        self.url = url
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    enum Status {
        case pending
        case compressing
        case completed(VideoResult)
        case failed(String)
        case skipped(String)
    }

    var fileName: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    /// AVFoundation 能可靠解码的容器。mkv/avi/webm 等系统没有解码器，
    /// 交给 UTType 兜底判断，失败时会在结果里给出明确原因。
    static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp", "ts"
    ]

    static func isSupportedVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if supportedExtensions.contains(ext) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .movie) ?? false
    }

    var resolutionText: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "" }
        return "\(pixelWidth)×\(pixelHeight)"
    }

    var durationText: String {
        guard duration > 0 else { return "" }
        let total = Int(duration.rounded())
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct VideoCompressionOutcome {
    let items: [VideoItem]
    let report: CompressionReport
}

// MARK: - 引擎

/// 基于 AVFoundation 的视频压缩。
///
/// 选择原生实现而非内置 ffmpeg 的原因：不增加 40~80MB 安装包体积，
/// 且可直接走 VideoToolbox 硬件编码，速度更快、发热更低。
/// 码率由「分辨率 × 帧率 × 每像素比特数」估算，并受源码率上限约束。
actor VideoCompressionEngine {
    static let maxConcurrent = 2

    private var reservedOutputPaths: Set<String> = []

    func compress(
        items: [VideoItem],
        quality: VideoQuality,
        resolution: VideoResolution,
        codec: VideoCodec,
        onProgress: (@Sendable (CompressionProgress) -> Void)? = nil
    ) async -> VideoCompressionOutcome {
        let startedAt = Date()
        reservedOutputPaths.removeAll()

        let relay = ProgressRelay(total: items.count, handler: onProgress)
        var results = items
        let total = items.count
        var cancelled = false

        await withTaskGroup(of: (Int, VideoItem).self) { group in
            var nextIndex = 0
            let seed = min(VideoCompressionEngine.maxConcurrent, total)
            for _ in 0..<seed {
                let index = nextIndex
                let item = items[index]
                nextIndex += 1
                group.addTask { [self] in
                    let result = await compressSingle(
                        item: item, quality: quality, resolution: resolution, codec: codec,
                        onFraction: { fraction in relay.report(fraction, name: item.fileName) })
                    return (index, result)
                }
            }

            for await (index, updated) in group {
                results[index] = updated
                relay.finishOne(updated.fileName)

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
                            item: item, quality: quality, resolution: resolution, codec: codec,
                            onFraction: { fraction in relay.report(fraction, name: item.fileName) })
                        return (index, result)
                    }
                }
            }
        }

        if cancelled {
            for index in results.indices {
                switch results[index].status {
                case .pending, .compressing: results[index].status = .skipped("已取消")
                default: break
                }
            }
        }

        let failures = results.compactMap { item -> CompressionFailure? in
            guard case .failed(let reason) = item.status else { return nil }
            return CompressionFailure(fileName: item.fileName, path: item.url.path, reason: reason, detail: "")
        }
        let skipped = results.compactMap { item -> CompressionFailure? in
            guard case .skipped(let reason) = item.status else { return nil }
            return CompressionFailure(fileName: item.fileName, path: item.url.path, reason: reason, detail: "")
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
        if report.failedCount > 0 {
            for failure in failures.prefix(20) {
                AppLog.shared.log("视频压缩失败 \(failure.path)：\(failure.reason)", category: "Video", level: .error)
            }
        }
        return VideoCompressionOutcome(items: results, report: report)
    }

    func compressSingle(
        item: VideoItem,
        quality: VideoQuality,
        resolution: VideoResolution,
        codec: VideoCodec,
        onFraction: (@Sendable (Double) -> Void)? = nil
    ) async -> VideoItem {
        var updated = item
        updated.status = .compressing

        guard FileManager.default.fileExists(atPath: item.url.path) else {
            updated.status = .failed("文件不存在或已被移动")
            return updated
        }
        guard VideoItem.isSupportedVideo(item.url) else {
            updated.status = .skipped("不是视频文件")
            return updated
        }

        let asset = AVURLAsset(url: item.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        do {
            let duration = try await asset.load(.duration)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                updated.status = .failed("文件里没有视频轨道")
                return updated
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let nominalFPS = try await videoTrack.load(.nominalFrameRate)
            let dataRate = try await videoTrack.load(.estimatedDataRate)

            let displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let displayW = max(1, abs(displayRect.width))
            let displayH = max(1, abs(displayRect.height))

            let seconds = max(0.1, duration.seconds)
            updated.duration = seconds
            updated.pixelWidth = Int(displayW)
            updated.pixelHeight = Int(displayH)

            // 缩放按「显示尺寸」判定，但输出宽高要作用在自然尺寸上（transform 负责旋转）
            var scale: CGFloat = 1
            if let maxDim = resolution.maxDimension {
                scale = min(1, maxDim / max(displayW, displayH))
            }
            let outW = Self.even(max(2, naturalSize.width * scale))
            let outH = Self.even(max(2, naturalSize.height * scale))

            let fps = nominalFPS > 1 ? Double(min(60, nominalFPS)) : 30
            var targetBitrate = Double(outW * outH) * fps * quality.bitsPerPixel
            if dataRate > 0 { targetBitrate = min(targetBitrate, Double(dataRate) * 0.9) }
            targetBitrate = max(targetBitrate, 400_000)

            let outputURL = try determineOutputURL(for: item)
            let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

            let transcoder = VideoTranscoder(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                outputURL: outputURL,
                width: outW,
                height: outH,
                bitrate: Int(targetBitrate),
                frameRate: fps,
                codec: codec,
                transform: transform,
                duration: seconds,
                onFraction: onFraction
            )
            try await withTaskCancellationHandler {
                try await transcoder.run()
            } onCancel: {
                transcoder.cancel()
            }

            let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            if outputSize == 0 {
                updated.status = .failed("编码器未生成输出文件")
                return updated
            }
            if outputSize >= item.fileSize {
                // 源文件已经很紧凑，再编码只会更大：删掉产物并如实告知
                try? FileManager.default.removeItem(at: outputURL)
                updated.status = .skipped("压缩后体积未减小（源文件已足够紧凑）")
                return updated
            }

            updated.status = .completed(VideoResult(
                inputSize: item.fileSize,
                outputSize: outputSize,
                outputURL: outputURL,
                width: Int(displayW * scale),
                height: Int(displayH * scale)
            ))
        } catch VideoTranscodeError.cancelled {
            updated.status = .skipped("已取消")
        } catch {
            // 取消时 writer 会以 cancelled 状态收尾，统一归为「已取消」而不是失败
            if Task.isCancelled {
                updated.status = .skipped("已取消")
            } else {
                updated.status = .failed(Self.friendlyMessage(for: error))
            }
        }
        return updated
    }

    private func determineOutputURL(for item: VideoItem) throws -> URL {
        let dir = item.url.deletingLastPathComponent()
        let base = item.url.deletingPathExtension().lastPathComponent
        // 容器固定为 mp4：AVAssetWriter(fileType: .mp4) 写出的内容不能挂 .mov/.mkv 扩展名
        let ext = "mp4"
        var candidate = dir.appendingPathComponent("\(base)-压缩.\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path)
            || reservedOutputPaths.contains(candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-压缩-\(counter).\(ext)")
            counter += 1
        }
        reservedOutputPaths.insert(candidate.path)
        return candidate
    }

    private static func even(_ value: CGFloat) -> Int {
        let v = Int(value.rounded())
        return v % 2 == 0 ? v : max(2, v - 1)
    }

    static func friendlyMessage(for error: Error) -> String {
        if let error = error as? VideoTranscodeError {
            return error.errorDescription ?? "视频压缩失败"
        }
        let ns = error as NSError
        if ns.domain == AVFoundationErrorDomain {
            return "系统编码器错误：\(ns.localizedDescription)"
        }
        return error.localizedDescription
    }
}

/// 跨任务共享的进度上报器，避免在并发闭包里捕获可变的局部变量
private final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0
    private let total: Int
    private let handler: (@Sendable (CompressionProgress) -> Void)?

    init(total: Int, handler: (@Sendable (CompressionProgress) -> Void)?) {
        self.total = total
        self.handler = handler
    }

    func finishOne(_ name: String) {
        lock.lock()
        completed += 1
        let current = completed
        lock.unlock()
        handler?(CompressionProgress(completed: current, total: total, currentFileName: name))
    }

    func report(_ fraction: Double, name: String) {
        lock.lock()
        let current = completed
        lock.unlock()
        handler?(CompressionProgress(
            completed: current, total: total,
            currentFileName: name, currentFraction: fraction))
    }
}

// MARK: - 转码器

enum VideoTranscodeError: Error, LocalizedError {
    case readerFailed(String)
    case writerFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .readerFailed(let message): return "读取视频失败：\(message)"
        case .writerFailed(let message): return "写入视频失败：\(message)"
        case .cancelled: return "已取消"
        }
    }
}

/// AVAssetReader → AVAssetWriter 的转码流水线。
/// 视频轨重编码到目标码率/分辨率，音频轨直接透传（不二次损失音质）。
final class VideoTranscoder: @unchecked Sendable {
    private let asset: AVURLAsset
    private let videoTrack: AVAssetTrack
    private let audioTrack: AVAssetTrack?
    private let outputURL: URL
    private let width: Int
    private let height: Int
    private let bitrate: Int
    private let frameRate: Double
    private let codec: VideoCodec
    private let transform: CGAffineTransform
    private let duration: Double
    private let onFraction: (@Sendable (Double) -> Void)?

    private let queue = DispatchQueue(label: "com.quickactions.video-transcode", qos: .userInitiated)
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?

    /// 供外部取消：中断读写后 run() 会以 cancelled 结束
    func cancel() {
        reader?.cancelReading()
        writer?.cancelWriting()
    }

    init(asset: AVURLAsset, videoTrack: AVAssetTrack, audioTrack: AVAssetTrack?,
         outputURL: URL, width: Int, height: Int, bitrate: Int, frameRate: Double,
         codec: VideoCodec, transform: CGAffineTransform, duration: Double,
         onFraction: (@Sendable (Double) -> Void)?) {
        self.asset = asset
        self.videoTrack = videoTrack
        self.audioTrack = audioTrack
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.frameRate = frameRate
        self.codec = codec
        self.transform = transform
        self.duration = duration
        self.onFraction = onFraction
    }

    func run() async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        self.reader = reader
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw VideoTranscodeError.readerFailed("无法添加视频读取通道")
        }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        self.writer = writer

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoMaxKeyFrameIntervalKey: Int(frameRate * 2),
            AVVideoExpectedSourceFrameRateKey: Int(frameRate),
            AVVideoAllowFrameReorderingKey: true
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else {
            throw VideoTranscodeError.writerFailed("无法添加视频写入通道")
        }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack {
            // 音频显式重编码为 AAC：直接透传（outputSettings: nil）在部分源上
            // 会让 writer.canAdd 返回 false，音轨被静默丢弃（实测 mp4/AAC 源即如此）
            // 固定 48kHz 立体声：由 AVAssetReader 负责重采样与声道映射，
            // 避免源采样率（如 22.05kHz 单声道）与 AAC 编码器不匹配导致
            // 「Cannot Encode Media」
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let pcmSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcmSettings)
            if writer.canAdd(input), reader.canAdd(output) {
                writer.add(input)
                reader.add(output)
                audioOutput = output
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw VideoTranscodeError.readerFailed(reader.error?.localizedDescription ?? "无法开始读取")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw VideoTranscodeError.writerFailed(writer.error?.localizedDescription ?? "无法开始写入")
        }
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            let state = TranscodeState()
            let fractionHandler = onFraction
            let duration = duration

            group.enter()
            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    guard let sample = videoOutput.copyNextSampleBuffer() else {
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if !videoInput.append(sample) {
                        state.fail(writer.error ?? VideoTranscodeError.writerFailed("追加视频帧失败"))
                        reader.cancelReading()
                        writer.cancelWriting()
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if duration > 0 {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        state.progress = min(1, max(0, pts / duration))
                    }
                }
            }

            if let audioInput, let audioOutput {
                group.enter()
                audioInput.requestMediaDataWhenReady(on: queue) {
                    while audioInput.isReadyForMoreMediaData {
                        guard let sample = audioOutput.copyNextSampleBuffer() else {
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }
                        if !audioInput.append(sample) {
                            state.fail(writer.error ?? VideoTranscodeError.writerFailed("追加音频失败"))
                            reader.cancelReading()
                            writer.cancelWriting()
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            // 进度轮询：每 0.5s 读一次已写入的时长占比
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
            timer.setEventHandler {
                fractionHandler?(state.progress)
            }
            timer.resume()

            group.notify(queue: queue) {
                timer.cancel()
                if let error = state.error {
                    continuation.resume(throwing: error)
                    return
                }
                if reader.status == .failed {
                    continuation.resume(throwing: VideoTranscodeError.readerFailed(
                        reader.error?.localizedDescription ?? "读取中断"))
                    return
                }
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: VideoTranscodeError.writerFailed(
                            writer.error?.localizedDescription ?? "写入未完成"))
                    }
                }
            }
        }
    }
}

private final class TranscodeState: @unchecked Sendable {
    private let lock = NSLock()
    private var _error: Error?
    private var _progress: Double = 0

    var error: Error? {
        lock.lock(); defer { lock.unlock() }
        return _error
    }

    var progress: Double {
        get { lock.lock(); defer { lock.unlock() }; return _progress }
        set { lock.lock(); _progress = newValue; lock.unlock() }
    }

    func fail(_ error: Error) {
        lock.lock()
        if _error == nil { _error = error }
        lock.unlock()
    }
}
