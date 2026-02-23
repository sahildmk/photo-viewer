import Foundation

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var fileName: String { url.lastPathComponent }
}
