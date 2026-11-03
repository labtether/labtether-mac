import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Security: certificate checks for wss:// Hubs.
struct SettingsSecurityTab: View {
    @ObservedObject var settings: AgentSettings

    var body: some View {
        SettingsSection("TLS", footnote: "Applies to wss:// Hubs. A CA file keeps certificate checks on.") {
            LTToggleRow(
                label: "Skip certificate check",
                isOn: $settings.tlsSkipVerify,
                onChange: { settings.markChanged() }
            )
            LTFormRow(label: "CA certificate") {
                HStack(spacing: LT.space8) {
                    LTTextField(
                        label: "CA certificate",
                        text: $settings.tlsCAFile,
                        prompt: "/Users/demo/hub-ca.pem",
                        onChange: { settings.markChanged() }
                    )
                    Button("Browse…", action: browseCAFile)
                        .buttonStyle(LTSecondaryButtonStyle())
                }
            }
        }
    }

    private func browseCAFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["crt", "pem", "cer"].compactMap { UTType(filenameExtension: $0) }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.tlsCAFile = url.path
            settings.markChanged()
        }
    }
}
