import SwiftUI

struct ToolbarView: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await openFolder() }
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await copySelected() }
            } label: {
                Label("Copy Selected (\(appState.selectedIDs.count))", systemImage: "doc.on.doc")
            }
            .disabled(appState.selectedIDs.isEmpty)
            .keyboardShortcut("e", modifiers: [.command])
        }

        ToolbarItem(placement: .status) {
            if !appState.images.isEmpty {
                Text("\(appState.images.count) photos \u{2022} \(appState.selectedIDs.count) selected")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.horizontal, 8)
            }
        }
    }

    @MainActor
    private func openFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await appState.loadFolder(url)
    }

    @MainActor
    private func copySelected() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Destination"
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let selectedURLs = appState.images
            .filter { appState.selectedIDs.contains($0.id) }
            .map(\.url)

        do {
            _ = try await FileCopyService.copyFiles(from: selectedURLs, to: dest)
            appState.selectedIDs.removeAll()
        } catch {
            // File copy failed silently for now
        }
    }
}
