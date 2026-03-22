import Foundation
import Security

/// Stores sensitive settings in the macOS Keychain.
enum KeychainSecretStore {
    private static let service = "com.labtether.agent"

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        saveStatus(value, account: account) == errSecSuccess
    }

    static func saveStatus(_ value: String, account: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }

        // Update existing key first to avoid extra delete/add churn.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return errSecSuccess
        }

        if updateStatus != errSecItemNotFound {
            return updateStatus
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func delete(account: String) {
        _ = deleteStatus(account: account)
    }

    @discardableResult
    static func deleteStatus(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            return errSecSuccess
        }
        return status
    }

    static func errorMessage(for status: OSStatus) -> String {
        if let description = SecCopyErrorMessageString(status, nil) as String? {
            return description
        }
        return "OSStatus \(status)"
    }
}
