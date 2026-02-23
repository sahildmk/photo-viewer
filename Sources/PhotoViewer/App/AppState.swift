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
    var loadingProgress: Double = 0
    var loadingTotal: Int = 0
    var dateGroups: [DateGroup] = []
    private var groupMembership: [(groupIndex: Int, localIndex: Int)] = []
    private var preloadTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    enum ViewMode: Equatable {
        case grid
        case single(index: Int)
    }

    func loadFolder(_ url: URL) async {
        preloadTask?.cancel()
        folderURL = url
        isLoading = true
        loadingProgress = 0
        loadingTotal = 0
        selectedIDs.removeAll()
        focusedIndex = nil
        viewMode = .grid

        do {
            images = try await FolderScanner.scan(folder: url) { [weak self] processed, total in
                Task { @MainActor [weak self] in
                    self?.loadingTotal = total
                    self?.loadingProgress = Double(processed) / Double(max(total, 1))
                }
            }
            rebuildIndex()
            rebuildDateGroups()
            if !images.isEmpty {
                focusedIndex = 0
            }
        } catch {
            images = []
            indexByID = [:]
            dateGroups = []
            groupMembership = []
        }

        isLoading = false

        restartPreload(centerIndex: 0)
    }

    func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func toggleGroupSelection(groupIndex: Int) {
        guard groupIndex < dateGroups.count else { return }
        let group = dateGroups[groupIndex]
        let groupIDs = images[group.range].map(\.id)
        let allSelected = groupIDs.allSatisfy { selectedIDs.contains($0) }
        if allSelected {
            for id in groupIDs { selectedIDs.remove(id) }
        } else {
            for id in groupIDs { selectedIDs.insert(id) }
        }
    }

    func isGroupFullySelected(_ groupIndex: Int) -> Bool {
        guard groupIndex < dateGroups.count else { return false }
        let group = dateGroups[groupIndex]
        return images[group.range].allSatisfy { selectedIDs.contains($0.id) }
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
            focusedIndex = navigateVertical(from: current, direction: -1)
        case .down:
            focusedIndex = navigateVertical(from: current, direction: 1)
        @unknown default:
            break
        }

        if let focusedIndex {
            restartPreload(centerIndex: focusedIndex, debounce: true)
        }
    }

    func enterSingleView() {
        guard let idx = focusedIndex, idx < images.count else { return }
        viewMode = .single(index: idx)
        restartPreload(centerIndex: idx, maxConcurrent: 1)
    }

    func exitSingleView() {
        if case .single(let idx) = viewMode {
            focusedIndex = idx
            restartPreload(centerIndex: idx)
        }
        viewMode = .grid
    }

    func navigateSingle(_ offset: Int) {
        if case .single(let idx) = viewMode {
            let newIdx = min(max(idx + offset, 0), images.count - 1)
            viewMode = .single(index: newIdx)
            restartPreload(centerIndex: newIdx, maxConcurrent: 1, debounce: true)
        }
    }

    func restartPreload(centerIndex: Int, maxConcurrent: Int? = nil, debounce: Bool = false) {
        debounceTask?.cancel()
        debounceTask = nil

        let urls = images.map(\.url)
        guard !urls.isEmpty else { return }

        if debounce {
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.launchPreload(urls: urls, centerIndex: centerIndex, maxConcurrent: maxConcurrent)
                }
            }
        } else {
            launchPreload(urls: urls, centerIndex: centerIndex, maxConcurrent: maxConcurrent)
        }
    }

    // MARK: - Private

    private func launchPreload(urls: [URL], centerIndex: Int, maxConcurrent: Int?) {
        preloadTask?.cancel()
        let center = min(max(centerIndex, 0), urls.count - 1)
        let concurrency = maxConcurrent
        preloadTask = Task.detached(priority: .utility) {
            await ThumbnailGenerator.preloadAll(
                urls: urls,
                centerIndex: center,
                maxConcurrent: concurrency
            )
        }
    }

    private func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: images.enumerated().map { ($1.id, $0) })
    }

    private func rebuildDateGroups() {
        let calendar = Calendar.current
        var groups: [DateGroup] = []
        var membership: [(groupIndex: Int, localIndex: Int)] = []

        var i = 0
        while i < images.count {
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: images[i].captureDate)
            let start = i
            while i < images.count
                && calendar.dateComponents([.year, .month, .day], from: images[i].captureDate) == dayComponents
            {
                i += 1
            }
            let groupIndex = groups.count
            groups.append(DateGroup(
                id: dayComponents,
                date: images[start].captureDate,
                range: start..<i
            ))
            for local in 0..<(i - start) {
                membership.append((groupIndex: groupIndex, localIndex: local))
            }
        }

        dateGroups = groups
        groupMembership = membership
    }

    private func navigateVertical(from index: Int, direction: Int) -> Int {
        guard !groupMembership.isEmpty else { return index }
        let (gIdx, localIdx) = groupMembership[index]
        let group = dateGroups[gIdx]
        let groupSize = group.range.count
        let col = localIdx % columnCount
        let row = localIdx / columnCount
        let totalRows = (groupSize + columnCount - 1) / columnCount

        if direction < 0 {
            // Moving up
            if row > 0 {
                // Stay within same section
                let newLocal = (row - 1) * columnCount + col
                return group.range.lowerBound + newLocal
            }
            // Cross to previous section
            if gIdx > 0 {
                let prevGroup = dateGroups[gIdx - 1]
                let prevSize = prevGroup.range.count
                let prevTotalRows = (prevSize + columnCount - 1) / columnCount
                let lastRowStart = (prevTotalRows - 1) * columnCount
                let targetLocal = min(lastRowStart + col, prevSize - 1)
                return prevGroup.range.lowerBound + targetLocal
            }
            return index
        } else {
            // Moving down
            if row < totalRows - 1 {
                // Stay within same section
                let newLocal = (row + 1) * columnCount + col
                if newLocal < groupSize {
                    return group.range.lowerBound + newLocal
                }
                // Last row is shorter — clamp to last item in section
                return group.range.upperBound - 1
            }
            // Cross to next section
            if gIdx < dateGroups.count - 1 {
                let nextGroup = dateGroups[gIdx + 1]
                let nextSize = nextGroup.range.count
                let targetLocal = min(col, nextSize - 1)
                return nextGroup.range.lowerBound + targetLocal
            }
            return index
        }
    }
}
