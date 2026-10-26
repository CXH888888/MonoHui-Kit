import Foundation

enum CompressionFormat: String, CaseIterable, Identifiable, Codable {
    case png, jpeg, gif, webp, avif, jxl, svg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .gif: return "GIF"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .jxl: return "JPEG XL"
        case .svg: return "SVG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .gif: return "gif"
        case .webp: return "webp"
        case .avif: return "avif"
        case .jxl: return "jxl"
        case .svg: return "svg"
        }
    }

    var utType: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .gif: return "com.compuserve.gif"
        case .webp: return "org.webmproject.webp"
        case .avif: return "public.avif"
        case .jxl: return "public.jxl"
        case .svg: return "public.svg-image"
        }
    }

    static func from(fileExtension ext: String) -> CompressionFormat? {
        let lower = ext.lowercased()
        for format in allCases {
            if format.fileExtension == lower || format.rawValue == lower {
                return format
            }
        }
        return nil
    }
}
