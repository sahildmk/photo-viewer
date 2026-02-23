import Foundation

struct FileCopyService {
    static func copyFiles(from sources: [URL], to destination: URL) async throws -> Int {
        var copied = 0
        for source in sources {
            let dest = destination.appendingPathComponent(source.lastPathComponent)
            let finalDest = uniqueDestination(dest)
            try FileManager.default.copyItem(at: source, to: finalDest)
            copied += 1
        }
        return copied
    }

    private static func uniqueDestination(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }

        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        var candidate = url

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
