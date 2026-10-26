import Foundation
import AppKit
import ImageIO

/// 格式转换引擎：按规则把图片转换为 PNG/JPG（不缩放，保留原始尺寸）
/// SVG/PDF 等矢量格式不转换，原样保留
enum TransformEngine {
    /// 按规则转换文件
    /// - Returns: 转换后的文件 URL（成功）或 nil（失败/无需转换）
    /// - Note: 内部仅使用 CoreGraphics / FileManager，均为线程安全，可后台执行
    static func transform(url: URL, rule: AppRule) -> URL? {
        // 原格式：直接返回
        guard rule.outputFormat.lowercased() != "original" else { return url }

        let ext = url.pathExtension.lowercased()
        let targetFmt = rule.outputFormat.lowercased()

        // SVG/PDF 矢量格式不转换，原样保留
        if ext == "svg" || ext == "pdf" {
            return url
        }

        // 已经是目标格式：直接返回
        if ext == targetFmt {
            return url
        }

        // 加载源图
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            AppLog.shared.log("转换失败：无法加载图片 \(url.lastPathComponent)", category: "Shelf", level: .error)
            return nil
        }

        // 输出到缓存目录（保留原始尺寸，不缩放）
        let outDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MonoHui-Kit/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let stem = url.deletingPathExtension().lastPathComponent
        let outURL = outDir.appendingPathComponent("\(stem).\(targetFmt)")

        // 写入
        let type: CFString
        switch targetFmt {
        case "png": type = "public.png" as CFString
        case "jpg", "jpeg": type = "public.jpeg" as CFString
        default: type = "public.png" as CFString
        }

        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, type, 1, nil) else {
            AppLog.shared.log("转换失败：无法创建输出文件", category: "Shelf", level: .error)
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            AppLog.shared.log("转换失败：写入失败", category: "Shelf", level: .error)
            return nil
        }

        AppLog.shared.log("转换成功：\(url.lastPathComponent) → \(outURL.lastPathComponent)（\(rule.formatDisplayName)）", category: "Shelf")
        return outURL
    }
}
