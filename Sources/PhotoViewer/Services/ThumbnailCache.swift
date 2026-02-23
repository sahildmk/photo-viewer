import AppKit
import ImageIO

// Pure cache — no task management, no scheduling
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 500
        return c
    }()

    func get(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ url: URL, image: NSImage) {
        cache.setObject(image, forKey: url as NSURL)
    }

    func clearCache() {
        cache.removeAllObjects()
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
    private var paused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    /// Block new acquisitions so full-size image loads get priority.
    func pause() {
        paused = true
    }

    /// Allow thumbnail generation to resume.
    func resume() {
        paused = false
        let waiting = pauseWaiters
        pauseWaiters = []
        for cont in waiting {
            cont.resume()
        }
    }

    func acquire() async {
        // While paused, hold off new thumbnail work
        while paused {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if paused {
                    pauseWaiters.append(cont)
                } else {
                    cont.resume()
                }
            }
        }

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

    /// Generate all thumbnails in the background, in parallel.
    /// Skips any that are already cached (e.g. loaded by visible cells).
    static func preloadAll(urls: [URL]) async {
        let maxConcurrent = max(4, ProcessInfo.processInfo.activeProcessorCount)

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for url in urls {
                // Limit concurrent decodings
                if running >= maxConcurrent {
                    await group.next()
                    running -= 1
                }
                guard !Task.isCancelled else { return }
                if await ThumbnailCache.shared.get(url) != nil { continue }

                group.addTask {
                    let image = generateThumbnail(url: url)
                    guard !Task.isCancelled else { return }
                    if let image {
                        await ThumbnailCache.shared.set(url, image: image)
                    }
                }
                running += 1
            }
        }
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
