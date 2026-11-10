import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Security: certificate checks for wss:// Hubs.
struct SettingsSecurityTab: View {
    @ObservedObject var settings: AgentSettings
    /// What is in the field. It becomes the setting only when the file
    /// verifies the Hub alone; until then the saved setting stays.
    @State private var caDraft = ""
    @State private var caError: String?

    var body: some View {
        SettingsSection("TLS", footnote: "Applies to wss:// Hubs. A CA file keeps certificate checks on.") {
            LTToggleRow(
                label: "Skip certificate check",
                isOn: $settings.tlsSkipVerify,
                onChange: { settings.markChanged() }
            )
            LTFormRow(label: "CA certificate", alignment: caError == nil && settings.chosenCAProblem == nil ? .center : .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: LT.space8) {
                        LTTextField(
                            label: "CA certificate",
                            text: $caDraft,
                            prompt: "/Users/demo/hub-ca.pem",
                            hasError: caError != nil
                        )
                        Button("Browse…", action: browseCAFile)
                            .buttonStyle(LTSecondaryButtonStyle())
                    }
                    if let caError {
                        LTFieldError(text: caError)
                    } else if let problem = settings.chosenCAProblem {
                        // The saved file is wrong for this Hub: say so, with the way out.
                        HStack(alignment: .firstTextBaseline, spacing: LT.space8) {
                            LTFieldError(text: problem.words)
                            switch problem {
                            case .doesNotMatch:
                                Button("Remove") { caDraft = "" }
                                    .buttonStyle(LTTextButtonStyle(fontSize: 12))
                                    .accessibilityLabel("Remove CA certificate")
                            case .changed:
                                Button("Check again", action: checkSavedCAFileAgain)
                                    .buttonStyle(LTTextButtonStyle(fontSize: 12))
                                    .accessibilityLabel("Check CA certificate again")
                            }
                        }
                    }
                }
            }
            .onAppear { caDraft = settings.tlsCAFile }
            .onChange(of: settings.tlsCAFile) { caDraft = $0 }
            .task(id: caDraft) {
                let draft = caDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard draft != settings.tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    caError = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                let words = await settings.chooseCAFile(draft)
                guard !Task.isCancelled else { return }
                caError = words
                if words == nil { settings.markChanged() }
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

    /// The saved file changed on disk: the same path is checked against the
    /// Hub again, as if it had just been chosen.
    private func checkSavedCAFileAgain() {
        Task { @MainActor in
            caError = await settings.chooseCAFile(settings.tlsCAFile)
            if caError == nil { settings.markChanged() }
        }
    }

    private func browseCAFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["crt", "pem", "cer"].compactMap { UTType(filenameExtension: $0) }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            caDraft = url.path   // checked against the Hub, then saved
        }
    }
}
