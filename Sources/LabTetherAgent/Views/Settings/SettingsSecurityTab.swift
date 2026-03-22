import SwiftUI
import UniformTypeIdentifiers

struct SettingsSecurityTab: View {
    @ObservedObject var settings: AgentSettings
    @FocusState private var caFileFocused: Bool

    var body: some View {
        LazyVStack(spacing: LT.space12) {
            SettingsCardSection("TLS CONFIGURATION", glowHint: LT.warn) {
                SettingsToggleRow(icon: "shield.slash.fill", label: "Skip TLS Verification",
                                  isOn: $settings.tlsSkipVerify,
                                  onChange: { settings.markChanged() })

                HStack(spacing: LT.space8) {
                    Image(systemName: "doc.badge.clock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(caFileFocused ? LT.accent : LT.textMuted)
                        .animation(.easeInOut(duration: LT.animFast), value: caFileFocused)
                        .frame(width: 16)

                    TextField("CA Certificate", text: $settings.tlsCAFile,
                              prompt: Text("Path to CA cert").foregroundColor(LT.textMuted.opacity(0.5)))
                        .textFieldStyle(.plain)
                        .font(LT.inter(12))
                        .foregroundStyle(LT.textPrimary)
                        .focused($caFileFocused)
                        .onChange(of: settings.tlsCAFile) { _ in settings.markChanged() }

                    LTPillButton("Browse", icon: "folder.fill", color: LT.textSecondary) {
                        browseCAFile()
                    }
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, 7)
                .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
                .ltFocusRing(caFileFocused)
            }

            HStack(spacing: LT.space8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(LT.textMuted)
                Text("TLS settings apply when using wss:// hub URLs.")
                    .font(LT.inter(10, weight: .medium))
                    .foregroundStyle(LT.textMuted)
                Spacer()
            }
            .padding(.horizontal, LT.space4)
        }
    }

    // MARK: - Helpers

    private func browseCAFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "crt")!,
            .init(filenameExtension: "pem")!,
            .init(filenameExtension: "cer")!,
        ]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.tlsCAFile = url.path
            settings.markChanged()
        }
    }
}
