import Foundation
import LocalAuthentication
import Security

/// Stores sensitive settings in the macOS Keychain.
enum KeychainSecretStore {
    private final class LoadResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue: String?

        func store(_ value: String?) {
            lock.lock()
            storedValue = value
            lock.unlock()
        }

        func value() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
    }

    private static let service = "com.labtether.agent"
    private static let loadQueue = DispatchQueue(
        label: "com.labtether.agent.keychain-load",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let loadTimeout: DispatchTimeInterval = .seconds(1)
    // Raw values of kSecUseAuthenticationUI and
    // kSecUseAuthenticationUIFail. Apple deprecated the typed constants in
    // favor of LAContext, but legacy Keychain ACLs can still enter the older
    // authorization path before consulting that context. Supplying both keeps
    // launch non-interactive across old and current item formats.
    private static let authenticationUIQueryKey = "u_AuthUI"
    private static let authenticationUIFailValue = "u_AuthUIF"

    static func load(account: String) -> String? {
        boundedLoad {
            loadWithoutTimeout(account: account)
        }
    }

    static func boundedLoad(
        timeout: DispatchTimeInterval = loadTimeout,
        operation: @escaping @Sendable () -> String?
    ) -> String? {
        let completion = DispatchSemaphore(value: 0)
        let result = LoadResultBox()
        loadQueue.async {
            result.store(operation())
            completion.signal()
        }

        guard completion.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        return result.value()
    }

    private static func loadWithoutTimeout(account: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(loadQuery(account: account) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func loadQuery(account: String) -> [String: Any] {
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true

        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // A stale or externally-created item may require an authorization
            // prompt. Secret loading happens synchronously during SwiftUI app
            // construction, before any LabTether window can appear, so such a
            // prompt would otherwise freeze the entire app launch. Treat an
            // inaccessible item as unavailable and let the UI surface the
            // missing credential instead.
            kSecUseAuthenticationContext as String: authenticationContext,
            authenticationUIQueryKey: authenticationUIFailValue,
        ]
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
