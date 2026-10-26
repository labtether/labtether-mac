import Foundation
import Security

/// Default mode retains the existing defaults domain. Isolated mode never opens it.
final class AgentPreferences {
    private let defaults: UserDefaults?
    private let location: AppStateLocation?
    private var values: [String: Any] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        location = nil
        ManagedAppUpdatePolicy.migrateLegacyPreference(in: defaults)
    }

    init(location: AppStateLocation) throws {
        defaults = nil
        self.location = location
        if let data = try location.read("preferences.json") {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  value.count <= 64, value.values.allSatisfy({ $0 is String || $0 is Bool }) else {
                throw AppStateLocation.Failure.unsafeFile
            }
            values = value
        }
    }

    func observeChanges(_ action: @escaping () -> Void) -> NSObjectProtocol? {
        guard let defaults else { return nil }
        return NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                       object: defaults, queue: .main) { _ in action() }
    }

    func string(_ key: String, default value: String) -> String {
        (defaults?.object(forKey: key) ?? values[key]) as? String ?? value
    }

    func bool(_ key: String, default value: Bool) -> Bool {
        (defaults?.object(forKey: key) ?? values[key]) as? Bool ?? value
    }

    func set(_ value: Any, key: String) throws {
        if let defaults { defaults.set(value, forKey: key); return }
        var proposed = values
        proposed[key] = value
        let data = try JSONSerialization.data(withJSONObject: proposed, options: [.sortedKeys])
        try location!.write(data, name: "preferences.json")
        values = proposed
    }
}

/// Bootstrap tokens in a disposable app live only in memory. The existing
/// runtime-secret owner writes the minimum private files needed by the Go child.
final class AgentBootstrapSecrets {
    private let usesKeychain: Bool
    private var values: [String: String] = [:]
    init(usesKeychain: Bool) { self.usesKeychain = usesKeychain }
    func load(account: String) -> String? {
        usesKeychain ? KeychainSecretStore.load(account: account) : values[account]
    }
    func saveStatus(_ value: String, account: String) -> OSStatus {
        if usesKeychain { return KeychainSecretStore.saveStatus(value, account: account) }
        values[account] = value
        return errSecSuccess
    }
    func deleteStatus(account: String) -> OSStatus {
        if usesKeychain { return KeychainSecretStore.deleteStatus(account: account) }
        values.removeValue(forKey: account)
        return errSecSuccess
    }
}
