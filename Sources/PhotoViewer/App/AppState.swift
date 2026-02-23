import SwiftUI

@MainActor
@Observable
final class AppState {
    var folderURL: URL?
    var images: [ImageItem] = []
    private(set) var indexByID: [UUID: Int] = [:]
    var focusedIndex: Int?
    var selectedIDs: Set<UUID> = []
    var viewMode: ViewMode = .grid
    var columnCount: Int = 4
    var isLoading = false

    enum ViewMode: Equatable {
        case grid
        case single(index: Int)
    }

    func loadFolder(_ url: URL) async {
        folderURL = url
        isLoading = true
        selectedIDs.removeAll()
        focusedIndex = nil
        viewMode = .grid

        do {
            images = try await FolderScanner.scan(folder: url)
            rebuildIndex()
            if !images.isEmpty {
                focusedIndex = 0
            }
        } catch {
            images = []
            indexByID = [:]
        }

        isLoading = false
    }

    func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func moveFocus(_ direction: MoveCommandDirection) {
        guard !images.isEmpty else { return }
        let current = focusedIndex ?? 0

        switch direction {
        case .left:
            focusedIndex = max(0, current - 1)
        case .right:
            focusedIndex = min(images.count - 1, current + 1)
        case .up:
            let target = current - columnCount
            if target >= 0 { focusedIndex = target }
        case .down:
            let target = current + columnCount
            if target < images.count { focusedIndex = target }
        @unknown default:
            break
        }
    }

    func enterSingleView() {
        guard let idx = focusedIndex, idx < images.count else { return }
        viewMode = .single(index: idx)
    }

    func exitSingleView() {
        if case .single(let idx) = viewMode {
            focusedIndex = idx
        }
        viewMode = .grid
    }

    func navigateSingle(_ offset: Int) {
        if case .single(let idx) = viewMode {
            let newIdx = min(max(idx + offset, 0), images.count - 1)
            viewMode = .single(index: newIdx)
        }
    }

    private func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: images.enumerated().map { ($1.id, $0) })
    }
}
