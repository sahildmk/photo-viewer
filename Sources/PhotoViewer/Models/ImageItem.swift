import Foundation

struct ImageItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    var fileName: String { url.lastPathComponent }
}
