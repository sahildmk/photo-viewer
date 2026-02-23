import AppKit
import ImageIO

actor ImageLoader {
    static let shared = ImageLoader()

    private static let maxPixelSize: CGFloat = 2560

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 5
        return c
    }()

    func loadFullSize(url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let image = await Task.detached(priority: .userInitiated) {
            Self.downsampledImage(url: url)
        }.value

        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    private static func downsampledImage(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    nonisolated func prefetch(urls: [URL]) {
        for url in urls {
            Task { _ = await self.loadFullSize(url: url) }
        }
    }
}
