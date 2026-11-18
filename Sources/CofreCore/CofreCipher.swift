import CryptoKit
import Foundation

/// Errors of the .cofre format.
public enum CofreError: LocalizedError, Equatable {
    case notCofreFile
    case unsupportedVersion(UInt8)
    case authenticationFailed
    case isDirectory
    case invalidRecoveryKey

    public var errorDescription: String? {
        switch self {
        case .notCofreFile: return String(localized: "Not a valid .cofre file.")
        case .unsupportedVersion(let v): return String(localized: "Unsupported file version (\(Int(v))).")
        case .authenticationFailed: return String(localized: "Wrong key, or the file is corrupted or was tampered with.")
        case .isDirectory: return String(localized: "Folders aren't supported — zip them first.")
        case .invalidRecoveryKey: return String(localized: "Invalid recovery key.")
        }
    }
}

/// File format (v1):
///
///     header = "COFRE\0" | version (1 byte) | chunk size (UInt32 BE) | salt (32 bytes)
///     body   = AES-256-GCM chunks: ciphertext | tag(16)
///
/// - Every file gets its own key: HKDF-SHA256(master key, random salt). Keys never repeat.
/// - Chunk nonce = counter (11 bytes BE) | last-chunk flag (1 byte), so chunks can't be
///   reordered, dropped or truncated without detection (STREAM-style construction).
/// - The whole header is authenticated (AAD) in every chunk.
public struct CofreCipher: Sendable {
    public static let fileExtension = "cofre"
    public static let defaultChunkSize = 1 << 20 // 1 MiB

    static let magic: [UInt8] = Array("COFRE".utf8) + [0]
    static let version: UInt8 = 1
    static let saltSize = 32
    static let tagSize = 16
    static let headerSize = magic.count + 1 + 4 + saltSize
    static let maxChunkSize = 64 << 20

    private let masterKey: SymmetricKey

    public init(masterKey: SymmetricKey) {
        self.masterKey = masterKey
    }

    // MARK: - Encrypt

    public func encrypt(
        from input: URL,
        to output: URL,
        chunkSize: Int = CofreCipher.defaultChunkSize,
        progress: ((Int64) -> Void)? = nil
    ) throws {
        precondition(chunkSize > 0 && chunkSize <= Self.maxChunkSize)
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }
        let writer = try Self.createWriter(at: output)
        defer { try? writer.close() }

        var salt = Data(count: Self.saltSize)
        salt.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, Self.saltSize, $0.baseAddress!) }

        var header = Data(Self.magic)
        header.append(Self.version)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(chunkSize).bigEndian, Array.init))
        header.append(salt)
        try writer.write(contentsOf: header)

        let key = fileKey(salt: salt)
        var counter: UInt64 = 0
        var processed: Int64 = 0
        var current = try reader.read(upToCount: chunkSize) ?? Data()

        while true {
            let next = try reader.read(upToCount: chunkSize) ?? Data()
            let isFinal = next.isEmpty
            try autoreleasepool {
                let box = try AES.GCM.seal(current, using: key, nonce: Self.nonce(counter, final: isFinal), authenticating: header)
                try writer.write(contentsOf: box.ciphertext)
                try writer.write(contentsOf: box.tag)
            }
            processed += Int64(current.count)
            progress?(processed)
            if isFinal { break }
            current = next
            counter += 1
        }
        try writer.synchronize()
    }

    // MARK: - Decrypt

    public func decrypt(
        from input: URL,
        to output: URL,
        progress: ((Int64) -> Void)? = nil
    ) throws {
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }

        guard let header = try reader.read(upToCount: Self.headerSize),
              header.count == Self.headerSize,
              Array(header.prefix(Self.magic.count)) == Self.magic
        else { throw CofreError.notCofreFile }

        let version = header[Self.magic.count]
        guard version == Self.version else { throw CofreError.unsupportedVersion(version) }

        let sizeStart = Self.magic.count + 1
        let chunkSize = Int(header[sizeStart..<sizeStart + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        guard chunkSize > 0, chunkSize <= Self.maxChunkSize else { throw CofreError.notCofreFile }
        let salt = header.suffix(Self.saltSize)

        let writer = try Self.createWriter(at: output)
        defer { try? writer.close() }

        let key = fileKey(salt: Data(salt))
        let sealedChunk = chunkSize + Self.tagSize
        var counter: UInt64 = 0
        var processed: Int64 = 0
        var current = try reader.read(upToCount: sealedChunk) ?? Data()

        while true {
            let next = try reader.read(upToCount: sealedChunk) ?? Data()
            let isFinal = next.isEmpty
            guard current.count >= Self.tagSize, isFinal || current.count == sealedChunk else {
                throw CofreError.authenticationFailed
            }
            try autoreleasepool {
                let box = try AES.GCM.SealedBox(
                    nonce: Self.nonce(counter, final: isFinal),
                    ciphertext: current.prefix(current.count - Self.tagSize),
                    tag: current.suffix(Self.tagSize)
                )
                let plain: Data
                do {
                    plain = try AES.GCM.open(box, using: key, authenticating: header)
                } catch {
                    throw CofreError.authenticationFailed
                }
                try writer.write(contentsOf: plain)
                processed += Int64(plain.count)
            }
            progress?(processed)
            if isFinal { break }
            current = next
            counter += 1
        }
        try writer.synchronize()
    }

    // MARK: - Internals

    private func fileKey(salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: Data("cofre v1 file key".utf8),
            outputByteCount: 32
        )
    }

    static func nonce(_ counter: UInt64, final: Bool) -> AES.GCM.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        withUnsafeBytes(of: counter.bigEndian) { bytes.replaceSubrange(3..<11, with: $0) }
        bytes[11] = final ? 1 : 0
        return try! AES.GCM.Nonce(data: bytes)
    }

    private static func createWriter(at url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return try FileHandle(forWritingTo: url)
    }
}
