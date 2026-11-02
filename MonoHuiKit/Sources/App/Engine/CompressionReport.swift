import Foundation

/// 单个文件的压缩失败记录。批量压缩时必须能回答两个问题：
/// 1. 是哪个文件失败了（绝对路径 + 文件名）
/// 2. 为什么失败（面向用户的简短原因 + 工具原始输出）
struct CompressionFailure: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let path: String
    /// 面向用户的原因（已做中文归类）
    let reason: String
    /// 工具 stderr 原文，便于定位；为空时不展示
    let detail: String

    var displayText: String {
        detail.isEmpty ? "\(fileName) — \(reason)" : "\(fileName) — \(reason)（\(detail)）"
    }
}

/// 一次批量压缩的汇总结果。UI、通知、报告文件共用同一份数据源，
/// 避免「通知说失败 3 个但不知道是哪 3 个」。
struct CompressionReport {
    let startedAt: Date
    let finishedAt: Date
    let total: Int
    let succeeded: Int
    let failures: [CompressionFailure]
    /// 主动跳过（非图片、目标格式不支持等），不计入失败
    let skipped: [CompressionFailure]
    /// 用户中途取消
    var cancelled: Bool = false

    var failedCount: Int { failures.count }
    var skippedCount: Int { skipped.count }

    var elapsedText: String {
        let seconds = finishedAt.timeIntervalSince(startedAt)
        if seconds < 60 { return String(format: "%.1f 秒", seconds) }
        return String(format: "%.1f 分钟", seconds / 60)
    }

    var summaryLine: String {
        if cancelled {
            return "已取消 · 成功 \(succeeded) / 共 \(total)"
        }
        var parts = ["成功 \(succeeded)"]
        if failedCount > 0 { parts.append("失败 \(failedCount)") }
        if skippedCount > 0 { parts.append("跳过 \(skippedCount)") }
        return parts.joined(separator: " · ")
    }

    /// 通知正文：失败时列出前 3 个文件名，让人一眼知道去查什么
    var notificationBody: String {
        guard failedCount > 0 else {
            // 全部是已压缩产物时，「0 个文件压缩成功」读起来像出错，
            // 必须直说跳过原因，否则用户以为点了菜单没生效
            if skippedCount > 0 {
                return succeeded > 0
                    ? "\(succeeded) 个成功，\(skippedCount) 个已跳过"
                    : "\(skippedCount) 个文件已压缩过，无需重复处理"
            }
            return "\(succeeded) 个文件压缩成功"
        }
        let names = failures.prefix(3).map(\.fileName).joined(separator: "、")
        let more = failedCount > 3 ? " 等 \(failedCount) 个" : ""
        var text = "\(succeeded) 个成功，\(failedCount) 个失败：\(names)\(more)"
        if skippedCount > 0 { text += "；另有 \(skippedCount) 个已跳过" }
        return text
    }

    /// 有需要用户留意的内容（失败或跳过）——决定是否落盘报告、是否给明细入口
    var hasIssues: Bool { failedCount > 0 || skippedCount > 0 }

    /// 纯文本报告：可直接复制给他人，也可落盘留档
    func plainText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines: [String] = []
        lines.append("MonoHui-Kit 压缩报告")
        lines.append("开始时间：\(formatter.string(from: startedAt))")
        lines.append("耗时：\(elapsedText)")
        lines.append("总数：\(total) · 成功：\(succeeded) · 失败：\(failedCount) · 跳过：\(skippedCount)")
        lines.append("")

        if !failures.isEmpty {
            lines.append("失败明细（\(failures.count)）")
            for (index, failure) in failures.enumerated() {
                lines.append("\(index + 1). \(failure.fileName)")
                lines.append("   路径：\(failure.path)")
                lines.append("   原因：\(failure.reason)")
                if !failure.detail.isEmpty {
                    lines.append("   详情：\(failure.detail)")
                }
            }
            lines.append("")
        }

        if !skipped.isEmpty {
            lines.append("跳过明细（\(skipped.count)）")
            for (index, item) in skipped.enumerated() {
                lines.append("\(index + 1). \(item.fileName) — \(item.reason)")
            }
            lines.append("")
        }

        if failures.isEmpty && skipped.isEmpty {
            lines.append("没有失败或跳过的文件。")
        }
        return lines.joined(separator: "\n")
    }

    /// 落盘到 ~/.monohui-kit/reports/，返回文件 URL。失败时返回 nil（不影响主流程）。
    @discardableResult
    func writeToDisk() -> URL? {
        let dir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".monohui-kit/reports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyyMMdd-HHmmss"
            let url = dir.appendingPathComponent("compress-\(stamp.string(from: finishedAt)).txt")
            try plainText().data(using: .utf8)?.write(to: url)
            return url
        } catch {
            AppLog.shared.log("写入压缩报告失败：\(error)", category: "Compress", level: .warn)
            return nil
        }
    }
}

/// 进度回调载荷。批量压缩时驱动进度条与当前文件名展示。
struct CompressionProgress: Sendable {
    let completed: Int
    let total: Int
    let currentFileName: String
    /// 当前文件内部的进度（视频转码这类长任务用），0…1
    var currentFraction: Double = 0

    /// 整体进度：已完成文件 + 当前文件内进度
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, (Double(completed) + currentFraction) / Double(total))
    }
}
