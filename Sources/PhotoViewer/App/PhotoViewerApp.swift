import AppKit
import SwiftUI

@main
struct PhotoViewerApp: App {
    @State private var appState = AppState()

    init() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder...") {
                    Task { await openFolder() }
                }
                .keyboardShortcut("o")
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
}
