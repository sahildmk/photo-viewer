import Foundation

struct ImageItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let captureDate: Date
    var fileName: String { url.lastPathComponent }
}
