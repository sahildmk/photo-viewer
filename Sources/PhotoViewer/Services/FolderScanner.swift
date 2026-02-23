import Foundation
import ImageIO
import os

struct FolderScanner {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif",
        "tiff", "tif", "bmp", "gif", "webp",
    ]

    private static let headerSize = 128 * 1024 // 128KB — covers EXIF for JPEG, HEIC, most RAW

    static func scan(folder: URL, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [ImageItem] {
        await Task.detached(priority: .userInitiated) {
            // Phase 1: Fast enumerate — names only, no per-file stat() calls.
            // On external drives / SD cards, stat() per file dominates enumeration time.
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return [] }

            // Phase 2: Filter by extension — pure string check, zero I/O.
            let imageURLs = contents.filter {
                supportedExtensions.contains($0.pathExtension.lowercased())
            }

            let total = imageURLs.count
            progress?(0, total)
            guard total > 0 else { return [] }

            // Phase 3a: Read file headers sequentially into memory.
            // Sequential single-reader I/O is optimal for SD cards / USB drives
            // where concurrent reads cause contention on the single I/O channel.
            var headers = [Data?](repeating: nil, count: total)
            for idx in 0..<total {
                if let fh = try? FileHandle(forReadingFrom: imageURLs[idx]) {
                    headers[idx] = fh.readData(ofLength: headerSize)
                    try? fh.close()
                }
                if (idx + 1) % 100 == 0 || idx == total - 1 {
                    progress?(idx + 1, total)
                }
            }

            // Phase 3b: Parse EXIF from memory buffers in parallel — CPU-bound, all cores help.
            var slots = [ImageItem?](repeating: nil, count: total)

            slots.withUnsafeMutableBufferPointer { buffer in
                nonisolated(unsafe) let base = buffer.baseAddress!
                DispatchQueue.concurrentPerform(iterations: total) { idx in
                    let url = imageURLs[idx]
                    var captureDate: Date?
                    if let data = headers[idx] {
                        captureDate = exifDateFromData(data)
                    }
                    if captureDate == nil {
                        // Fallback: file modification date (stat call, rare for camera photos)
                        captureDate = (try? url.resourceValues(
                            forKeys: [.contentModificationDateKey]
                        ))?.contentModificationDate
                    }
                    (base + idx).pointee = ImageItem(url: url, captureDate: captureDate ?? .distantPast)
                }
            }
            headers = [] // release header memory

            var items = slots.compactMap { $0 }
            items.sort {
                if $0.captureDate == $1.captureDate {
                    return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
                }
                return $0.captureDate < $1.captureDate
            }
            return items
        }.value
    }

    private static func exifDateFromData(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        guard let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return parseExifDate(dateStr)
    }

    private static func parseExifDate(_ s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 19 else { return nil }

        func int(_ start: Int, _ len: Int) -> Int? {
            var v = 0
            for i in start..<(start + len) {
                let d = Int(u[i]) - 48
                guard d >= 0, d <= 9 else { return nil }
                v = v * 10 + d
            }
            return v
        }

        guard let year = int(0, 4),
              let month = int(5, 2),
              let day = int(8, 2),
              let hour = int(11, 2),
              let minute = int(14, 2),
              let second = int(17, 2)
        else { return nil }

        var dc = DateComponents()
        dc.year = year
        dc.month = month
        dc.day = day
        dc.hour = hour
        dc.minute = minute
        dc.second = second
        return gregorian.date(from: dc)
    }

    private static let gregorian = Calendar(identifier: .gregorian)
}
