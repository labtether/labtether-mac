import XCTest
@testable import LabTetherAgent

final class ManagedAppUpdatePolicyTests: XCTestCase {
    func testMigratesLegacyEnabledChildAutoUpdatePreference() throws {
        let suiteName = "ManagedAppUpdatePolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: ManagedAppUpdatePolicy.legacyChildAutoUpdatePreferenceKey)

        XCTAssertTrue(ManagedAppUpdatePolicy.migrateLegacyPreference(in: defaults))
        XCTAssertFalse(defaults.bool(forKey: ManagedAppUpdatePolicy.legacyChildAutoUpdatePreferenceKey))
        XCTAssertFalse(ManagedAppUpdatePolicy.migrateLegacyPreference(in: defaults))
    }

    func testForcesBundledAgentCoreAutoUpdateOff() {
        var environment = [ManagedAppUpdatePolicy.environmentKey: "true"]

        ManagedAppUpdatePolicy.apply(to: &environment, parentProcessIdentifier: 4242)

        XCTAssertEqual(environment[ManagedAppUpdatePolicy.environmentKey], "false")
        XCTAssertEqual(environment[ManagedAppUpdatePolicy.parentPIDEnvironmentKey], "4242")
        XCTAssertEqual(ManagedAppUpdatePolicy.title, "LabTether App Updates")
        XCTAssertEqual(ManagedAppUpdatePolicy.badge, "App-managed")
        XCTAssertTrue(ManagedAppUpdatePolicy.detail.contains("signed LabTether app"))
    }
}
