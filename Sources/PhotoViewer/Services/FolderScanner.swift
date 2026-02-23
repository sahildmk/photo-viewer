import Foundation
import UniformTypeIdentifiers

struct FolderScanner {
    static let supportedTypes: Set<UTType> = [.jpeg, .png, .heic, .tiff, .bmp, .gif, .webP]

    static func scan(folder: URL) async throws -> [ImageItem] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentTypeKey]

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }

        var items: [ImageItem] = []
        for fileURL in allURLs {
            guard
                let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                values.isRegularFile == true,
                let contentType = values.contentType,
                supportedTypes.contains(where: { contentType.conforms(to: $0) })
            else { continue }
            items.append(ImageItem(url: fileURL))
        }

        items.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        return items
    }
}
