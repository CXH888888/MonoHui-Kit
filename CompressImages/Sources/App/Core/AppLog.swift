import Foundation
import Observation
import AppKit

/// 应用内日志：内存缓冲 + 文件持久化。
/// - 内存：最近 100 条，设置页实时显示
/// - 文件：~/.quickactions/logs/app.log，启动时载入历史，每条日志追加写入
/// 文件大小超过 3MB 时自动滚动重写（保留后半部分）
@Observable
final class AppLog {
    static let shared = AppLog()

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let level: Level
        let message: String

        enum Level: String, Hashable {
            case info = "ℹ️"
            case success = "✅"
            case warn = "⚠️"
            case error = "❌"
            case hot = "🔥"
        }
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 100
    private let lock = NSLock()
    private let logFileURL: URL
    private let maxFileSize: Int = 3_000_000 // 3MB

    private init() {
        let logDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quickactions/logs")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        self.logFileURL = logDir.appendingPathComponent("app.log")

        loadHistoryFromFile()
    }

    /// 启动时读取历史日志到内存（倒序显示）
    private func loadHistoryFromFile() {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var loaded: [Entry] = []
        loaded.reserveCapacity(lines.count)
        for line in lines {
            if let entry = parseLine(String(line), formatter: formatter) {
                loaded.append(entry)
            }
        }
        // 只保留最近 maxEntries 条
        if loaded.count > maxEntries {
            loaded.removeFirst(loaded.count - maxEntries)
        }
        self.entries = loaded
    }

    private func parseLine(_ line: String, formatter: DateFormatter) -> Entry? {
        // 格式：[2026-07-14 09:26:21.656] [HotKey] ✅ 已注册 ...
        var rest = line
        guard rest.hasPrefix("[") else { return nil }
        rest.removeFirst()
        guard let endBracket = rest.firstIndex(of: "]") else { return nil }
        let timestampStr = String(rest[..<endBracket])
        rest = String(rest[rest.index(after: endBracket)...])

        guard rest.hasPrefix(" [") else { return nil }
        rest.removeFirst(2)
        guard let catEnd = rest.firstIndex(of: "]") else { return nil }
        let category = String(rest[..<catEnd])
        rest = String(rest[rest.index(after: catEnd)...])

        // rest 现在形如 " ✅ 已注册 ..."
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard let firstChar = rest.first else { return nil }
        let level: Entry.Level
        switch firstChar {
        case "ℹ️".first: level = .info
        case "✅".first: level = .success
        case "⚠️".first: level = .warn
        case "❌".first: level = .error
        case "🔥".first: level = .hot
        default: level = .info
        }
        // 去掉 level emoji 和后面的空格
        var message = rest
        if let spaceIdx = message.firstIndex(of: " ") {
            message = String(message[message.index(after: spaceIdx)...])
        } else {
            message = ""
        }

        guard let ts = formatter.date(from: timestampStr) else { return nil }
        return Entry(timestamp: ts, category: category, level: level, message: message)
    }

    func log(_ message: String, category: String = "App", level: Entry.Level = .info) {
        let entry = Entry(timestamp: Date(), category: category, level: level, message: message)
        lock.lock()
        var newEntries = entries
        newEntries.append(entry)
        if newEntries.count > maxEntries {
            newEntries.removeFirst(newEntries.count - maxEntries)
        }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.entries = newEntries
        }
        NSLog("[\(category)] \(level.rawValue) \(message)")
        appendToFile(entry: entry)
    }

    private func appendToFile(entry: Entry) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: entry.timestamp))] [\(entry.category)] \(entry.level.rawValue) \(entry.message)\n"
        // 检查文件大小，超过限制则滚动
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let size = attrs[.size] as? Int, size > maxFileSize {
            rotateLogFile()
        }
        // 追加写入（文件不存在时自动创建）
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    /// 滚动日志：保留后半部分，前半部分丢弃
    private func rotateLogFile() {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let keepCount = lines.count / 2
        let kept = lines.suffix(keepCount).joined(separator: "\n") + "\n"
        try? kept.data(using: .utf8)?.write(to: logFileURL)
    }

    func clear() {
        entries = []
        try? Data().write(to: logFileURL)
    }

    func exportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.reversed().map { e in
            "[\(formatter.string(from: e.timestamp))] [\(e.category)] \(e.level.rawValue) \(e.message)"
        }.joined(separator: "\n")
    }

    func copyToPasteboard() {
        let text = exportText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
