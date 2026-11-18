import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: Model
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 14) {
            dropZone

            Toggle("Delete the original file after processing", isOn: $model.deleteOriginal)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !model.recoveryExported {
                recoveryBanner
            }

            logList
        }
        .padding(18)
        .frame(width: 480, height: 560)
        .sheet(item: Binding(
            get: { model.recoveryKeyShown.map(KeyBox.init) },
            set: { if $0 == nil { model.recoveryKeyShown = nil } }
        )) { box in
            RecoveryKeySheet(key: box.key) {
                model.recoveryExported = true
                model.recoveryKeyShown = nil
            }
        }
        .sheet(isPresented: $model.showImport) {
            ImportKeySheet { text in
                model.showImport = false
                model.importRecoveryKey(text)
            } onCancel: {
                model.showImport = false
            }
        }
    }

    // MARK: - Sections

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))

            VStack(spacing: 10) {
                if model.busy {
                    ProgressView(value: model.progress)
                        .frame(width: 220)
                    Text(model.currentName.isEmpty ? String(localized: "Waiting for Touch ID…") : model.currentName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300)
                } else {
                    Image(systemName: "touchid")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(targeted ? Color.accentColor : .secondary)
                    Text("Drop files here")
                        .font(.title3.weight(.semibold))
                    Text("**.cofre** files get unlocked. Everything else gets locked.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Choose Files…") { model.openPanel() }
                        .padding(.top, 2)
                }
            }
            .padding()
        }
        .frame(height: 210)
        .dropDestination(for: URL.self) { urls, _ in
            model.process(urls)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var recoveryBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Back up your recovery key")
                    .font(.callout.weight(.semibold))
                Text("The key only lives in this Mac's Keychain. If it's lost, your .cofre files can't be opened without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Show") { model.exportRecoveryKey() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var logList: some View {
        Group {
            if model.log.isEmpty {
                Text("Nothing processed yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.log) { entry in
                    LogRow(entry: entry)
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct KeyBox: Identifiable {
    let key: String
    var id: String { key }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let url = entry.url, FileManager.default.fileExists(atPath: url.path) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch entry.kind {
        case .encrypted: return "lock.fill"
        case .decrypted: return "lock.open.fill"
        case .failed: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .encrypted: return .green
        case .decrypted: return .blue
        case .failed: return .red
        case .info: return .secondary
        }
    }
}

private struct RecoveryKeySheet: View {
    let key: String
    let onDone: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Recovery Key", systemImage: "key.fill")
                .font(.title3.weight(.semibold))
            Text("Store this in a password manager (1Password, Apple Passwords…). Anyone with this key can open any of your .cofre files — never share it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(key)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(key, forType: .string)
                    copied = true
                } label: {
                    copied ? Text("Copied ✓") : Text("Copy")
                }
                Spacer()
                Button("I've Saved It") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct ImportKeySheet: View {
    let onImport: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Import Recovery Key", systemImage: "key.horizontal.fill")
                .font(.title3.weight(.semibold))
            Text("Use this on a new Mac to open files locked with an older key. This Mac's current key will be replaced.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("cofre1:…", text: $text)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { confirming = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .confirmationDialog("Replace the current key?", isPresented: $confirming) {
            Button("Replace", role: .destructive) { onImport(text) }
        } message: {
            Text("Files locked with the current key will only open again if you have its recovery key.")
        }
    }
}
