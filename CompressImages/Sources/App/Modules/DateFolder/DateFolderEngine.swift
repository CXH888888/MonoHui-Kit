import Foundation
import ApplicationServices

struct DateFolderEngine {

    // MARK: - 创建锁（防止 create() 重复触发导致多个文件夹）
    // @State 的更新在 SwiftUI 中可能有延迟，同一 runloop 内的两次调用可能都读到 false。
    // 用 NSLock 保证原子性，绝对可靠。
    private static let createLock = NSLock()
    private static var createInProgress = false

    /// 尝试获取创建锁。成功返回 true（表示可以继续创建），失败返回 false（已有创建在进行中）
    static func tryAcquireCreateLock() -> Bool {
        createLock.lock()
        defer { createLock.unlock() }
        if createInProgress { return false }
        createInProgress = true
        return true
    }

    /// 释放创建锁（创建完成或失败后调用）
    static func releaseCreateLock() {
        createLock.lock()
        defer { createLock.unlock() }
        createInProgress = false
    }

    static func formatName(format: String, prefix: String, suffix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return "\(prefix)\(formatter.string(from: Date()))\(suffix)"
    }

    static func resolveUniqueURL(directory: URL, name: String) -> URL {
        let base = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: base.path) {
            return base
        }
        var i = 2
        while true {
            let candidate = directory.appendingPathComponent("\(name) \(i)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            i += 1
        }
    }

    static func createFolder(in directory: URL, format: String, prefix: String, suffix: String) throws -> URL {
        let name = formatName(format: format, prefix: prefix, suffix: suffix)
        let targetURL = resolveUniqueURL(directory: directory, name: name)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
        return targetURL
    }

    static func createFolder(in directory: URL, name: String) throws -> URL {
        let targetURL = resolveUniqueURL(directory: directory, name: name)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
        return targetURL
    }

    static func selectAndRename(_ url: URL) {
        let path = url.path

        let script = """
        tell application "Finder"
            set targetFolder to (POSIX file "\(path)") as alias
            reveal targetFolder
            select targetFolder
        end tell
        tell application "System Events"
            keystroke return
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            AppLog.shared.log("selectAndRename 启动 osascript 失败: \(error)", category: "DateFolder", level: .error)
        }
    }

    static func revealInFinder(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-R", url.path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            AppLog.shared.log("revealInFinder 启动 open 失败: \(error)", category: "DateFolder", level: .error)
        }
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func run(urls: [URL], format: String) {
        guard let firstURL = urls.first else { return }

        let directory = firstURL.deletingLastPathComponent()

        let prefix = UserDefaults.standard.string(forKey: "datefolder_prefix") ?? ""
        let suffix = UserDefaults.standard.string(forKey: "datefolder_suffix") ?? "-"

        do {
            let createdURL = try createFolder(in: directory, format: format, prefix: prefix, suffix: suffix)

            if hasAccessibilityPermission() {
                selectAndRename(createdURL)
            } else {
                revealInFinder(createdURL)
            }
        } catch {
            AppLog.shared.log("DateFolderEngine.run 创建失败 format=\(format) dir=\(directory.path) error=\(error)", category: "DateFolder", level: .error)
            // 通知用户失败原因，避免"右键没反应"的困惑
            DispatchQueue.main.async {
                AppNotification.send(title: "新建文件夹失败", body: error.localizedDescription)
            }
        }
    }

    static func runInteractive(urls: [URL], name: String, moveSelectedFiles: Bool = false) throws -> URL {
        guard let firstURL = urls.first else {
            throw NSError(domain: "DateFolderEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "未选中任何文件"])
        }
        let directory = firstURL.deletingLastPathComponent()
        return try runInteractiveInDirectory(directory: directory, urls: urls, name: name, moveSelectedFiles: moveSelectedFiles)
    }

    /// 在指定目录内创建文件夹（用户当前打开的 Finder 窗口目录），可选移入选中文件
    static func runInteractiveInDirectory(directory: URL, urls: [URL], name: String, moveSelectedFiles: Bool = false) throws -> URL {
        let createdURL = try createFolder(in: directory, name: name)

        // 移入选中文件到新文件夹（类似 macOS 原生"新建所选文件的文件夹"）
        if moveSelectedFiles {
            for url in urls {
                let dest = createdURL.appendingPathComponent(url.lastPathComponent)
                // 目标已存在时跳过，避免抛错中断后续文件
                guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
                do {
                    try FileManager.default.moveItem(at: url, to: dest)
                } catch {
                    AppLog.shared.log("移入文件失败 \(url.lastPathComponent): \(error)", category: "DateFolder", level: .warn)
                }
            }
        }

        if hasAccessibilityPermission() {
            selectAndRename(createdURL)
        } else {
            revealInFinder(createdURL)
        }
        return createdURL
    }
}
