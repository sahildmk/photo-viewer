import SwiftUI

struct SinglePhotoView: View {
    @Environment(AppState.self) private var appState
    let index: Int

    @State private var fullImage: NSImage?
    @FocusState private var isFocused: Bool

    private var currentItem: ImageItem {
        appState.images[index]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let fullImage {
                Image(nsImage: fullImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .colorScheme(.dark)
            }

            selectionBadge
            fileNameOverlay
            navigationHints
        }
        .task(id: index) {
            fullImage = nil
            fullImage = await ImageLoader.shared.loadFullSize(url: currentItem.url)
            guard !Task.isCancelled else { return }
            appState.restartPreload(centerIndex: index)
            prefetchAdjacent()
        }
        .onAppear {
            isFocused = true
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            appState.exitSingleView()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            appState.navigateSingle(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            appState.navigateSingle(1)
            return .handled
        }
        .onKeyPress(.space) {
            appState.toggleSelection(for: currentItem.id)
            return .handled
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if appState.selectedIDs.contains(currentItem.id) {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white, .blue)
                        .padding()
                }
                Spacer()
            }
        }
    }

    private var fileNameOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Text(currentItem.fileName)
                    .foregroundStyle(.white)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))

                Spacer()

                Text("\(index + 1) / \(appState.images.count)")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding()
        }
    }

    private var navigationHints: some View {
        VStack {
            Spacer()
            Spacer()
        }
    }

    private func prefetchAdjacent() {
        let adjacent = [index - 1, index + 1]
            .filter { $0 >= 0 && $0 < appState.images.count }
            .map { appState.images[$0].url }
        ImageLoader.shared.prefetch(urls: adjacent)
    }
}
