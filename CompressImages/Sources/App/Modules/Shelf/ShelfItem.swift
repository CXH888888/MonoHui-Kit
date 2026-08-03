import Foundation

/// 中转站文件项数据模型
struct ShelfItem: Identifiable {
    let id = UUID()
    var url: URL
    var isLocked: Bool = false
    var transformStatus: TransformStatus = .none
    var transformFormat: String? = nil  // 转换后格式（如 "PNG"），用于显示 badge

    /// 压缩后大小（字节）。compressAndShelf 完成后设置，用于底部显示 "65KB（-78%）"
    var compressedSize: UInt64? = nil
    /// 压缩节省百分比（0-100）。compressAndShelf 完成后设置
    var savedPercent: Double? = nil

    /// 源应用 bundleId（拖入时识别）
    var sourceBundleId: String? = nil

    /// 文件原始位置（本地文件移入 cacheDir 时记录，用于"放回原位"）
    /// nil 表示该文件无法放回原位（应用拖入的临时文件）
    var originalURL: URL? = nil

    enum TransformStatus: Equatable {
        case none
        case converting
        case completed
        case failed(String)
    }

    var fileName: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    var fileSize: UInt64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue {
            // 文件夹：递归计算所有内容总大小
            return Self.directorySize(at: url)
        }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    /// 递归计算目录总大小
    private static func directorySize(at url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total &+= UInt64(size)
            }
        }
        return total
    }

    /// 格式化文件大小（用系统标准 ByteCountFormatter，与访达一致）
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    /// 是否为图片类型（扩充：含 SVG、RAW、HEIF 等）
    var isImage: Bool {
        FileTypeClassifier.shared.isImage(ext: fileExtension)
    }

    /// 是否为视频
    var isVideo: Bool {
        FileTypeClassifier.shared.isVideo(ext: fileExtension)
    }

    /// 是否为音频
    var isAudio: Bool {
        FileTypeClassifier.shared.isAudio(ext: fileExtension)
    }

    /// 是否为文件夹
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// 文件类型分类器（统一管理所有格式识别，避免散落多处不一致）
final class FileTypeClassifier {
    static let shared = FileTypeClassifier()
    private init() {}

    private let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp",
        "heic", "heif", "psd", "ai", "svg", "raw", "cr2", "nef", "arw",
        "dng", "ico", "icns", "jp2", "hdr", "exr"
    ]

    private let videoExts: Set<String> = [
        "mp4", "mov", "avi", "mkv", "m4v", "flv", "wmv", "mpeg", "mpg",
        "webm", "3gp", "3g2", "mts", "m2ts", "vob", "f4v"
    ]

    private let audioExts: Set<String> = [
        "mp3", "wav", "m4a", "flac", "aac", "ogg", "wma", "aiff", "aif",
        "alac", "opus", "amr", "mka"
    ]

    private let archiveExts: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso",
        "pkg", "sitx", "lz"
    ]

    private let codeExts: Set<String> = [
        "swift", "py", "js", "ts", "jsx", "tsx", "html", "css", "scss", "less",
        "json", "xml", "yaml", "yml", "java", "c", "cpp", "h", "hpp", "cc",
        "go", "rs", "rb", "php", "sh", "bash", "zsh", "sql", "vue", "kt", "dart"
    ]

    private let docExts: Set<String> = [
        "pdf", "doc", "docx", "rtf", "txt", "md", "pages", "odt", "epub"
    ]

    private let sheetExts: Set<String> = [
        "xls", "xlsx", "csv", "numbers", "ods"
    ]

    private let keyExts: Set<String> = [
        "ppt", "pptx", "key", "odp"
    ]

    func isImage(ext: String) -> Bool { imageExts.contains(ext.lowercased()) }
    func isVideo(ext: String) -> Bool { videoExts.contains(ext.lowercased()) }
    func isAudio(ext: String) -> Bool { audioExts.contains(ext.lowercased()) }
    func isArchive(ext: String) -> Bool { archiveExts.contains(ext.lowercased()) }
    func isCode(ext: String) -> Bool { codeExts.contains(ext.lowercased()) }
    func isDoc(ext: String) -> Bool { docExts.contains(ext.lowercased()) }
    func isSheet(ext: String) -> Bool { sheetExts.contains(ext.lowercased()) }
    func isKey(ext: String) -> Bool { keyExts.contains(ext.lowercased()) }

    /// 格式分类枚举
    enum Category {
        case image, video, audio, archive, code, doc, sheet, key, folder, other
    }

    /// 获取文件扩展名对应的分类
    func category(ext: String, isDirectory: Bool = false) -> Category {
        if isDirectory || ext.isEmpty { return .folder }
        let e = ext.lowercased()
        if imageExts.contains(e) { return .image }
        if videoExts.contains(e) { return .video }
        if audioExts.contains(e) { return .audio }
        if archiveExts.contains(e) { return .archive }
        if codeExts.contains(e) { return .code }
        if docExts.contains(e) { return .doc }
        if sheetExts.contains(e) { return .sheet }
        if keyExts.contains(e) { return .key }
        return .other
    }

    /// 获取分类对应的 SF Symbol（兜底用）
    func sfSymbol(ext: String, isDirectory: Bool = false) -> String {
        switch category(ext: ext, isDirectory: isDirectory) {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .archive: return "doc.zipper"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .doc: return "doc.richtext"
        case .sheet: return "tablecells"
        case .key: return "slider.horizontal.3"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }

    /// 获取分类对应的标签颜色
    func labelColor(ext: String, isDirectory: Bool = false) -> (Double, Double, Double) {
        switch category(ext: ext, isDirectory: isDirectory) {
        case .image: return (0.2, 0.6, 0.9)      // 蓝色
        case .video: return (0.85, 0.3, 0.3)     // 红色
        case .audio: return (0.6, 0.4, 0.9)      // 紫色
        case .archive: return (0.85, 0.6, 0.2)   // 橙色
        case .code: return (0.3, 0.7, 0.5)       // 青绿
        case .doc: return (0.85, 0.2, 0.4)       // 粉红
        case .sheet: return (0.2, 0.7, 0.4)      // 绿色
        case .key: return (0.9, 0.4, 0.2)        // 橙红
        case .folder: return (0.2, 0.6, 0.9)     // 蓝色
        case .other: return (0.6, 0.6, 0.6)      // 灰色
        }
    }
}
