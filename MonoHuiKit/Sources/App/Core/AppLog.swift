import Foundation
import Observation
import AppKit

/// 应用内日志：内存缓冲 + 文件持久化。
/// - 内存：最近 100 条，设置页实时显示
/// - 文件：~/.monohui-kit/logs/app.log，启动时载入历史，每条日志追加写入
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
    /// 受 lock 保护的真实缓冲。并发压缩时多个任务同时写日志，
    /// 直接读写 entries（@Observable 属性）会与主线程刷新产生数据竞争。
    private var storage: [Entry] = []
    private let fileQueue = DispatchQueue(label: "com.monohui.kit.applog.file")
    private let logFileURL: URL
    private let maxFileSize: Int = 3_000_000 // 3MB
    /// 文件写入句柄：常开，避免每条日志都 open/close
    private var fileHandle: FileHandle?
    /// 距上次大小检查写了多少条
    private var writesSinceSizeCheck = 0
    /// 是否已经排了一次主线程刷新（合并批量日志）
    private var pendingUIUpdate = false

    /// 日志行时间戳格式化器：DateFormatter 构造很贵，全进程共用一个（只在 fileQueue 上用）
    private static let lineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        let logDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".monohui-kit/logs")
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
        self.storage = loaded
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
        storage.append(entry)
        if storage.count > maxEntries {
            storage.removeFirst(storage.count - maxEntries)
        }
        // 合并刷新：一次批量压缩会连续写几百条，逐条 dispatch 到主线程毫无必要
        let shouldScheduleUI = !pendingUIUpdate
        pendingUIUpdate = true
        lock.unlock()

        if shouldScheduleUI {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.entries = self.storage
                self.pendingUIUpdate = false
                self.lock.unlock()
            }
        }
        appendToFile(entry: entry)
    }

    private func appendToFile(entry: Entry) {
        // 串行队列保证多线程批量压缩时不会交错写入同一文件
        fileQueue.async { [weak self] in
            self?.writeToFile(entry: entry)
        }
    }

    /// 写文件：复用同一个 FileHandle，避免每条日志都 open/close 三次系统调用；
    /// DateFormatter 也缓存——之前每条日志 new 一个，批量压缩时是实打实的开销。
    private func writeToFile(entry: Entry) {
        let line = "[\(Self.lineFormatter.string(from: entry.timestamp))] [\(entry.category)] \(entry.level.rawValue) \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if fileHandle == nil {
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: logFileURL)
            _ = try? fileHandle?.seekToEnd()
        }
        try? fileHandle?.write(contentsOf: data)

        // 大小检查很便宜但没必要每条都做，攒够 200 条查一次
        writesSinceSizeCheck += 1
        if writesSinceSizeCheck >= 200 {
            writesSinceSizeCheck = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
               let size = attrs[.size] as? Int, size > maxFileSize {
                rotateLogFile()
            }
        }
    }

    /// 滚动日志：保留后半部分，前半部分丢弃
    private func rotateLogFile() {
        try? fileHandle?.close()
        fileHandle = nil
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let keepCount = lines.count / 2
        let kept = lines.suffix(keepCount).joined(separator: "\n") + "\n"
        try? kept.data(using: .utf8)?.write(to: logFileURL)
    }

    func clear() {
        lock.lock()
        storage = []
        lock.unlock()
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
