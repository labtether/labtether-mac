import Foundation

/// The native app is one signed release artifact. Its bundled agent core must
/// never replace itself independently because that would invalidate the app's
/// code signature.
enum ManagedAppUpdatePolicy {
    static let legacyChildAutoUpdatePreferenceKey = "autoUpdateEnabled"
    static let environmentKey = "LABTETHER_AUTO_UPDATE"
    static let parentPIDEnvironmentKey = "LABTETHER_PARENT_PID"
    static let title = "LabTether App Updates"
    static let detail = "Agent core updates with the signed LabTether app."
    static let badge = "App-managed"

    @discardableResult
    static func migrateLegacyPreference(in defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: legacyChildAutoUpdatePreferenceKey) else {
            return false
        }
        defaults.set(false, forKey: legacyChildAutoUpdatePreferenceKey)
        return true
    }

    static func apply(
        to environment: inout [String: String],
        parentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        environment[environmentKey] = "false"
        environment[parentPIDEnvironmentKey] = String(parentProcessIdentifier)
    }
}
