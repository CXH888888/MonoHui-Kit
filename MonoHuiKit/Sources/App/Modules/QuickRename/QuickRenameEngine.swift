import Foundation

struct QuickRenameEngine {

    // MARK: - 创建锁（防止 rename() 重复触发）
    private static let createLock = NSLock()
    private static var createInProgress = false

    static func tryAcquireCreateLock() -> Bool {
        createLock.lock()
        defer { createLock.unlock() }
        if createInProgress { return false }
        createInProgress = true
        return true
    }

    static func releaseCreateLock() {
        createLock.lock()
        defer { createLock.unlock() }
        createInProgress = false
    }

    // MARK: - 默认状态标签
    static let defaultStatuses = ["草稿", "定稿", "转曲", "审核", "归档"]

    // MARK: - 文件名解析结果
    struct ParsedFileName {
        var date: String        // 日期段（如 "260806"），未识别为空
        var dateFormat: String  // 匹配到的日期格式（"yyMMdd"/"MMdd"/"yyMM"），未识别为空
        var channel: String     // 渠道段（多选用 - 连接，如 "线上-门店"），未识别为空
        var name: String        // 名字段（必填，未识别则用整个去扩展名文件名）
        var version: Int?       // 版本号数字，未识别为 nil
        var status: String      // 状态段，未识别为空
    }

    // MARK: - 文件名解析
    /// 解析原文件名，返回各字段
    /// 解析策略：按 - 分割，从首尾两端识别日期/渠道/版本/状态，中间剩余为名字
    static func parse(fileName: String, customChannels: [String], customStatuses: [String]) -> ParsedFileName {
        // 去掉扩展名
        let nsName = fileName as NSString
        let nameWithoutExt = nsName.deletingPathExtension

        // 按 - 分割
        let segments = nameWithoutExt.components(separatedBy: "-")
        guard segments.count >= 1 else {
            return ParsedFileName(date: "", dateFormat: "", channel: "", name: nameWithoutExt, version: nil, status: "")
        }

        // 单段：整个作为名字
        if segments.count == 1 {
            return ParsedFileName(date: "", dateFormat: "", channel: "", name: segments[0], version: nil, status: "")
        }

        // 正向识别：第 1 段日期、第 2 段渠道
        var startIndex = 0
        var date = ""
        var dateFormat = ""
        var channel = ""

        if let detected = detectDateFormat(segments[0]) {
            date = segments[0]
            dateFormat = detected
            startIndex = 1
            // 渠道段：从第 2 段起，连续命中白名单的段都算渠道（多选用 - 连接）
            var channelParts: [String] = []
            while startIndex < segments.count {
                let ch = segments[startIndex]
                guard isChannelSegment(ch, customChannels: customChannels) else { break }
                // 至少给名字留一段；第一段渠道除外，兼容「1027-线上」这种没有名字的老格式
                if !channelParts.isEmpty && startIndex == segments.count - 1 { break }
                channelParts.append(ch)
                startIndex += 1
            }
            channel = channelParts.joined(separator: "-")
        }

        // 剩余段
        let remaining = Array(segments[startIndex...])
        guard !remaining.isEmpty else {
            return ParsedFileName(date: date, dateFormat: dateFormat, channel: channel, name: "", version: nil, status: "")
        }

        // 反向识别：状态、版本
        var endIndex = remaining.count - 1
        var status = ""
        var version: Int? = nil

        // 最后 1 段：先试方括号状态，再试纯文本状态，再试 "vN[状态]" 连写形式
        let last = remaining[endIndex]
        if let bracketStatus = detectBracketStatus(last) {
            status = bracketStatus
            endIndex -= 1
        } else if isStatus(last, customStatuses: customStatuses) {
            // 提取纯状态名（去掉 macOS 重名后缀 "定稿 2" → "定稿"）
            status = extractStatusName(last)
            endIndex -= 1
        } else if let combined = detectVersionAndStatus(last, customStatuses: customStatuses) {
            // 识别 "v3[草稿]" 这种连写形式
            version = combined.version
            status = combined.status
            endIndex -= 1
        }

        // 倒数第 2 段：版本号（如果上面没识别到版本）
        if version == nil && endIndex >= 0 {
            if let v = detectVersion(remaining[endIndex]) {
                version = v
                endIndex -= 1
            }
        }

        // 中间剩余：名字
        let name: String
        if endIndex >= 0 {
            name = Array(remaining[0...endIndex]).joined(separator: "-")
        } else {
            name = ""
        }

        // 回退：如果第 1 段不是日期 或 第 2 段不是渠道（即不符合系统格式）
        // 且 name 为空，则整个文件名（去扩展名）作为名字
        if date.isEmpty && channel.isEmpty && name.isEmpty {
            return ParsedFileName(date: "", dateFormat: "", channel: "", name: nameWithoutExt, version: nil, status: "")
        }

        return ParsedFileName(date: date, dateFormat: dateFormat, channel: channel, name: name, version: version, status: status)
    }

    // MARK: - 版本号递增
    /// 识别到版本号则 +1，无则返回 1
    static func nextVersion(current: Int?) -> Int {
        (current ?? 0) + 1
    }

    // MARK: - 渠道段识别
    /// 单个片段是否属于渠道白名单（内置两个 + 用户自定义标签）
    private static func isChannelSegment(_ segment: String, customChannels: [String]) -> Bool {
        segment == "线上" || segment == "线下" || customChannels.contains(segment)
    }

    // MARK: - 日期格式识别
    /// 尝试匹配 yyMMdd(6位) / MMdd(4位月日) / yyMM(4位年月)
    /// 4 位数字有歧义，默认按 MMdd 处理
    private static func detectDateFormat(_ segment: String) -> String? {
        if segment.count == 6 && segment.allSatisfy({ $0.isNumber }) {
            return "yyMMdd"
        }
        if segment.count == 4 && segment.allSatisfy({ $0.isNumber }) {
            return "MMdd"
        }
        return nil
    }

    // MARK: - 版本号识别
    /// 匹配 [vV]\d+ 格式
    private static func detectVersion(_ segment: String) -> Int? {
        let trimmed = segment.lowercased()
        guard trimmed.hasPrefix("v") else { return nil }
        let numStr = String(trimmed.dropFirst())
        return Int(numStr)
    }

    // MARK: - 方括号状态识别
    /// 匹配 ^[\[【］](.+)[\]】］]$ 格式（支持半角[]、全角【】、全角［］）
    /// 也支持 macOS 重名后缀： "[草稿] 2"
    private static func detectBracketStatus(_ segment: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "^[\\[【［](.+?)[\\]】］](?:\\s*\\d+)?$"
        ) else { return nil }
        let range = NSRange(segment.startIndex..., in: segment)
        guard let match = regex.firstMatch(in: segment, range: range),
              match.numberOfRanges >= 2,
              let sRange = Range(match.range(at: 1), in: segment) else { return nil }
        let inner = String(segment[sRange])
        return inner.isEmpty ? nil : inner
    }

    // MARK: - 版本号+状态连写识别
    /// 匹配 "v3[草稿]" / "V2[定稿]" 这种连写形式
    /// 也支持 macOS 重名后缀： "v3[草稿] 2" / "v1[定稿] 3"
    struct VersionStatusCombo {
        let version: Int
        let status: String
    }
    private static func detectVersionAndStatus(_ segment: String, customStatuses: [String]) -> VersionStatusCombo? {
        // 用正则匹配：^[vV](\d+)[\[【［](.+?)[\]】］](?:\s*\d+)?$
        guard let regex = try? NSRegularExpression(
            pattern: "^[vV](\\d+)[\\[【［](.+?)[\\]】］](?:\\s*\\d+)?$"
        ) else { return nil }
        let range = NSRange(segment.startIndex..., in: segment)
        guard let match = regex.firstMatch(in: segment, range: range),
              match.numberOfRanges >= 3,
              let vRange = Range(match.range(at: 1), in: segment),
              let sRange = Range(match.range(at: 2), in: segment) else { return nil }
        guard let version = Int(segment[vRange]) else { return nil }
        let statusStr = String(segment[sRange])
        guard !statusStr.isEmpty else { return nil }
        return VersionStatusCombo(version: version, status: statusStr)
    }

    // MARK: - 纯文本状态识别
    /// 支持纯状态名（"定稿"）和 macOS 重名后缀（"定稿 2"）
    private static func isStatus(_ segment: String, customStatuses: [String]) -> Bool {
        if defaultStatuses.contains(segment) || customStatuses.contains(segment) {
            return true
        }
        // 检查 "状态名 数字" 格式（macOS 重名后缀）
        guard let regex = try? NSRegularExpression(pattern: "^(.+?)\\s+\\d+$") else { return false }
        let range = NSRange(segment.startIndex..., in: segment)
        if let match = regex.firstMatch(in: segment, range: range),
           match.numberOfRanges >= 2,
           let sRange = Range(match.range(at: 1), in: segment) {
            let base = String(segment[sRange])
            return defaultStatuses.contains(base) || customStatuses.contains(base)
        }
        return false
    }

    /// 从可能带 macOS 重名后缀的段中提取纯状态名（"定稿 2" → "定稿"）
    private static func extractStatusName(_ segment: String) -> String {
        if defaultStatuses.contains(segment) || !segment.contains(" ") {
            return segment
        }
        guard let regex = try? NSRegularExpression(pattern: "^(.+?)\\s+\\d+$") else { return segment }
        let range = NSRange(segment.startIndex..., in: segment)
        if let match = regex.firstMatch(in: segment, range: range),
           match.numberOfRanges >= 2,
           let sRange = Range(match.range(at: 1), in: segment) {
            return String(segment[sRange])
        }
        return segment
    }

    // MARK: - 生成新文件名（不含扩展名）
    /// 格式：日期-渠道-名字-[版本号][[状态]]
    /// versionEnabled 为 false 时不追加版本号
    /// status 为空时不追加，非空时用方括号包裹紧跟版本号后
    static func buildName(date: String, channel: String, name: String, version: Int?, versionEnabled: Bool, status: String) -> String {
        var parts = [date, channel, name]
        if versionEnabled, let v = version {
            parts.append("v\(v)")
        }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "-")
        if !status.isEmpty {
            return "\(joined)[\(status)]"
        }
        return joined
    }

    // MARK: - 日期格式化（复用 DateFolderEngine 的逻辑）
    static func formatName(format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }

    // MARK: - 执行重命名
    /// 重命名文件，保留扩展名，处理重名冲突
    static func rename(url: URL, newName: String) throws -> URL {
        let ext = url.pathExtension
        let fullNewName = ext.isEmpty ? newName : "\(newName).\(ext)"
        let directory = url.deletingLastPathComponent()
        let targetURL = resolveUniqueURL(directory: directory, name: fullNewName)

        // 目标与源相同时直接返回
        if targetURL == url {
            return url
        }

        try FileManager.default.moveItem(at: url, to: targetURL)
        return targetURL
    }

    // MARK: - 重名冲突处理
    /// 若同名已存在，追加 " 2"、" 3"...（注意是空格 + 数字）
    static func resolveUniqueURL(directory: URL, name: String) -> URL {
        let base = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: base.path) {
            return base
        }
        let nsName = name as NSString
        let nameOnly = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        var i = 2
        while true {
            let candidateName = ext.isEmpty ? "\(nameOnly) \(i)" : "\(nameOnly) \(i).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            i += 1
        }
    }
}
