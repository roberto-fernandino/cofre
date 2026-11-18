import CofreCore
import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Guarda a chave mestra (256 bits) no Keychain do usuário, só neste Mac (sem iCloud),
/// e só a lê depois de Touch ID (ou senha do Mac, se o sensor não estiver disponível).
enum KeyStore {
    private static let service = "Cofre"
    private static let account = "master-key-v1"

    enum Failure: LocalizedError {
        case keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .keychain(let s):
                let msg = SecCopyErrorMessageString(s, nil) as String? ?? "erro \(s)"
                return "Keychain: \(msg)"
            }
        }
    }

    /// Pede a digital. `.deviceOwnerAuthentication` = Touch ID, com a senha do Mac como alternativa.
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    static func hasKey() -> Bool {
        (try? read()) != nil
    }

    /// Lê a chave; se ainda não existir, cria uma nova. Só chame depois de `authenticate`.
    static func loadOrCreate() throws -> (key: SymmetricKey, created: Bool) {
        if let key = try read() { return (key, false) }
        let key = SymmetricKey(size: .bits256)
        try write(key)
        return (key, true)
    }

    static func replace(with key: SymmetricKey) throws {
        SecItemDelete(baseQuery as CFDictionary)
        try write(key)
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data, data.count == 32 else {
            throw Failure.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    private static func write(_ key: SymmetricKey) throws {
        var item = baseQuery
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrLabel as String] = "Cofre — chave mestra"
        item[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}
