import AppKit
import ImageIO

// Pure cache — no task management, no scheduling
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [URL: NSImage] = [:]

    func get(_ url: URL) -> NSImage? {
        cache[url]
    }

    func set(_ url: URL, image: NSImage) {
        cache[url] = image
    }

    func clearCache() {
        cache.removeAll()
    }
}

// Concurrency limiter — controls how many thumbnails decode at once.
// When a cell scrolls off screen its .task cancels, which releases the
// slot immediately so newly visible cells jump to the front.
actor ThumbnailSemaphore {
    static let shared = ThumbnailSemaphore(
        limit: max(4, ProcessInfo.processInfo.activeProcessorCount)
    )

    private let limit: Int
    private var running: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func release() {
        if !waiters.isEmpty {
            // Wake the next waiter — slot stays occupied
            let next = waiters.removeFirst()
            next.resume()
        } else {
            running -= 1
        }
    }
}

// Static helper — called from each cell's .task so cancellation propagates
enum ThumbnailGenerator {
    static let thumbnailSize: CGFloat = 200

    static func loadThumbnail(for url: URL) async -> NSImage? {
        // 1. Check cache
        if let cached = await ThumbnailCache.shared.get(url) {
            return cached
        }

        // 2. Wait for a concurrency slot (cancelled tasks release automatically)
        await ThumbnailSemaphore.shared.acquire()

        // If cancelled while waiting, release slot immediately
        guard !Task.isCancelled else {
            await ThumbnailSemaphore.shared.release()
            return nil
        }

        // 3. Generate thumbnail off the main thread
        let image = generateThumbnail(url: url)

        // 4. Release slot
        await ThumbnailSemaphore.shared.release()

        guard !Task.isCancelled else { return nil }

        // 5. Store in cache
        if let image {
            await ThumbnailCache.shared.set(url, image: image)
        }
        return image
    }

    private static func generateThumbnail(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
