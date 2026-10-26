import Foundation
import AppKit

/// 应用内更新：检查 GitHub Release → 下载 dmg（带进度）→ 自动挂载替换 → 重启。
///
/// 仓库是私有的，API 与附件下载都需要 PAT。构建时若存在
/// `~/.monohui-kit/github-token`，build.sh 会把它打进 Bundle 资源
/// （`Contents/Resources/github-token`），App 用它做 Authorization。
/// 建议用只读的细粒度 token（仅 Contents: Read）。
@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)      // 远端最新版本号（含 v 前缀）
        case downloading(Double)    // 0...1
        case installing
        case failed(String)
    }

    var state: State = .idle

    private static let owner = "CXH888888"
    private static let repo = "MonoHui-Kit"
    private static let volumeName = "MonoHui-Kit"
    private static let appPath = "/Applications/MonoHui-Kit.app"

    private var pendingAsset: (name: String, url: String)?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 「检查更新 / 下载并安装 / 重试」主按钮的统一入口
    func handlePrimaryAction() async {
        if case .available = state {
            downloadAndInstall()
        } else {
            await check()
        }
    }

    // MARK: - 检查

    func check() async {
        state = .checking

        var request = URLRequest(url: URL(string:
            "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = Self.githubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed("服务器响应异常")
                return
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 {
                    state = .failed("无法访问仓库（私有仓库需要 ~/.monohui-kit/github-token）")
                } else {
                    state = .failed("GitHub 返回 \(http.statusCode)")
                }
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard Self.isNewer(release.tagName, than: currentVersion) else {
                state = .upToDate
                return
            }
            guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
                state = .failed("该 Release 没有附带 dmg")
                return
            }
            pendingAsset = (name: dmg.name, url: dmg.browserDownloadURL)
            state = .available(release.tagName)
        } catch {
            state = .failed("网络错误：\(error.localizedDescription)")
        }
    }

    // MARK: - 下载并安装

    func downloadAndInstall() {
        guard case .available = state, let asset = pendingAsset else { return }
        state = .downloading(0)

        let delegate = DownloadProgressDelegate { [weak self] fraction in
            Task { @MainActor in
                if case .downloading = self?.state { self?.state = .downloading(fraction) }
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        Task {
            do {
                var request = URLRequest(url: URL(string: asset.url)!)
                if let token = Self.githubToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                request.timeoutInterval = 300

                let (tmpURL, response) = try await session.download(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    state = .failed("下载失败（GitHub 返回错误）")
                    return
                }

                let dmgPath = "/tmp/\(asset.name)"
                try? FileManager.default.removeItem(atPath: dmgPath)
                try FileManager.default.moveItem(at: tmpURL, to: URL(fileURLWithPath: dmgPath))

                state = .installing
                installAndRestart(dmgPath: dmgPath)
            } catch {
                state = .failed("下载失败：\(error.localizedDescription)")
            }
        }
    }

    /// 挂载新 dmg → 覆盖 /Applications → 重启。
    /// 实际替换由独立脚本完成：本进程先退出，脚本等 1.5 秒再动手，
    /// 避免「自己删自己」时文件仍被占用。
    private func installAndRestart(dmgPath: String) {
        let script = """
        #!/bin/bash
        sleep 1.5
        /usr/bin/hdiutil detach "/Volumes/\(Self.volumeName)" -force >/dev/null 2>&1
        /usr/bin/hdiutil attach "\(dmgPath)" -nobrowse -noautoopen >/dev/null
        sleep 1
        rm -rf "\(Self.appPath)"
        cp -R "/Volumes/\(Self.volumeName)/MonoHui-Kit.app" "\(Self.appPath)"
        /usr/bin/hdiutil detach "/Volumes/\(Self.volumeName)" -force >/dev/null 2>&1
        rm -f "\(dmgPath)"
        /usr/bin/open "\(Self.appPath)"
        """
        let scriptPath = "/tmp/monohui-updater.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            state = .failed("写入更新脚本失败：\(error.localizedDescription)")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptPath]
        do {
            try proc.run()
            AppLog.shared.log("更新脚本已启动，即将退出当前进程", category: "Update", level: .hot)
            NSApp.terminate(nil)
        } catch {
            state = .failed("启动更新脚本失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 工具

    /// PAT：构建时从 ~/.monohui-kit/github-token 打进 Bundle 资源
    static func githubToken() -> String? {
        guard let url = Bundle.main.url(forResource: "github-token", withExtension: nil) else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 版本比较：v3.10.0 > v3.9.9（按数字逐段比，不按字符串）
    static func isNewer(_ remote: String, than local: String) -> Bool {
        func numbers(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = numbers(remote), b = numbers(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
