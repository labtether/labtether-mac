import SwiftUI

// MARK: - OnboardingIdentityStep

/// Step 2 (final) of the onboarding wizard.
///
/// Collects optional asset and group identifiers, provides a connection test
/// probe, and presents the "Finish & Start Agent" call-to-action. The finish
/// callback is supplied by the parent `OnboardingView`.
struct OnboardingIdentityStep: View {

    // MARK: Dependencies

    @ObservedObject var state: OnboardingState
    let settings: AgentSettings
    let tlsSkipVerify: Bool

    // MARK: Inputs

    @Binding var assetID: String
    @Binding var groupID: String

    // MARK: Callbacks

    /// Called when the user taps "Finish & Start Agent". The parent is
    /// responsible for applying settings and launching the process.
    let onFinish: () -> Void

    // MARK: Private state

    @FocusState private var assetFocused: Bool
    @FocusState private var groupFocused: Bool

    // MARK: Body

    var body: some View {
        VStack(spacing: LT.space24) {
            headerSection
            identityFieldsSection
            connectionTestSection
            finishButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: LT.space16) {
            shieldIconView

            VStack(alignment: .leading, spacing: LT.space4) {
                Text(L10n.onboardingIdentityTitle)
                    .font(LT.sora(20, weight: .bold))
                    .foregroundStyle(LT.textPrimary)

                Text(L10n.onboardingIdentitySubtitle)
                    .font(LT.inter(13))
                    .foregroundStyle(LT.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Shield icon

    private var shieldIconView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [LT.ok.opacity(0.18), LT.ok.opacity(0.05)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .strokeBorder(LT.ok.opacity(0.25), lineWidth: 1)
                )

            Image(systemName: "shield.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(LT.ok)
                .shadow(color: LT.ok.opacity(0.4), radius: 8)
        }
    }

    // MARK: - Identity fields

    private var identityFieldsSection: some View {
        VStack(spacing: LT.space8) {
            // Asset ID
            HStack(spacing: LT.space8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(assetFocused ? LT.accent : LT.textMuted)
                    .animation(.easeInOut(duration: LT.animFast), value: assetFocused)
                    .frame(width: 16)

                TextField(
                    "Asset ID",
                    text: $assetID,
                    prompt: Text("Auto-detected from hostname")
                        .foregroundColor(LT.textMuted.opacity(0.5))
                )
                .textFieldStyle(.plain)
                .font(LT.inter(12))
                .foregroundStyle(LT.textPrimary)
                .focused($assetFocused)
            }
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space8 + 1)
            .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
            .ltFocusRing(assetFocused)

            // Group ID
            HStack(spacing: LT.space8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(groupFocused ? LT.accent : LT.textMuted)
                    .animation(.easeInOut(duration: LT.animFast), value: groupFocused)
                    .frame(width: 16)

                TextField(
                    "Group ID",
                    text: $groupID,
                    prompt: Text("Optional group assignment")
                        .foregroundColor(LT.textMuted.opacity(0.5))
                )
                .textFieldStyle(.plain)
                .font(LT.inter(12))
                .foregroundStyle(LT.textPrimary)
                .focused($groupFocused)
            }
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space8 + 1)
            .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
            .ltFocusRing(groupFocused)
        }
    }

    // MARK: - Connection test

    private var connectionTestSection: some View {
        HStack(spacing: LT.space12) {
            testConnectionButton
            connectionResultView
        }
    }

    private var testConnectionButton: some View {
        Button {
            Task {
                await state.testConnection(tlsSkipVerify: tlsSkipVerify)
            }
        } label: {
            HStack(spacing: LT.space6) {
                if state.isTesting {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(state.isTesting ? "Testing..." : L10n.settingsTestConnection)
                    .font(LT.inter(12, weight: .semibold))
            }
            .foregroundStyle(LT.accent)
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space6)
            .background(
                Capsule()
                    .fill(LT.accent.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(LT.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(state.isTesting)
    }

    @ViewBuilder
    private var connectionResultView: some View {
        if let result = state.connectionTestResult {
            HStack(spacing: LT.space6) {
                switch result {
                case .success(let ms):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LT.ok)
                    Text("Reachable (\(ms) ms)")
                        .font(LT.inter(12, weight: .medium))
                        .foregroundStyle(LT.ok)

                case .failure(let message):
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LT.bad)
                    Text(message)
                        .font(LT.inter(12, weight: .medium))
                        .foregroundStyle(LT.bad)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(LT.springSnappy, value: state.connectionTestResult)
        }
    }

    // MARK: - Finish button

    private var finishButton: some View {
        Button {
            onFinish()
        } label: {
            HStack(spacing: LT.space8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(L10n.onboardingFinish)
                    .font(LT.inter(14, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LT.space12)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LT.accent, LT.accent.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: LT.accent.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(LTPressButtonStyle())
        .accessibilityIdentifier("onboarding-finish")
    }
}
