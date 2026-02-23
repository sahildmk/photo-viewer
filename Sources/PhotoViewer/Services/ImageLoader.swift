import AppKit

actor ImageLoader {
    static let shared = ImageLoader()

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
            NSImage(contentsOf: url)
        }.value

        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    nonisolated func prefetch(urls: [URL]) {
        for url in urls {
            Task { _ = await self.loadFullSize(url: url) }
        }
    }
}
