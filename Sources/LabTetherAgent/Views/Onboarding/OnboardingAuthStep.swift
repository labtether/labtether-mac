import SwiftUI

// MARK: - OnboardingAuthStep

/// Step 1 of the onboarding wizard.
///
/// Lets the user choose between an enrollment token and an API token,
/// then enter the chosen credential. A show/hide eye toggle makes it
/// easy to verify the value without leaving the secure field permanently visible.
struct OnboardingAuthStep: View {

    // MARK: Inputs

    @Binding var tokenType: OnboardingTokenType
    @Binding var tokenValue: String

    // MARK: Private state

    @State private var showToken = false
    @FocusState private var tokenFocused: Bool

    // MARK: Body

    var body: some View {
        VStack(spacing: LT.space24) {
            headerSection
            tokenTypeSection
            tokenInputSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: LT.space16) {
            keyIconView

            VStack(alignment: .leading, spacing: LT.space4) {
                Text(L10n.onboardingAuthTitle)
                    .font(LT.sora(20, weight: .bold))
                    .foregroundStyle(LT.textPrimary)

                Text(L10n.onboardingAuthSubtitle)
                    .font(LT.inter(13))
                    .foregroundStyle(LT.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Key icon

    private var keyIconView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [LT.accent.opacity(0.18), LT.accent.opacity(0.05)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .strokeBorder(LT.accent.opacity(0.25), lineWidth: 1)
                )

            Image(systemName: "key.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(LT.accent)
                .shadow(color: LT.accent.opacity(0.4), radius: 8)
        }
    }

    // MARK: - Token type picker

    private var tokenTypeSection: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            Text("Token Type")
                .font(LT.inter(11, weight: .semibold))
                .foregroundStyle(LT.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Picker("Token Type", selection: $tokenType) {
                ForEach(OnboardingTokenType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: tokenType) { _ in
                tokenValue = ""
                showToken = false
            }

            tokenTypeHelpText
        }
    }

    @ViewBuilder
    private var tokenTypeHelpText: some View {
        HStack(alignment: .top, spacing: LT.space6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(LT.textMuted)
                .padding(.top, 1)

            Text(tokenType == .enrollment
                 ? "Enrollment tokens register this device and are consumed on first connection. Generate one from the hub dashboard."
                 : "API tokens allow ongoing authentication. Use an owner token or a dedicated agent token from the hub settings.")
                .font(LT.inter(11))
                .foregroundStyle(LT.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Token input

    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            Text(tokenType == .enrollment ? "Enrollment Token" : "API Token")
                .font(LT.inter(11, weight: .semibold))
                .foregroundStyle(LT.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            tokenField
        }
    }

    private var tokenField: some View {
        HStack(spacing: LT.space8) {
            Image(systemName: tokenType == .enrollment ? "ticket.fill" : "key.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tokenFocused ? LT.accent : LT.textMuted)
                .animation(.easeInOut(duration: LT.animFast), value: tokenFocused)
                .frame(width: 16)

            if showToken {
                TextField(
                    "Token",
                    text: $tokenValue,
                    prompt: Text(tokenType == .enrollment ? "Paste enrollment token" : "Paste API token")
                        .foregroundColor(LT.textMuted.opacity(0.5))
                )
                .textFieldStyle(.plain)
                .font(LT.mono(12))
                .foregroundStyle(LT.textPrimary)
                .focused($tokenFocused)
            } else {
                SecureField(
                    "Token",
                    text: $tokenValue,
                    prompt: Text(tokenType == .enrollment ? "Paste enrollment token" : "Paste API token")
                        .foregroundColor(LT.textMuted.opacity(0.5))
                )
                .textFieldStyle(.plain)
                .font(LT.mono(12))
                .foregroundStyle(LT.textPrimary)
                .focused($tokenFocused)
            }

            Button {
                showToken.toggle()
            } label: {
                Image(systemName: showToken ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(showToken ? LT.accent : LT.textMuted)
            }
            .buttonStyle(.plain)
            .help(showToken ? "Hide token" : "Show token")
            .accessibilityLabel(showToken ? "Hide token" : "Show token")
        }
        .padding(.horizontal, LT.space12)
        .padding(.vertical, LT.space8 + 1)
        .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
        .ltFocusRing(tokenFocused)
    }
}
