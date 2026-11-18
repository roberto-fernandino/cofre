import CryptoKit
import Foundation

public enum CofreAction: Sendable {
    case encrypted, decrypted
}

public struct CofreResult: Sendable {
    public let action: CofreAction
    public let output: URL
}

/// Decide o que fazer com um arquivo: `.cofre` → descriptografa; qualquer outro → criptografa.
/// Escreve num arquivo temporário na mesma pasta e só renomeia no final, para nunca deixar
/// um resultado pela metade.
public enum CofreJob {
    public static func process(
        _ url: URL,
        cipher: CofreCipher,
        deleteOriginal: Bool,
        progress: ((Double) -> Void)? = nil
    ) throws -> CofreResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        if isDir.boolValue { throw CofreError.isDirectory }

        let total = max((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 1, 1)
        let report: (Int64) -> Void = { progress?(min(Double($0) / Double(total), 1)) }

        let decrypting = url.pathExtension.lowercased() == CofreCipher.fileExtension
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            let target: URL
            if decrypting {
                try cipher.decrypt(from: url, to: temp, progress: report)
                target = uniqueURL(url.deletingPathExtension())
            } else {
                try cipher.encrypt(from: url, to: temp, progress: report)
                target = uniqueURL(url.appendingPathExtension(CofreCipher.fileExtension))
            }
            try fm.moveItem(at: temp, to: target)
            if deleteOriginal { try fm.removeItem(at: url) }
            return CofreResult(action: decrypting ? .decrypted : .encrypted, output: target)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    /// `foo.txt` → `foo (1).txt`, `foo (2).txt`… se já existir.
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}

/// Representação textual da chave mestra para backup: `cofre1:<base64>`.
public enum RecoveryKey {
    static let prefix = "cofre1:"

    public static func encode(_ key: SymmetricKey) -> String {
        prefix + key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    public static func decode(_ text: String) throws -> SymmetricKey {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        guard let data = Data(base64Encoded: s), data.count == 32 else { throw CofreError.invalidRecoveryKey }
        return SymmetricKey(data: data)
    }
}
