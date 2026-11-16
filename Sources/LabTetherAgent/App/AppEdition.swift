import Foundation

/// Which build of the app this is.
///
/// `scripts/build-app.sh --edition store` compiles with `-D LABTETHER_STORE`
/// for the Mac App Store. Every other build, `swift test` included, is the
/// Developer ID download, which is unchanged by the Store edition.
///
/// The Store edition runs in the App Sandbox and bundles the Rust agent's
/// monitoring edition in `Contents/MacOS`. Code that must not be in the Store
/// binary at all (the update check's request, the Screen Sharing admin grant,
/// the Hub SSH key remover) sits behind `#if LABTETHER_STORE`; everything
/// else asks the edition, so both editions' choices are tested in one run.
enum AppEdition: Equatable {
    case developerID
    case appStore

    static var current: AppEdition {
        #if LABTETHER_STORE
        return .appStore
        #else
        return .developerID
        #endif
    }

    var isStore: Bool { self == .appStore }

    /// The Mac App Store updates a Store app; no other update check is
    /// allowed (App Review Guideline 2.4.5(vii)).
    var checksForAppUpdates: Bool { !isStore }

    /// Screen Sharing status, its admin grant (2.4.5(v) forbids asking for
    /// admin rights) and the Remote View settings. The monitoring agent has
    /// no Remote View, so none of it is shown.
    var offersRemoteView: Bool { !isStore }

    /// Docker, files, service discovery, WebRTC and capture settings. The
    /// monitoring agent has none of those pages; a hidden setting must not
    /// reach it either.
    var offersAgentPageSettings: Bool { !isStore }

    /// The bundled agent: in `Contents/Resources` as the Developer ID app has
    /// always shipped it, in `Contents/MacOS` for the Store, where Apple wants
    /// a sandboxed app's helper executables.
    var agentInMacOSFolder: Bool { isStore }

    /// The Store app reads only files the person picks; a typed path cannot
    /// be read in the sandbox.
    var picksCAFileWithPanel: Bool { isStore }

    /// Setup explains the macOS Local Network question.
    var explainsLocalNetworkInSetup: Bool { isStore }

    /// Words shown with the agent's state.
    var agentEditionLabel: String? { isStore ? L10n.storeMonitoringOnly : nil }

    /// The Keychain service for the app's tokens. The Developer ID app keeps
    /// `com.labtether.agent`. The Store app uses its own bundle identifier, so
    /// a Store and a direct install on one Mac never read, overwrite or
    /// delete each other's tokens.
    func keychainService(bundleIdentifier: String?) -> String {
        let fallback = "com.labtether.agent"
        guard isStore, let bundleIdentifier, !bundleIdentifier.isEmpty else { return fallback }
        return bundleIdentifier
    }
}
