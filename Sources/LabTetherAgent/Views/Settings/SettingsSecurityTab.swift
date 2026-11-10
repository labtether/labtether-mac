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
            if let fingerprint = trustedHubFingerprint {
                LTFormRow(label: "Trusted Hub", alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(fingerprint, id: \.self) { row in
                            Text(row)
                                .font(LT.mono(12))
                                .foregroundStyle(LT.text2)
                        }
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Trusted Hub certificate fingerprint")
                    .accessibilityValue(fingerprint.joined(separator: " "))
                }
            }
        }
    }

    /// The fingerprint of the Hub certificate kept by "Trust this Hub" (or by
    /// enrollment), shown while no CA file is typed above.
    private var trustedHubFingerprint: [String]? {
        guard settings.tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.hasManagedHubCA,
              let ca = try? ConnectionTester.trustedCertificates(for: settings.managedHubCAPath).first else { return nil }
        let value = HubCATrust.fingerprint(of: ca)
        return HubCAOffer(pem: "", fingerprint: value).groupedRows
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
