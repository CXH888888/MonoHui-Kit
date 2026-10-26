import Foundation

/// 输入归一化层。
///
/// 每个编码器只认很少的几种输入格式（pngquant 只吃 PNG、avifenc 只吃 JPEG/PNG、
/// cwebp 不吃 GIF/AVIF、gifsicle 只吃 GIF）。批量压缩里混着 AVIF、HEIC、GIF、TIFF
/// 时，直接把源文件丢给目标编码器会成片失败——日志里的
/// `Cannot extract image from file`、`Unsupported file format AVIF` 都来自这里。
///
/// 本层负责在编码前用系统 sips 把源文件预解码成编码器认识的中间格式，
/// 并在用完后清理临时文件。
struct PreparedInput {
    let url: URL
    let isTemporary: Bool

    func cleanup() {
        guard isTemporary else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

enum InputNormalizer {

    /// 目标编码器原生支持的源扩展名。命中则直接编码，不产生临时文件。
    static func canEncodeDirectly(sourceExtension ext: String, target: CompressionFormat) -> Bool {
        let e = ext.lowercased()
        switch target {
        case .png:
            return e == "png"
        case .jpeg:
            // 非 JPEG 源走 sips 直接转 JPEG，不需要临时文件
            return true
        case .gif:
            return e == "gif"
        case .webp:
            return ["png", "jpg", "jpeg", "tif", "tiff", "webp"].contains(e)
        case .avif:
            return ["png", "jpg", "jpeg"].contains(e)
        case .jxl:
            return ["png", "jpg", "jpeg", "jxl"].contains(e)
        case .svg:
            return e == "svg"
        }
    }

    /// 为编码器准备可读输入。无法转换时抛出明确原因。
    static func prepare(url: URL, target: CompressionFormat) throws -> PreparedInput {
        let ext = url.pathExtension.lowercased()

        if canEncodeDirectly(sourceExtension: ext, target: target) {
            return PreparedInput(url: url, isTemporary: false)
        }

        // SVG 是矢量格式，无法由位图「归一化」得到，只能明确拒绝
        if target == .svg {
            throw CompressionEngine.CompressionError.unsupportedConversion(ext, target.displayName)
        }

        // GIF 目标：sips 可直接写 GIF，先转成 GIF 再交给 gifsicle 做调色板优化
        let intermediate: String = (target == .gif) ? "gif" : "png"
        let tempURL = try makeTempURL(extension: intermediate)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        proc.arguments = ["-s", "format", intermediate, url.path, "--out", tempURL.path]

        let stderr = Pipe()
        proc.standardError = stderr
        proc.standardOutput = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
            throw CompressionEngine.CompressionError.decodeFailed(error.localizedDescription)
        }

        guard proc.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tempURL.path) else {
            let text = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
            throw CompressionEngine.CompressionError.decodeFailed(text.isEmpty ? "系统无法解码该文件" : text)
        }

        return PreparedInput(url: tempURL, isTemporary: true)
    }

    /// HEIC/HEIF/TIFF 没有对应的第三方编码器，但 sips 本身能写。
    /// 「保持原格式」遇到它们时用 sips 重编码，避免整批照片/扫描件全部失败。
    static func canReencodeWithSips(extension ext: String) -> Bool {
        ["heic", "heif", "tiff", "tif"].contains(ext.lowercased())
    }

    /// sips 重编码时的 formatOptions：HEIC 用质量数值，TIFF 用 LZW 压缩
    static func sipsFormatOptions(for ext: String, quality: Int) -> String {
        let e = ext.lowercased()
        if e == "tiff" || e == "tif" { return "lzw" }
        return "\(quality)"
    }

    /// 用 sips 重编码（HEIC 保持原格式、TIFF 转 LZW）
    static func sipsReencode(url: URL, format: String, formatOptions: String, outputURL: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        proc.arguments = [
            "-s", "format", format,
            "-s", "formatOptions", formatOptions,
            url.path, "--out", outputURL.path
        ]
        let stderr = Pipe()
        proc.standardError = stderr
        proc.standardOutput = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            throw CompressionEngine.CompressionError.decodeFailed(error.localizedDescription)
        }

        guard proc.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            let text = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CompressionEngine.CompressionError.decodeFailed(text.isEmpty ? "系统无法重编码该文件" : text)
        }
    }

    private static func makeTempURL(extension ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickActionsCompress", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("input.\(ext)")
    }
}
