import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.viewMode {
            case .grid:
                GridView()
            case .single(let index):
                SinglePhotoView(index: index)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarView()
        }
        .overlay {
            if appState.images.isEmpty && !appState.isLoading {
                emptyState
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
