import Foundation

/// 目标输出格式。sips 原生的可写格式，无需额外依赖。
enum TargetFormat: String, CaseIterable, Identifiable {
    case png, jpeg, tiff

    var id: String { rawValue }

    var displayName: String {
        rawValue.uppercased()
    }

    var sipsTarget: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }
}

struct FormatItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: Status = .pending
    let fileSize: UInt64

    init(url: URL) {
        self.url = url
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    enum Status {
        case pending
        case converting
        case completed(outputURL: URL)
        case failed(String)
    }

    var fileName: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
}

/// 系统标准 sRGB ICC 配置文件，用于 --matchTo 色彩空间标准化。
private let sRGBProfilePath = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"

/// 用系统自带 sips 批量转换图像格式（含 PSD 渲染像素为平面图）。
actor FormatConversionEngine {
    func convert(items: [FormatItem], target: TargetFormat, trimEdges: Bool = false) async -> [FormatItem] {
        await withTaskGroup(of: (Int, FormatItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { [self] in
                    let result = await self.convertSingle(item: item, target: target, trimEdges: trimEdges)
                    return (index, result)
                }
            }

            var results = items
            for await (index, updated) in group {
                results[index] = updated
            }
            return results
        }
    }

    private func convertSingle(item: FormatItem, target: TargetFormat, trimEdges: Bool) async -> FormatItem {
        var updated = item
        updated.status = .converting

        let outputURL = uniqueOutputURL(for: item, target: target)
        let proc = Process()

        if let magick = locateMagick() {
            // ImageMagick 渲染：色彩与 Photoshop 一致，且输出 straight alpha。
            // [0] 取合并后的合成帧。
            proc.executableURL = URL(fileURLWithPath: magick)
            if let env = magickEnvironment(for: magick) { proc.environment = env }
            var args = ["\(item.url.path)[0]", "-background", "none"]
            // 裁掉四周与边缘同色的空白区域（透明留白/纯色边框），让内容紧贴边界。
            if trimEdges { args += ["-trim", "+repage"] }
            if target == .jpeg { args += ["-quality", "90"] }
            args.append(outputURL.path)
            proc.arguments = args
        } else {
            // 回退 sips：无 ImageMagick 时仍可用，但复杂 PSD/PSB 的半透明色彩可能与 Photoshop 有偏差。
            // sips 无裁边能力，trimEdges 在此回退分支不生效。
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            proc.arguments = [
                "--matchTo", sRGBProfilePath,
                "-s", "format", target.sipsTarget,
                item.url.path, "--out", outputURL.path
            ]
        }

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                updated.status = .completed(outputURL: outputURL)
            } else {
                updated.status = .failed("转换失败（错误码 \(proc.terminationStatus)）")
            }
        } catch {
            updated.status = .failed(error.localizedDescription)
        }
        return updated
    }

    /// 定位 ImageMagick。优先 bundle 内置（随包分发、离线可用），其次 brew / PATH。
    private func locateMagick() -> String? {
        // 1. 应用内置（Contents/Resources/tools/imagemagick/bin/magick）
        if let res = Bundle.main.resourcePath {
            let bundled = "\(res)/tools/imagemagick/bin/magick"
            if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        }
        // 2. brew 安装路径
        for c in ["/opt/homebrew/bin/magick", "/usr/local/bin/magick"]
        where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // 3. PATH
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let p = dir.hasSuffix("/") ? "\(dir)magick" : "\(dir)/magick"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// 为 magick 进程准备自包含所需的环境变量，使内置 ImageMagick 不依赖用户系统安装。
    private func magickEnvironment(for magickPath: String) -> [String: String]? {
        // 假设布局 <root>/bin/magick，动态库与模块在 <root>/lib 下
        let magickURL = URL(fileURLWithPath: magickPath)
        let binDir = magickURL.deletingLastPathComponent()
        guard binDir.lastPathComponent == "bin" else { return nil }
        let root = binDir.deletingLastPathComponent()
        let libDir = root.appendingPathComponent("lib").path
        guard FileManager.default.fileExists(atPath: libDir) else { return nil }

        var env = ProcessInfo.processInfo.environment
        env["DYLD_LIBRARY_PATH"] = libDir
        env["MAGICK_CONFIGURE_PATH"] = "\(libDir)/ImageMagick/config-Q16HDRI"
        env["MAGICK_CODER_MODULE_PATH"] = "\(libDir)/ImageMagick/modules-Q16HDRI/coders"
        env["MAGICK_FILTER_MODULE_PATH"] = "\(libDir)/ImageMagick/modules-Q16HDRI/filters"
        return env
    }

    /// 输出到源文件同目录，同名存在时追加 `-1`、`-2` 后缀防止覆盖。
    private func uniqueOutputURL(for item: FormatItem, target: TargetFormat) -> URL {
        let dir = item.url.deletingLastPathComponent()
        let base = item.url.deletingPathExtension().lastPathComponent
        let ext = target.fileExtension

        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}