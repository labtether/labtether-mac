import Foundation

/// Words used only by the Mac App Store edition.
extension L10n {
    private static var storeBundle: Bundle { BundleHelper.resourceBundle }

    /// "Monitoring only" / "Solo supervisión"
    static var storeMonitoringOnly: String {
        NSLocalizedString("store.monitoring_only", bundle: storeBundle, comment: "")
    }

    /// "Local network" / "Red local"
    static var storeLocalNetwork: String {
        NSLocalizedString("store.local_network", bundle: storeBundle, comment: "")
    }

    /// The setup step before macOS has been asked, or after it said yes.
    static var storeLocalNetworkAsk: String {
        NSLocalizedString("store.local_network_ask", bundle: storeBundle, comment: "")
    }

    /// "Local Network access is off for %@." with the app's name.
    static func storeLocalNetworkDenied(_ appName: String) -> String {
        String(format: NSLocalizedString("store.local_network_denied", bundle: storeBundle, comment: ""), appName)
    }

    /// "Open Settings" / "Abrir Ajustes"
    static var storeLocalNetworkOpenSettings: String {
        NSLocalizedString("store.local_network_open_settings", bundle: storeBundle, comment: "")
    }

    /// "Choose…" / "Elegir…"
    static var storeCAChoose: String {
        NSLocalizedString("store.ca_choose", bundle: storeBundle, comment: "")
    }

    /// "Remove" / "Quitar"
    static var storeCARemove: String {
        NSLocalizedString("store.ca_remove", bundle: storeBundle, comment: "")
    }

    /// "None" / "Ninguno"
    static var storeCANone: String {
        NSLocalizedString("store.ca_none", bundle: storeBundle, comment: "")
    }
}
