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

    private static let volumeName = "MonoHui-Kit"

    // MARK: - 更新源（可在「关于与诊断 → 软件更新」里改）

    static let defaultOwner = "CXH888888"
    static let defaultRepo = "MonoHui-Kit"
    private static let repoSlugKey = "update_repo_slug"

    /// 形如 `owner/repo`，留空即默认仓库
    static var repoSlug: String {
        get {
            let saved = UserDefaults.standard.string(forKey: repoSlugKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "\(defaultOwner)/\(defaultRepo)" : saved
        }
        set {
            let slug = normalizeRepoSlug(newValue)
            if slug.isEmpty || slug == "\(defaultOwner)/\(defaultRepo)" {
                UserDefaults.standard.removeObject(forKey: repoSlugKey)
            } else {
                UserDefaults.standard.set(slug, forKey: repoSlugKey)
            }
        }
    }

    static var owner: String {
        repoSlug.split(separator: "/").first.map(String.init) ?? defaultOwner
    }

    static var repo: String {
        let parts = repoSlug.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : defaultRepo
    }

    /// 容忍粘贴整条仓库 URL：`https://github.com/owner/repo.git` → `owner/repo`
    static func normalizeRepoSlug(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:", "github.com/"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
            }
        }
        if s.lowercased().hasSuffix(".git") { s = String(s.dropLast(4)) }
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 保存新的更新源；下次检查才会生效，已缓存的待下载信息作废
    func applyRepoSlug(_ raw: String) {
        Self.repoSlug = raw
        pendingAsset = nil
        state = .idle
    }

    /// 待下载的 dmg。
    /// - `apiURL`：`https://api.github.com/.../releases/assets/{id}`，私有仓库唯一可用的下载入口，
    ///   需要 `Accept: application/octet-stream` + PAT，GitHub 会 302 到签名 CDN 地址。
    /// - `browserURL`：`https://github.com/.../releases/download/...`，浏览器用；私有仓库
    ///   即使带上 PAT 也返回 404（github.com 的网页端不认 Authorization 头），只作兜底。
    private var pendingAsset: PendingAsset?

    private struct PendingAsset {
        let name: String
        let apiURL: String?
        let browserURL: String
    }

    /// 手动下载兜底：网络到不了 CDN 时让用户走浏览器
    static var releasePageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
    }

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
                switch http.statusCode {
                case 404:
                    state = .failed("无法访问仓库 \(Self.repoSlug)（私有仓库需要 ~/.monohui-kit/github-token）")
                case 401:
                    state = .failed("GitHub 凭据无效，请重新生成 token")
                case 403:
                    state = .failed("GitHub 拒绝访问（403，可能触发限流）")
                default:
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
            pendingAsset = PendingAsset(name: dmg.name,
                                        apiURL: dmg.apiURL,
                                        browserURL: dmg.browserDownloadURL)
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
            defer { session.finishTasksAndInvalidate() }

            // 依次尝试：API 资产地址（私有仓库唯一可用）→ 网页下载地址（公开仓库兜底）
            // 只保留第一次失败的原因，避免兜底请求的 404 盖掉真正的诊断信息
            var firstError: String?
            func remember(_ message: String) { if firstError == nil { firstError = message } }

            for request in Self.candidateRequests(for: asset) {
                do {
                    let (tmpURL, response) = try await session.download(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        remember("下载失败：服务器响应异常")
                        continue
                    }
                    guard http.statusCode == 200 || http.statusCode == 206 else {
                        let hint = http.statusCode == 404
                            ? "，凭据失效或没有该 Release 的访问权限"
                            : ""
                        remember("下载失败（GitHub 返回 \(http.statusCode)\(hint)）")
                        AppLog.shared.log("更新下载失败 HTTP \(http.statusCode) \(request.url?.absoluteString ?? "")",
                                          category: "Update", level: .hot)
                        continue
                    }

                    let size = (try? FileManager.default
                        .attributesOfItem(atPath: tmpURL.path)[.size] as? Int64) ?? 0
                    guard size > 1_000_000 else {
                        remember("下载失败：文件不完整（\(size) 字节）")
                        continue
                    }

                    let dmgPath = "/tmp/\(asset.name)"
                    try? FileManager.default.removeItem(atPath: dmgPath)
                    try FileManager.default.moveItem(at: tmpURL, to: URL(fileURLWithPath: dmgPath))

                    AppLog.shared.log("更新包已下载：\(dmgPath)（\(size) 字节）",
                                      category: "Update", level: .hot)
                    state = .installing
                    installAndRestart(dmgPath: dmgPath)
                    return
                } catch {
                    remember("下载失败：\(error.localizedDescription)")
                    AppLog.shared.log("更新下载异常：\(error.localizedDescription)",
                                      category: "Update", level: .hot)
                }
            }
            state = .failed(firstError ?? "下载失败")
        }
    }

    /// 下载请求候选：API 资产地址优先，网页地址兜底
    private static func candidateRequests(for asset: PendingAsset) -> [URLRequest] {
        let token = githubToken()
        var requests: [URLRequest] = []

        if let api = asset.apiURL, let url = URL(string: api) {
            var request = URLRequest(url: url)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.timeoutInterval = 300
            requests.append(request)
        }

        if let url = URL(string: asset.browserURL) {
            var request = URLRequest(url: url)
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.timeoutInterval = 300
            requests.append(request)
        }

        return requests
    }

    /// 挂载新 dmg → 覆盖当前 App → 重启。
    /// 实际替换由独立脚本完成：本进程先退出，脚本等 1.5 秒再动手，
    /// 避免「自己删自己」时文件仍被占用。
    /// 脚本按「先解到临时目录 → 校验通过 → 再替换」的顺序执行，
    /// 任何一步失败都保留旧版本并重新拉起，不会把用户的应用删没。
    private func installAndRestart(dmgPath: String) {
        let target = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        LOG="$HOME/.monohui-kit/logs/update.log"
        mkdir -p "$(dirname "$LOG")"
        exec >>"$LOG" 2>&1
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') 开始更新 ==="

        DMG="\(dmgPath)"
        TARGET="\(target)"
        SRC="/Volumes/\(Self.volumeName)/MonoHui-Kit.app"
        STAGE="/Applications/.MonoHui-Kit.app.new"

        fail() {
            echo "失败：$1"
            /usr/bin/hdiutil detach "/Volumes/\(Self.volumeName)" -force >/dev/null 2>&1
            /usr/bin/open "$TARGET"
            exit 1
        }

        sleep 1.5
        /usr/bin/hdiutil detach "/Volumes/\(Self.volumeName)" -force >/dev/null 2>&1
        /usr/bin/hdiutil attach "$DMG" -nobrowse -noautoopen >/dev/null || fail "挂载 dmg 失败"
        [ -d "$SRC" ] || fail "dmg 内未找到 MonoHui-Kit.app"
        [ -d "$SRC/Contents/MacOS/MonoHuiKit" ] || fail "dmg 内可执行文件缺失"

        rm -rf "$STAGE"
        /bin/cp -R "$SRC" "$STAGE" || fail "拷贝到临时目录失败"
        /usr/bin/xattr -dr com.apple.quarantine "$STAGE" >/dev/null 2>&1

        rm -rf "$TARGET" || fail "删除旧版本失败"
        /bin/mv "$STAGE" "$TARGET" || fail "替换失败"

        /usr/bin/hdiutil detach "/Volumes/\(Self.volumeName)" -force >/dev/null 2>&1
        rm -f "$DMG"
        echo "完成：$TARGET"
        /usr/bin/open "$TARGET"
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
        let apiURL: String?
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case apiURL = "url"
            case browserDownloadURL = "browser_download_url"
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    // 进度回调本身只做一次主线程跳转，由调用方保证线程安全；
    // 标成 @Sendable 反而要求调用方传入 Sendable 闭包，与 [weak self] 冲突。
    let onProgress: (Double) -> Void

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

    /// GitHub 的资产下载会 302 跳到 `release-assets.githubusercontent.com` 的签名地址。
    /// 签名地址自带凭据，跨域再带 Authorization 会被对象存储拒绝，这里显式摘掉。
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var redirected = request
        if redirected.url?.host != task.originalRequest?.url?.host {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }
}
