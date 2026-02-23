#!/usr/bin/env swift

// Standalone benchmark — run with: swift benchmark.swift /path/to/photo/folder

import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift benchmark.swift /path/to/photo/folder")
    exit(1)
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
print("Benchmarking: \(folder.path)")

let supportedTypes: Set<UTType> = [.jpeg, .png, .heic, .tiff, .bmp, .gif, .webP]
let gregorian = Calendar(identifier: .gregorian)

func parseExifDate(_ s: String) -> Date? {
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
    guard let year = int(0, 4), let month = int(5, 2), let day = int(8, 2),
          let hour = int(11, 2), let minute = int(14, 2), let second = int(17, 2)
    else { return nil }
    var dc = DateComponents()
    dc.year = year; dc.month = month; dc.day = day
    dc.hour = hour; dc.minute = minute; dc.second = second
    return gregorian.date(from: dc)
}

func exifDateFromURL(for url: URL) -> Date? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
    guard let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
    return parseExifDate(dateStr)
}

func exifDateFromData(_ data: Data) -> Date? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
    guard let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
    return parseExifDate(dateStr)
}

// ── Phase 1a: Enumerate (old — with property prefetch) ──
var t0 = CFAbsoluteTimeGetCurrent()

let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentTypeKey, .contentModificationDateKey]
guard let enumerator = FileManager.default.enumerator(
    at: folder,
    includingPropertiesForKeys: Array(resourceKeys),
    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
) else {
    print("Failed to enumerate folder")
    exit(1)
}
let allURLs = enumerator.allObjects.compactMap { $0 as? URL }

var t1 = CFAbsoluteTimeGetCurrent()
print("Phase 1a — Enum (props):     \(allURLs.count) files in \(String(format: "%.3f", t1 - t0))s")

// ── Phase 1b: Enumerate (new — names only, no stat) ──
t0 = CFAbsoluteTimeGetCurrent()

let fastContents = (try? FileManager.default.contentsOfDirectory(
    at: folder,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
)) ?? []

t1 = CFAbsoluteTimeGetCurrent()
print("Phase 1b — Enum (no props):  \(fastContents.count) files in \(String(format: "%.3f", t1 - t0))s")

// ── Phase 2a: Filter by UTType (old) ──
t0 = CFAbsoluteTimeGetCurrent()

var imageURLs: [(url: URL, modDate: Date?)] = []
for fileURL in allURLs {
    guard
        let values = try? fileURL.resourceValues(forKeys: resourceKeys),
        values.isRegularFile == true,
        let contentType = values.contentType,
        supportedTypes.contains(where: { contentType.conforms(to: $0) })
    else { continue }
    imageURLs.append((fileURL, values.contentModificationDate))
}

t1 = CFAbsoluteTimeGetCurrent()
print("Phase 2a — Filter (UTType):  \(imageURLs.count) images in \(String(format: "%.3f", t1 - t0))s")

// ── Phase 2b: Filter by extension (new) ──
t0 = CFAbsoluteTimeGetCurrent()

let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
let fastImageURLs = fastContents.filter { imageExts.contains($0.pathExtension.lowercased()) }

t1 = CFAbsoluteTimeGetCurrent()
print("Phase 2b — Filter (ext):     \(fastImageURLs.count) images in \(String(format: "%.3f", t1 - t0))s")

let total = imageURLs.count

// ── Phase 3a: EXIF via CGImageSourceCreateWithURL (sequential sample) ──
let sampleSize = min(200, total)
t0 = CFAbsoluteTimeGetCurrent()

var exifHits = 0
for i in 0..<sampleSize {
    if exifDateFromURL(for: imageURLs[i].url) != nil { exifHits += 1 }
}

t1 = CFAbsoluteTimeGetCurrent()
let perFile = sampleSize > 0 ? (t1 - t0) / Double(sampleSize) * 1000 : 0
print("Phase 3a — URL sequential:   \(sampleSize) files in \(String(format: "%.3f", t1 - t0))s (\(String(format: "%.2f", perFile))ms/file, \(exifHits) had EXIF)")

// ── Phase 3b: EXIF via CGImageSourceCreateWithURL (parallel, full set) ──
t0 = CFAbsoluteTimeGetCurrent()

var dates3b = [Date?](repeating: nil, count: total)
dates3b.withUnsafeMutableBufferPointer { buffer in
    nonisolated(unsafe) let base = buffer.baseAddress!
    DispatchQueue.concurrentPerform(iterations: total) { idx in
        (base + idx).pointee = exifDateFromURL(for: imageURLs[idx].url) ?? imageURLs[idx].modDate
    }
}

t1 = CFAbsoluteTimeGetCurrent()
print("Phase 3b — URL parallel:     \(total) files in \(String(format: "%.3f", t1 - t0))s")

// ── Phase 3c: Sequential header read into memory, then parallel EXIF parse ──
let headerSize = 128 * 1024  // 128KB covers EXIF for JPEG, HEIC, most RAW

t0 = CFAbsoluteTimeGetCurrent()

// Step 1: Sequential I/O — read just the file header from each file.
// A single sequential reader is optimal for SD cards / external drives.
var headers = [Data?](repeating: nil, count: total)
for idx in 0..<total {
    if let fh = try? FileHandle(forReadingFrom: imageURLs[idx].url) {
        headers[idx] = fh.readData(ofLength: headerSize)
        try? fh.close()
    }
}

let tRead = CFAbsoluteTimeGetCurrent()

// Step 2: Parallel EXIF parse from memory — CPU-bound, all cores help
var dates3c = [Date?](repeating: nil, count: total)
dates3c.withUnsafeMutableBufferPointer { buffer in
    nonisolated(unsafe) let base = buffer.baseAddress!
    DispatchQueue.concurrentPerform(iterations: total) { idx in
        if let data = headers[idx] {
            (base + idx).pointee = exifDateFromData(data)
        }
    }
}

let tParse = CFAbsoluteTimeGetCurrent()

let hits3c = dates3c.compactMap({ $0 }).count
print("Phase 3c — Read headers:     \(String(format: "%.3f", tRead - t0))s  |  Parse EXIF: \(String(format: "%.3f", tParse - tRead))s  |  Total: \(String(format: "%.3f", tParse - t0))s (\(hits3c) had EXIF)")

// Free header memory
headers = []

// ── Phase 3d: Mod-date only (no EXIF) ──
t0 = CFAbsoluteTimeGetCurrent()

// Already have mod dates from Phase 2 — this is essentially free
let modDates = imageURLs.map { $0.modDate ?? Date.distantPast }

t1 = CFAbsoluteTimeGetCurrent()
print("Phase 3d — Mod-date only:    \(total) files in \(String(format: "%.3f", t1 - t0))s")

// ── Phase 4: Sort ──
struct DummyItem: Identifiable {
    let id = UUID()
    let url: URL
    let captureDate: Date
    var fileName: String { url.lastPathComponent }
}

t0 = CFAbsoluteTimeGetCurrent()

var items = (0..<total).map { i in
    DummyItem(url: imageURLs[i].url, captureDate: dates3b[i] ?? modDates[i])
}
items.sort {
    if $0.captureDate == $1.captureDate {
        return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
    }
    return $0.captureDate < $1.captureDate
}

t1 = CFAbsoluteTimeGetCurrent()
print("Phase 4 — Sort:              \(total) items in \(String(format: "%.3f", t1 - t0))s")

// ── Phase 5: Group by date ──
t0 = CFAbsoluteTimeGetCurrent()

var groupCount = 0
var i = 0
while i < items.count {
    let day = gregorian.dateComponents([.year, .month, .day], from: items[i].captureDate)
    while i < items.count &&
          gregorian.dateComponents([.year, .month, .day], from: items[i].captureDate) == day {
        i += 1
    }
    groupCount += 1
}

t1 = CFAbsoluteTimeGetCurrent()
print("Phase 5 — Group by date:     \(groupCount) groups in \(String(format: "%.3f", t1 - t0))s")

print("\nDone.")
