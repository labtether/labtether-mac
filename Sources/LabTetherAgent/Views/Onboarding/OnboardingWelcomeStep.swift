import SwiftUI
import AppKit

// MARK: - OnboardingWelcomeStep

/// Step 0 of the onboarding wizard.
///
/// Displays the app icon, a brief welcome message, and a hub URL text field
/// with a clipboard-paste shortcut. The hub URL is the only required input
/// at this stage.
struct OnboardingWelcomeStep: View {

    // MARK: Inputs

    @Binding var hubURL: String

    // MARK: Private state

    @FocusState private var urlFocused: Bool

    // MARK: Body

    var body: some View {
        VStack(spacing: LT.space24) {
            headerSection
            urlInputSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: LT.space16) {
            appIconView

            VStack(alignment: .leading, spacing: LT.space4) {
                Text(L10n.onboardingWelcomeTitle)
                    .font(LT.sora(20, weight: .bold))
                    .foregroundStyle(LT.textPrimary)

                Text(L10n.onboardingWelcomeSubtitle)
                    .font(LT.inter(13))
                    .foregroundStyle(LT.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - App icon

    private var appIconView: some View {
        Group {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
            } else {
                RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                    .fill(LT.accent.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "network")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(LT.accent)
                    )
            }
        }
        .shadow(color: LT.accent.opacity(0.2), radius: 12, y: 4)
    }

    // MARK: - URL input

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            HStack {
                Text("Hub URL")
                    .font(LT.inter(11, weight: .semibold))
                    .foregroundStyle(LT.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                pasteButton
            }

            HStack(spacing: LT.space8) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(urlFocused ? LT.accent : LT.textMuted)
                    .animation(.easeInOut(duration: LT.animFast), value: urlFocused)
                    .frame(width: 16)

                TextField(
                    "Hub URL",
                    text: $hubURL,
                    prompt: Text("wss://localhost:8443/ws/agent")
                        .foregroundColor(LT.textMuted.opacity(0.5))
                )
                .textFieldStyle(.plain)
                .font(LT.mono(13))
                .foregroundStyle(LT.textPrimary)
                .focused($urlFocused)
            }
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space8 + 1)
            .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
            .ltFocusRing(urlFocused)

            Text("Enter the WebSocket URL for your hub. It should start with wss:// or ws://.")
                .font(LT.inter(11))
                .foregroundStyle(LT.textMuted)
        }
    }

    // MARK: - Paste button

    private var pasteButton: some View {
        Button {
            if let text = NSPasteboard.general.string(forType: .string) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    hubURL = trimmed
                }
            }
        } label: {
            HStack(spacing: LT.space4) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .medium))
                Text("Paste from Clipboard")
                    .font(LT.inter(11, weight: .medium))
            }
            .foregroundStyle(LT.accent)
            .padding(.horizontal, LT.space8)
            .padding(.vertical, LT.space4)
            .background(
                Capsule()
                    .fill(LT.accent.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .strokeBorder(LT.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste hub URL from clipboard")
    }
}
