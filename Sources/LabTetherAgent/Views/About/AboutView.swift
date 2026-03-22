import SwiftUI
import AppKit

// MARK: - AboutView

/// A compact About window displaying app version, agent version, and system information.
///
/// Shows the app icon, version strings, device fingerprint with a copy button,
/// external links, and copyright notice in a fixed 340x380 non-resizable panel.
struct AboutView: View {

    // MARK: Dependencies

    @ObservedObject var metadata: LocalAPIMetadataStore

    /// Filesystem path to the device fingerprint file.
    let deviceFingerprintPath: String

    // MARK: Private State

    @State private var fingerprint: String = ""
    @State private var isFingerprintCopied = false

    // MARK: Body

    var body: some View {
        ZStack {
            LT.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: LT.space24)

                appIconView

                Spacer()
                    .frame(height: LT.space12)

                titleView

                Spacer()
                    .frame(height: LT.space16)

                versionBlock

                Spacer()
                    .frame(height: LT.space12)

                fingerprintRow

                Spacer()
                    .frame(height: LT.space24)

                Divider()
                    .overlay(LT.panelBorder)

                Spacer()
                    .frame(height: LT.space16)

                linksRow

                Spacer()
                    .frame(height: LT.space8)

                copyrightView

                Spacer()
                    .frame(height: LT.space16)
            }
            .padding(.horizontal, LT.space24)
        }
        .frame(width: 340, height: 380)
        .fixedSize()
        .onAppear { loadFingerprint() }
    }

    // MARK: - Subviews

    private var appIconView: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .shadow(color: LT.accent.opacity(0.15), radius: 12)
    }

    private var titleView: some View {
        Text(L10n.aboutTitle)
            .font(LT.sora(18, weight: .semibold))
            .foregroundStyle(LT.textPrimary)
    }

    private var versionBlock: some View {
        VStack(spacing: LT.space4) {
            Text(appVersionString)
                .font(LT.inter(13))
                .foregroundStyle(LT.textSecondary)
                .accessibilityIdentifier("about-version")

            Text("Agent: \(metadata.snapshot.agentVersion ?? L10n.aboutNotRunning)")
                .font(LT.mono(12))
                .foregroundStyle(LT.textSecondary)

            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                .font(LT.mono(12))
                .foregroundStyle(LT.textMuted)
        }
    }

    private var fingerprintRow: some View {
        HStack(spacing: LT.space6) {
            Text(truncatedFingerprint)
                .font(LT.mono(12))
                .foregroundStyle(LT.textMuted)

            Button {
                copyFingerprint()
            } label: {
                Image(systemName: isFingerprintCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isFingerprintCopied ? LT.ok : LT.textMuted)
                    .animation(.easeInOut(duration: LT.animFast), value: isFingerprintCopied)
            }
            .buttonStyle(.plain)
            .disabled(fingerprint.isEmpty)
            .help("Copy full device fingerprint")
            .accessibilityLabel("Copy device fingerprint")
        }
    }

    private var linksRow: some View {
        HStack(spacing: LT.space16) {
            externalLink(L10n.aboutWebsite, url: "https://labtether.com")
            externalLink(L10n.aboutDocumentation, url: "https://docs.labtether.com")
            externalLink(L10n.aboutSupport, url: "https://labtether.com/support")
        }
    }

    private func externalLink(_ label: String, url: String) -> some View {
        Link(label, destination: URL(string: url)!)
            .font(LT.inter(12))
            .foregroundStyle(LT.accent)
    }

    private var copyrightView: some View {
        Text("\u{00A9} 2026 LabTether")
            .font(LT.inter(11))
            .foregroundStyle(LT.textMuted)
    }

    // MARK: - Helpers

    /// Formatted version string: "Version X (Y)".
    private var appVersionString: String {
        let version = BundleHelper.appVersion
        let build = BundleHelper.buildNumber
        return "Version \(version) (\(build))"
    }

    /// Device fingerprint truncated to 16 characters with trailing ellipsis when longer.
    private var truncatedFingerprint: String {
        guard !fingerprint.isEmpty else { return "No fingerprint" }
        if fingerprint.count > 16 {
            return String(fingerprint.prefix(16)) + "..."
        }
        return fingerprint
    }

    /// Reads the fingerprint file from disk, trimming whitespace.
    private func loadFingerprint() {
        fingerprint = (try? String(contentsOfFile: deviceFingerprintPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Copies the full fingerprint to the system pasteboard and briefly shows a checkmark.
    private func copyFingerprint() {
        guard !fingerprint.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fingerprint, forType: .string)
        withAnimation { isFingerprintCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { isFingerprintCopied = false }
        }
    }
}
