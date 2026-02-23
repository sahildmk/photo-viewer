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

    /// Indices radiating outward from `center`: [c, c-1, c+1, c-2, c+2, ...]
    static func proximityOrder(from center: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var result = [Int]()
        result.reserveCapacity(count)
        result.append(center)
        for offset in 1..<count {
            let before = center - offset
            let after = center + offset
            if before >= 0 { result.append(before) }
            if after < count { result.append(after) }
            if result.count == count { break }
        }
        return result
    }

    /// Generate all thumbnails in the background, sequentially.
    /// Sequential reads are optimal for SD cards / slow I/O (no contention).
    /// Skips any that are already cached (e.g. loaded by visible cells).
    /// URLs are processed in proximity order radiating from `centerIndex`.
    static func preloadAll(
        urls: [URL],
        centerIndex: Int = 0,
        maxConcurrent: Int? = nil
    ) async {
        let ordered = proximityOrder(from: centerIndex, count: urls.count)
        for idx in ordered {
            guard !Task.isCancelled else { return }
            let url = urls[idx]
            if await ThumbnailCache.shared.get(url) != nil { continue }
            let image = readAndDecode(url: url)
            guard !Task.isCancelled else { return }
            if let image {
                await ThumbnailCache.shared.set(url, image: image)
            }
        }
    }

    /// Sequential read with header-first fast path for embedded EXIF thumbnails.
    /// 256KB covers embedded thumbnails in camera JPEGs/RAW without reading the full file.
    private static func readAndDecode(url: URL) -> NSImage? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        // Fast path: 256KB covers embedded EXIF thumbnails in camera JPEGs/RAW
        let header = fh.readData(ofLength: 256 * 1024)
        if let image = decodeThumbnail(from: header) {
            return image
        }
        // Slow path: full file for PNGs, screenshots, no embedded thumbnail
        let rest = fh.readDataToEndOfFile()
        return decodeThumbnail(from: header + rest)
    }

    /// Data-based thumbnail decode using IfAbsent to prefer embedded thumbnails.
    private static func decodeThumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func generateThumbnail(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
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
