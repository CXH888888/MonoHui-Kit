import Foundation

/// 压缩产物命名识别。
///
/// 产物命名规则统一为 `原名-<档位标签>.<ext>`：
/// - 图片：`photo-q75.jpg`、`photo-lossless.png`（标签来自 `QualityLevel.shortLabel`）
/// - 视频：`clip-压缩.mp4`
///
/// 批量压缩时先把已压过的产物识别出来跳过，避免
/// `photo-q75.jpg` 再被压成 `photo-q75-q75.jpg` —— 画质会二次劣化，
/// 文件名也会一层层叠上去，几百个文件混在一起后无法分辨哪张是最终稿。
///
/// 同批次同名撞车产生的 `-2`、`-3` 序号也归入已压缩，例如 `photo-q75-2.jpg`。
enum CompressionNaming {

    /// 图片产物的档位标签。直接从 `QualityLevel` 派生，保证改名时不会两处脱节。
    static let imageTags: [String] = QualityLevel.allCases.map(\.shortLabel)

    /// 视频产物标签（`determineOutputURL` 里硬编码的「压缩」）
    static let videoTag = "压缩"

    /// 设置项：是否跳过已有压缩产物。默认开启，关掉后行为回到改造前。
    static var skipCompressedEnabled: Bool {
        UserDefaults.standard.object(forKey: "skipCompressedOutputs") as? Bool ?? true
    }

    /// 识别图片文件名里的压缩档位标签，命中返回该标签（如 `q75`），否则 nil
    static func imageTag(inFileName name: String) -> String? {
        matchTag(in: name, candidates: imageTags)
    }

    /// 识别视频文件名里的压缩标签，命中返回 `压缩`，否则 nil
    static func videoTag(inFileName name: String) -> String? {
        matchTag(in: name, candidates: [videoTag])
    }

    /// 匹配 `<名称>-<标签>` 或 `<名称>-<标签>-<序号>`（末段必须全为数字）。
    ///
    /// 刻意不用 `contains`：`a-q75-草稿.jpg` 这类中段出现的标签不算产物，
    /// 只有严格贴在文件名尾部（可带序号）才算，避免误伤用户自己的命名习惯。
    private static func matchTag(in name: String, candidates: [String]) -> String? {
        let stem = (name as NSString).deletingPathExtension.lowercased()
        guard !stem.isEmpty else { return nil }

        for tag in candidates {
            let lowerTag = tag.lowercased()
            if stem.hasSuffix("-\(lowerTag)") { return tag }

            // -q75-2 / -q75-12：标签后必须跟非空纯数字段
            guard let range = stem.range(of: "-\(lowerTag)-", options: .backwards) else { continue }
            let tail = stem[range.upperBound...]
            if !tail.isEmpty, tail.allSatisfy(\.isNumber) { return tag }
        }
        return nil
    }
}
