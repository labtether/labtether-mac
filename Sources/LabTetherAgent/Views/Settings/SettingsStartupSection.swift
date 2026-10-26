import SwiftUI

/// Startup and app-update preferences shown at the top of Settings > Advanced.
struct SettingsStartupSection: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var status: AgentStatus

    var body: some View {
        SettingsCardSection("STARTUP") {
            SettingsToggleRow(icon: "person.badge.clock.fill", label: "Start at Login",
                              isOn: Binding(
                                  get: { settings.startAtLogin },
                                  set: { newValue in
                                      guard settings.allowsSystemIntegration else { return }
                                      if LoginItemManager.setEnabled(newValue) {
                                          settings.startAtLogin = newValue
                                      } else {
                                          settings.startAtLogin = LoginItemManager.isEnabled
                                          status.markError(
                                              newValue
                                                  ? "Start at Login was not enabled. Approve LabTether in System Settings > General > Login Items, then try again."
                                                  : "Start at Login could not be disabled. Check System Settings > General > Login Items."
                                          )
                                      }
                                  }
                              ))
                .disabled(!settings.allowsSystemIntegration)

            SettingsToggleRow(icon: "play.circle.fill", label: "Auto-Start Agent on Launch",
                              isOn: $settings.autoStart)

            HStack(spacing: LT.space8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LT.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ManagedAppUpdatePolicy.title)
                        .font(LT.inter(12, weight: .medium))
                        .foregroundStyle(LT.textPrimary)
                    Text(ManagedAppUpdatePolicy.detail)
                        .font(LT.inter(10))
                        .foregroundStyle(LT.textSecondary)
                }
                Spacer()
                Text(ManagedAppUpdatePolicy.badge)
                    .font(LT.inter(9, weight: .semibold))
                    .foregroundStyle(LT.accent)
                    .padding(.horizontal, LT.space8)
                    .padding(.vertical, 4)
                    .background(LT.accent.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space4)
            .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                    .strokeBorder(LT.panelBorder, lineWidth: 1)
            )

            SettingsToggleRow(icon: "arrow.down.circle.fill", label: "Check for App Updates Daily",
                              isOn: $settings.checkForAppUpdates)
                .disabled(!settings.allowsSystemIntegration)
                .help("Shows a menu item when a newer signed release is published. Nothing is downloaded automatically.")
        }
    }
}
