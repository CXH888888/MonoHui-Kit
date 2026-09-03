import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// 固定最大尺寸的缩略图预览：完整显示图片（不裁切），最长边不超过 size。
/// 降采样解码 + 缓存，避免 body 重算时反复读盘解码全尺寸大图。
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat
    var cornerRadius: CGFloat = 12

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.appleSurface2
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc.fill")
                    .foregroundStyle(Color.appleSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            image = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: size * 2)
        }
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for url: URL, maxPixel: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let pixel = Int(maxPixel)
        let image = await Task.detached(priority: .userInitiated) {
            Self.loadThumbnail(url: url, maxPixel: pixel)
        }.value
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private static func loadThumbnail(url: URL, maxPixel: Int) -> NSImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        // ImageIO 解不了的格式（如部分 PSD/PSB）回退 NSImage
        return NSImage(contentsOf: url)
    }
}
