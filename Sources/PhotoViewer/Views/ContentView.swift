import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            GridView()
                .opacity(appState.viewMode == .grid ? 1 : 0)
                .allowsHitTesting(appState.viewMode == .grid)

            if case .single(let index) = appState.viewMode {
                SinglePhotoView(index: index)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarView()
        }
        .overlay {
            if appState.isLoading {
                loadingView
            } else if appState.images.isEmpty {
                emptyState
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            if appState.loadingTotal > 0 {
                ProgressView(value: appState.loadingProgress) {
                    Text("Reading photo metadata\u{2026}")
                        .font(.headline)
                } currentValueLabel: {
                    Text("\(Int(appState.loadingProgress * Double(appState.loadingTotal))) of \(appState.loadingTotal) photos")
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                .frame(width: 260)
            } else {
                ProgressView("Scanning folder\u{2026}")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a folder to view photos")
                .font(.title2)
            Text("File \u{2192} Open Folder or \u{2318}O")
                .foregroundStyle(.secondary)
        }
    }
}
