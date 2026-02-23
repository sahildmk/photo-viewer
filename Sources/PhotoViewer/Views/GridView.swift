import SwiftUI

struct GridView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isFocused: Bool

    private let thumbnailSize: CGFloat = 160
    private let spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let columns = max(1, Int((geometry.size.width - spacing) / (thumbnailSize + spacing)))

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(thumbnailSize), spacing: spacing),
                            count: columns
                        ),
                        spacing: spacing,
                        pinnedViews: [.sectionHeaders]
                    ) {
                        ForEach(Array(appState.dateGroups.enumerated()), id: \.element.id) { groupIndex, group in
                            Section {
                                ForEach(appState.images[group.range]) { item in
                                    let index = appState.indexByID[item.id]!
                                    GridItemView(
                                        item: item,
                                        isFocused: appState.focusedIndex == index,
                                        isSelected: appState.selectedIDs.contains(item.id)
                                    )
                                    .id(item.id)
                                    .onTapGesture(count: 2) {
                                        appState.focusedIndex = index
                                        appState.enterSingleView()
                                    }
                                    .onTapGesture {
                                        appState.focusedIndex = index
                                    }
                                }
                            } header: {
                                DateHeaderView(
                                    group: group,
                                    groupIndex: groupIndex,
                                    photoCount: group.range.count,
                                    allSelected: appState.isGroupFullySelected(groupIndex),
                                    onToggle: {
                                        appState.toggleGroupSelection(groupIndex: groupIndex)
                                    }
                                )
                            }
                        }
                    }
                    .padding(spacing)
                }
                .onChange(of: appState.focusedIndex) { _, newValue in
                    if let idx = newValue, idx < appState.images.count {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrollProxy.scrollTo(appState.images[idx].id, anchor: .center)
                        }
                    }
                }
                .onChange(of: columns) { _, newCount in
                    appState.columnCount = newCount
                }
                .onAppear {
                    appState.columnCount = columns
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onChange(of: appState.viewMode) { _, newValue in
            if newValue == .grid {
                isFocused = true
            }
        }
        .onMoveCommand { direction in
            appState.moveFocus(direction)
        }
        .onKeyPress(.return) {
            appState.enterSingleView()
            return .handled
        }
        .onKeyPress(.space) {
            if let idx = appState.focusedIndex, idx < appState.images.count {
                appState.toggleSelection(for: appState.images[idx].id)
            }
            return .handled
        }
    }
}
