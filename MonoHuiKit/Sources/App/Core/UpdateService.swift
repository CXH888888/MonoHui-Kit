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
        let size: Int64?
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
                                        browserURL: dmg.browserDownloadURL,
                                        size: dmg.size)
            state = .available(release.tagName)
        } catch {
            state = .failed("网络错误：\(error.localizedDescription)")
        }
    }

    // MARK: - 下载并安装

    func downloadAndInstall() {
        guard case .available = state, let asset = pendingAsset else { return }
        state = .downloading(0)
        Self.archive(Self.failureMarkURL.path)

        // 进度只能靠 task.progress 的 KVO 拿：session 的 didWriteData 在这套
        // completion-handler 任务上不会回调（实测 0 次），进度条会一直停在 0。
        let onProgress: (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                if case .downloading = self?.state { self?.state = .downloading(fraction) }
            }
        }
        let session = URLSession(configuration: .default,
                                 delegate: RedirectStripper(),
                                 delegateQueue: nil)

        Task {
            defer { session.finishTasksAndInvalidate() }

            // 依次尝试：API 资产地址（私有仓库唯一可用）→ 网页下载地址（公开仓库兜底）
            // 只保留第一次失败的原因，避免兜底请求的 404 盖掉真正的诊断信息
            var firstError: String?
            func remember(_ message: String) { if firstError == nil { firstError = message } }

            for request in Self.candidateRequests(for: asset) {
                do {
                    let (tmpURL, response) = try await Self.download(request,
                                                                     session: session,
                                                                     fallbackTotal: asset.size ?? 0,
                                                                     onProgress: onProgress)
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
                    if let expected = asset.size, expected > 0, size != expected {
                        remember("下载失败：大小不符（期望 \(expected)，实际 \(size)）")
                        continue
                    }
                    guard size > 1_000_000 else {
                        remember("下载失败：文件不完整（\(size) 字节）")
                        continue
                    }

                    let dmgPath = "/tmp/\(asset.name)"
                    Self.archive(dmgPath)   // 旧包不删，移进归档
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

    /// 下载单个请求，并通过 `task.progress` 的 KVO 回报进度。
    ///
    /// 不能用 `URLSession.download(for:)`：那套 async 便捷方法会给任务挂内部 delegate，
    /// session 级 `didWriteData` 一次都不会回调（实测 15.9MB / 6.7s，回调 0 次），
    /// 进度条因此永远停在 0。改用 completion-handler 版任务 + KVO 观察 `fractionCompleted`。
    private static func download(_ request: URLRequest,
                                 session: URLSession,
                                 fallbackTotal: Int64,
                                 onProgress: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        let observer = ProgressRelay(fallbackTotal: fallbackTotal, onProgress: onProgress)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { url, response, error in
                observer.stop()
                if let error {
                    continuation.resume(throwing: error)
                } else if let url, let response {
                    continuation.resume(returning: (url, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            observer.attach(to: task)
            task.resume()
        }
    }

    /// 挂载新 dmg → 覆盖当前 App → 重启。
    /// 实际替换由独立脚本完成：本进程先退出，脚本等 1.5 秒再动手，
    /// 避免「自己删自己」时文件仍被占用。
    /// 脚本按「先解到临时目录 → 校验通过 → 再替换」的顺序执行，
    /// 任何一步失败都保留旧版本并重新拉起，不会把用户的应用删没。
    /// 收尾：安装包与旧版本备份都移入 `~/.monohui-kit/archive`，不做任何删除。
    private func installAndRestart(dmgPath: String) {
        let target = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        LOG="$HOME/.monohui-kit/logs/update.log"
        MARK="$HOME/.monohui-kit/update-failed.txt"
        mkdir -p "$(dirname "$LOG")"
        exec >>"$LOG" 2>&1
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') 开始更新 ==="

        DMG="\(dmgPath)"
        TARGET="\(target)"
        STAGE="$(dirname "$TARGET")/.MonoHui-Kit.app.new"
        BACKUP="$(dirname "$TARGET")/.MonoHui-Kit.app.previous"
        MOUNT=""

        # 项目约定：任何文件都不删除，一律移入归档目录（旧版本 App、安装包、临时目录都是）。
        ARCHIVE="$HOME/.monohui-kit/archive"
        archive() {
            [ -e "$1" ] || return 0
            /bin/mkdir -p "$ARCHIVE"
            local name
            name="$(basename "$1")"
            name="${name#.}"
            /bin/mv "$1" "$ARCHIVE/$name.$(date +%Y%m%d-%H%M%S)" 2>/dev/null
        }

        fail() {
            echo "失败：$1"
            printf '%s' "$1" > "$MARK"
            [ -n "$MOUNT" ] && /usr/bin/hdiutil detach "$MOUNT" -force >/dev/null 2>&1
            archive "$STAGE"
            /usr/bin/open "$TARGET" >/dev/null 2>&1
            exit 1
        }

        sleep 1.5

        # 收走以前失败遗留的安装包（当前这次要用的保留）
        for old in /tmp/MonoHui-Kit-v*.dmg; do
            [ -e "$old" ] || continue
            [ "$old" = "$DMG" ] && continue
            archive "$old"
        done

        /usr/bin/hdiutil detach "/Volumes/\(Self.volumeName)" -force >/dev/null 2>&1

        # 卷名被占用时 hdiutil 会挂到 "MonoHui-Kit 1"，所以从输出里取真实挂载点
        MOUNT="$(/usr/bin/hdiutil attach "$DMG" -nobrowse -noautoopen 2>/dev/null \
                 | grep -oE '/Volumes/.*$' | head -1 | sed 's/[[:space:]]*$//')"
        [ -n "$MOUNT" ] || fail "挂载 dmg 失败"
        echo "挂载点：$MOUNT"

        SRC="$MOUNT/MonoHui-Kit.app"
        [ -d "$SRC" ] || fail "dmg 内未找到 MonoHui-Kit.app"
        [ -f "$SRC/Contents/MacOS/MonoHuiKit" ] || fail "dmg 内可执行文件缺失"

        archive "$STAGE"
        /bin/cp -R "$SRC" "$STAGE" || fail "拷贝到临时目录失败"
        /usr/bin/xattr -dr com.apple.quarantine "$STAGE" >/dev/null 2>&1

        # 旧版本先改名保留，替换成功后才归档；任何一步失败都能回滚
        archive "$BACKUP"
        /bin/mv "$TARGET" "$BACKUP" || fail "移走旧版本失败"
        if ! /bin/mv "$STAGE" "$TARGET"; then
            /bin/mv "$BACKUP" "$TARGET" >/dev/null 2>&1
            fail "替换失败，已回滚"
        fi
        archive "$BACKUP"

        /usr/bin/hdiutil detach "$MOUNT" -force >/dev/null 2>&1
        archive "$DMG"
        archive "$MARK"
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

    /// 上次更新的收尾脚本若失败，本进程早已退出、界面无从得知。
    /// 脚本会把失败原因写进这个文件，下次启动时读出来展示一次后删除。
    private static var failureMarkURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".monohui-kit/update-failed.txt")
    }

    func consumeLastFailure() {
        let url = Self.failureMarkURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        Self.archive(url.path)
        let reason = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        // 只在还没进入任何状态时提示，避免盖掉用户刚点出来的结果
        if case .idle = state {
            state = .failed("上次更新未完成：\(reason)（详见 ~/.monohui-kit/logs/update.log）")
        }
    }

    // MARK: - 归档（项目约定：不删除文件，一律移入归档目录）

    static var archiveDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".monohui-kit/archive", isDirectory: true)
    }

    private static let archiveStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// 把文件/目录移到 `~/.monohui-kit/archive/`，重名时加时间戳。移动失败就算了，绝不删除。
    @discardableResult
    static func archive(_ path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }
        let dir = archiveDirectory
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var name = (path as NSString).lastPathComponent
            if name.hasPrefix(".") { name = String(name.dropFirst()) }
            let dest = dir.appendingPathComponent("\(name).\(archiveStamp.string(from: Date()))")
            try fm.moveItem(atPath: path, toPath: dest.path)
            return true
        } catch {
            AppLog.shared.log("归档失败 \(path)：\(error.localizedDescription)",
                              category: "Update", level: .warn)
            return false
        }
    }

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
        let size: Int64?

        enum CodingKeys: String, CodingKey {
            case name
            case apiURL = "url"
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}

/// GitHub 的资产下载会 302 跳到 `release-assets.githubusercontent.com` 的签名地址。
/// 签名地址自带凭据，跨域再带 Authorization 会被对象存储拒绝，这里显式摘掉。
/// 注意：只实现重定向，不实现下载进度——那套回调在 completion-handler 任务上不会触发。
private final class RedirectStripper: NSObject, URLSessionTaskDelegate {
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

/// 通过 KVO 观察 `URLSessionTask.progress`，把下载进度回报给 UI。
/// 这是唯一可靠的进度来源：session 的 `didWriteData` 在 completion-handler 任务上是 0 回调。
private final class ProgressRelay: NSObject {
    private let fallbackTotal: Int64
    private let onProgress: (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastReported: Double = -1
    private var lastTime = Date.distantPast

    init(fallbackTotal: Int64, onProgress: @escaping (Double) -> Void) {
        self.fallbackTotal = fallbackTotal
        self.onProgress = onProgress
    }

    func attach(to task: URLSessionDownloadTask) {
        observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.report(progress)
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }

    private func report(_ progress: Progress) {
        let done = Double(progress.completedUnitCount)
        let total = progress.totalUnitCount > 0
            ? Double(progress.totalUnitCount)
            : Double(fallbackTotal)
        guard total > 0, done > 0 else { return }

        let fraction = min(1, done / total)
        // 节流：进度至少前进 0.5%，或距上次上报超过 0.1 秒，避免高频刷主线程
        let now = Date()
        guard fraction - lastReported >= 0.005 || now.timeIntervalSince(lastTime) >= 0.1 else { return }
        lastReported = fraction
        lastTime = now
        onProgress(fraction)
    }
}
