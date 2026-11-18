import AppKit
import CofreCore
import CryptoKit
import Foundation
import LocalAuthentication

struct LogEntry: Identifiable {
    enum Kind { case encrypted, decrypted, failed, info }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let url: URL?
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var log: [LogEntry] = []
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var currentName = ""
    @Published var recoveryKeyShown: String?
    @Published var showImport = false

    @Published var deleteOriginal: Bool {
        didSet { UserDefaults.standard.set(deleteOriginal, forKey: "deleteOriginal") }
    }
    @Published var recoveryExported: Bool {
        didSet { UserDefaults.standard.set(recoveryExported, forKey: "recoveryExported") }
    }

    private init() {
        deleteOriginal = UserDefaults.standard.bool(forKey: "deleteOriginal")
        recoveryExported = UserDefaults.standard.bool(forKey: "recoveryExported")
    }

    // MARK: - Processing

    /// One Touch ID prompt per batch, then every file is processed off the main thread.
    func process(_ urls: [URL]) {
        let urls = urls.filter { $0.isFileURL }
        guard !urls.isEmpty else { return }
        guard !busy else {
            append(.info, String(localized: "Please wait"), String(localized: "Still processing the previous batch."), nil)
            return
        }
        busy = true
        progress = 0

        Task {
            defer { busy = false; currentName = "" }

            let cipher: CofreCipher
            do {
                try await KeyStore.authenticate(reason: reason(for: urls))
                let (key, created) = try KeyStore.loadOrCreate()
                if created {
                    append(.info, String(localized: "Key created"),
                           String(localized: "New master key saved to the Keychain. Back up your recovery key!"), nil)
                    recoveryExported = false
                }
                cipher = CofreCipher(masterKey: key)
            } catch {
                append(.failed, String(localized: "Not authorized"), Self.describe(error), nil)
                return
            }

            let deleteOriginal = self.deleteOriginal
            for (index, url) in urls.enumerated() {
                currentName = url.lastPathComponent
                let base = Double(index) / Double(urls.count)
                let share = 1 / Double(urls.count)
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try CofreJob.process(url, cipher: cipher, deleteOriginal: deleteOriginal) { p in
                            Task { @MainActor in Model.shared.progress = base + p * share }
                        }
                    }.value
                    let enc = result.action == .encrypted
                    append(enc ? .encrypted : .decrypted,
                           result.output.lastPathComponent,
                           enc ? String(localized: "Encrypted") : String(localized: "Decrypted"),
                           result.output)
                } catch {
                    append(.failed, url.lastPathComponent, Self.describe(error), url)
                }
            }
            progress = 1
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "Process")
        if panel.runModal() == .OK { process(panel.urls) }
    }

    // MARK: - Recovery key

    func exportRecoveryKey() {
        Task {
            do {
                try await KeyStore.authenticate(reason: String(localized: "show your recovery key"))
                let (key, _) = try KeyStore.loadOrCreate()
                recoveryKeyShown = RecoveryKey.encode(key)
            } catch {
                append(.failed, String(localized: "Export cancelled"), Self.describe(error), nil)
            }
        }
    }

    func importRecoveryKey(_ text: String) {
        let key: SymmetricKey
        do { key = try RecoveryKey.decode(text) } catch {
            append(.failed, String(localized: "Import failed"), Self.describe(error), nil)
            return
        }
        Task {
            do {
                try await KeyStore.authenticate(reason: String(localized: "replace the Cofre key"))
                try KeyStore.replace(with: key)
                recoveryExported = true
                append(.info, String(localized: "Key imported"),
                       String(localized: "The recovery key is now the active key."), nil)
            } catch {
                append(.failed, String(localized: "Import failed"), Self.describe(error), nil)
            }
        }
    }

    // MARK: - Helpers

    /// Shown by macOS as "Cofre is trying to <reason>."
    private func reason(for urls: [URL]) -> String {
        let isCofre: (URL) -> Bool = { $0.pathExtension.lowercased() == CofreCipher.fileExtension }
        let what = urls.count == 1 ? "“\(urls[0].lastPathComponent)”" : String(localized: "\(urls.count) files")
        if urls.allSatisfy(isCofre) { return String(localized: "decrypt \(what)") }
        if !urls.contains(where: isCofre) { return String(localized: "encrypt \(what)") }
        return String(localized: "process \(what)")
    }

    private func append(_ kind: LogEntry.Kind, _ title: String, _ detail: String, _ url: URL?) {
        log.insert(LogEntry(kind: kind, title: title, detail: detail, url: url), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    private static func describe(_ error: Error) -> String {
        if let la = error as? LAError {
            switch la.code {
            case .userCancel, .appCancel, .systemCancel: return String(localized: "Cancelled.")
            case .authenticationFailed: return String(localized: "Fingerprint not recognized.")
            case .biometryLockout: return String(localized: "Touch ID is locked — use your Mac password.")
            default: break
            }
        }
        return error.localizedDescription
    }
}
