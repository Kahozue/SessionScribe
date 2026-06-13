import Foundation
import Security

/// API key 安全儲存抽象，便於測試注入。account 用供應商設定 id。
public protocol KeychainStore: Sendable {
    func secret(account: String) throws -> String?
    func setSecret(_ value: String, account: String) throws
    func deleteSecret(account: String) throws
}

/// 系統 Keychain 實作（kSecClassGenericPassword）。
public struct SystemKeychainStore: KeychainStore {
    let service: String
    public init(service: String = "com.sessionscribe.cloud-llm") { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func secret(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CloudLLMError.transport("Keychain 讀取失敗（\(status)）")
        }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String, account: String) throws {
        try deleteSecret(account: account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CloudLLMError.transport("Keychain 寫入失敗（\(status)）")
        }
    }

    public func deleteSecret(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CloudLLMError.transport("Keychain 刪除失敗（\(status)）")
        }
    }
}

/// 測試用：行程內保存，不碰系統 Keychain。
public final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    public init() {}
    public func secret(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }; return store[account]
    }
    public func setSecret(_ value: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; store[account] = value
    }
    public func deleteSecret(account: String) throws {
        lock.lock(); defer { lock.unlock() }; store[account] = nil
    }
}
