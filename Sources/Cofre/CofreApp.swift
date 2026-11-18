import AppKit
import SwiftUI

@main
struct CofreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = Model.shared

    var body: some Scene {
        Window("Cofre", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") { model.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Key") {
                Button("Show Recovery Key…") { model.exportRecoveryKey() }
                Button("Import Recovery Key…") { model.showImport = true }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files dropped on the Dock icon, "Open With" in Finder, or a double-clicked .cofre file.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in Model.shared.process(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
