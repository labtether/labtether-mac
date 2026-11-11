import SwiftUI

/// Startup and app-update preferences shown at the top of Settings › Advanced.
struct SettingsStartupSection: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var status: AgentStatus

    var body: some View {
        SettingsSection("Startup") {
            LTToggleRow(label: "Start at login", isOn: startAtLogin)
                .disabled(!settings.allowsSystemIntegration)

            LTToggleRow(label: "Start the agent when the app opens", isOn: $settings.autoStart)

            LTToggleRow(
                label: "Check for updates daily",
                isOn: $settings.checkForAppUpdates,
                detail: "\(ManagedAppUpdatePolicy.detail) Nothing is downloaded automatically."
            )
            .disabled(!settings.allowsSystemIntegration)
        }
    }

    private var startAtLogin: Binding<Bool> {
        Binding(
            get: { settings.startAtLogin },
            set: { newValue in
                guard settings.allowsSystemIntegration else { return }
                if LoginItemManager.setEnabled(newValue) {
                    settings.startAtLogin = newValue
                } else {
                    settings.startAtLogin = LoginItemManager.isEnabled
                    status.markError(
                        newValue
                            ? "Start at login was not turned on. Allow LabTether in System Settings › General › Login Items."
                            : "Start at login could not be turned off. See System Settings › General › Login Items."
                    )
                }
            }
        )
    }
}
