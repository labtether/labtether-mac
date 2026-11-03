import SwiftUI

/// Remote View: macOS Screen Sharing, or WebRTC where the agent supports it.
struct SettingsRemoteViewSection: View {
    @ObservedObject var settings: AgentSettings

    var body: some View {
        SettingsSection("Remote View") {
            if AgentSettings.webRTCRuntimeSupported {
                LTToggleRow(label: "WebRTC streaming", isOn: $settings.webrtcEnabled, onChange: { settings.markChanged() })
                if settings.webrtcEnabled {
                    LTFormRow(label: "Screen Recording") {
                        if ScreenRecordingPermission.isGranted {
                            Text("Allowed")
                                .font(LT.font(13))
                                .foregroundStyle(LT.text2)
                        } else {
                            HStack(spacing: LT.space8) {
                                Text("Not allowed")
                                    .font(LT.font(13))
                                    .foregroundStyle(LT.warnText)
                                Button("Open System Settings") { ScreenRecordingPermission.openSettings() }
                                    .buttonStyle(LTSecondaryButtonStyle())
                            }
                        }
                    }
                }
                SettingsTextRow(label: "STUN URL", text: $settings.webrtcStunURL,
                                prompt: "stun:stun.example.com:3478", onChange: { settings.markChanged() })
                SettingsTextRow(label: "TURN URL", text: $settings.webrtcTurnURL,
                                prompt: "turn:turn.example.com:3478?transport=udp", onChange: { settings.markChanged() })
                SettingsTextRow(label: "TURN username", text: $settings.webrtcTurnUser,
                                prompt: "Optional", onChange: { settings.markChanged() })
                SettingsSecretRow(label: "TURN password", text: $settings.webrtcTurnPass,
                                  prompt: "Optional", onChange: { settings.markChanged() })
                SettingsNumberRow(label: "Capture FPS", text: $settings.captureFPS,
                                  prompt: "30", range: 5...120, onChange: { settings.markChanged() })
            } else {
                LTFormRow(label: "Screen Sharing") {
                    Button("Open Sharing settings") { ScreenSharingMonitor.openSharingSettings() }
                        .buttonStyle(LTSecondaryButtonStyle())
                }
            }
        }
    }
}

/// What the menu bar shows next to the glyph.
struct SettingsMenuBarSection: View {
    @ObservedObject var settings: AgentSettings

    var body: some View {
        SettingsSection("Menu bar") {
            SettingsPickerRow(
                label: "Show",
                selection: $settings.menuBarDisplayMode,
                options: [
                    ("Icon only", "compact"),
                    ("Icon, CPU and memory", "standard"),
                    ("Icon, CPU, memory and disk", "verbose"),
                ],
                segmented: false
            )
        }
    }
}

/// File paths and process details, collapsed by default.
struct SettingsDiagnosticsSection: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var status: AgentStatus
    @ObservedObject var metadata: LocalAPIMetadataStore
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space4) {
            LTDisclosureRow(title: "Diagnostics", detail: "Paths, process ID, fingerprint", isExpanded: $isExpanded)
            if isExpanded {
                LTSheet(padding: EdgeInsets(top: 6, leading: LT.space16, bottom: 6, trailing: LT.space16)) {
                    VStack(alignment: .leading, spacing: 0) {
                        row("State", status.state.rawValue)
                        row("Agent binary", BundleHelper.binaryExists ? BundleHelper.agentBinaryPath : "Missing: \(BundleHelper.agentBinaryPath)", mono: true)
                        row("Token file", settings.tokenFilePath, mono: true)
                        row("Settings file", settings.agentSettingsFilePath, mono: true)
                        row("Device key", settings.deviceKeyFilePath, mono: true)
                        row("Fingerprint file", settings.deviceFingerprintFilePath, mono: true)
                        let local = metadata.snapshot
                        if let fingerprint = local.deviceFingerprint, !fingerprint.isEmpty {
                            row("Device fingerprint", fingerprint, mono: true)
                        }
                        if let bind = local.localBindAddress, !bind.isEmpty {
                            row("Local API", bind)
                        }
                        if let authEnabled = local.localAuthEnabled {
                            row("Local API token", authEnabled ? "Required" : "Off")
                        }
                        if let insecure = local.allowInsecureTransport {
                            row("Unencrypted ws://", insecure ? "Allowed" : "Blocked")
                        }
                        if let pid = status.pid {
                            row("Process ID", "\(pid)")
                        }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LT.space12) {
            Text(label)
                .font(LT.font(13))
                .foregroundStyle(LT.text3)
                .frame(width: 128, alignment: .leading)
            Text(value)
                .font(mono ? LT.mono(12) : LT.font(13).monospacedDigit())
                .foregroundStyle(LT.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
    }
}
