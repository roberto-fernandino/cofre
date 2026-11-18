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
                Button("Abrir arquivos…") { model.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Chave") {
                Button("Mostrar chave de recuperação…") { model.exportRecoveryKey() }
                Button("Importar chave de recuperação…") { model.showImport = true }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Arquivos soltos no ícone do Dock, "Abrir com" do Finder ou duplo clique num .cofre.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in Model.shared.process(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
