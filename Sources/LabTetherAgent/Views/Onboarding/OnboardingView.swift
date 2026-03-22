import SwiftUI

// MARK: - OnboardingTokenType

/// The authentication mode selected during onboarding.
enum OnboardingTokenType: String, CaseIterable {
    /// Short-lived enrollment token issued by the hub.
    case enrollment = "enrollment"
    /// Long-lived API token for direct agent authentication.
    case apiToken = "apiToken"

    /// Human-readable label used in the segmented picker.
    var displayName: String {
        switch self {
        case .enrollment: return "Enrollment Token"
        case .apiToken:   return "API Token"
        }
    }
}

// MARK: - OnboardingState

/// Observable draft values for the multi-step onboarding wizard.
///
/// All mutations must happen on the `@MainActor` because the class publishes
/// to SwiftUI state. `testConnection(tlsSkipVerify:)` dispatches the network
/// probe on a non-isolated background task and then re-enters `@MainActor`
/// to apply the result.
@MainActor
final class OnboardingState: ObservableObject {

    // MARK: Draft fields

    /// The hub WebSocket URL entered by the user (e.g. `wss://host:8443/ws/agent`).
    @Published var hubURL: String = ""

    /// Which authentication mode the user selected.
    @Published var tokenType: OnboardingTokenType = .enrollment

    /// The raw token string (enrollment or API token, depending on `tokenType`).
    @Published var tokenValue: String = ""

    /// Optional asset identifier to send to the hub.
    @Published var assetID: String = ""

    /// Optional group identifier to send to the hub.
    @Published var groupID: String = ""

    // MARK: Wizard navigation

    /// Current step index: 0 = Welcome, 1 = Auth, 2 = Identity.
    @Published var currentStep: Int = 0

    // MARK: Connection test

    /// Result of the last connection probe, or `nil` if not yet tested.
    @Published var connectionTestResult: ConnectionTestResult?

    /// `true` while a connection probe is in flight.
    @Published var isTesting: Bool = false

    // MARK: - Computed gating

    /// Whether the user has filled in enough data to leave step 0.
    var canAdvanceFromStep0: Bool {
        !hubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the user has filled in enough data to leave step 1.
    var canAdvanceFromStep1: Bool {
        !tokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    /// Fires a quick HTTP probe against `hubURL` and stores the result.
    ///
    /// - Parameter tlsSkipVerify: When `true`, server certificate errors are ignored.
    func testConnection(tlsSkipVerify: Bool) async {
        guard !isTesting else { return }
        isTesting = true
        connectionTestResult = nil

        let url = hubURL
        let result = await ConnectionTester.quickTest(hubURL: url, tlsSkipVerify: tlsSkipVerify)

        isTesting = false
        connectionTestResult = result
    }

    /// Writes the wizard draft into `settings` and marks onboarding complete.
    ///
    /// This must be called on the main actor because `AgentSettings` publishes
    /// via `@AppStorage` / `@Published` properties.
    func applyToSettings(_ settings: AgentSettings) {
        settings.hubURL = hubURL.trimmingCharacters(in: .whitespacesAndNewlines)

        switch tokenType {
        case .enrollment:
            settings.enrollmentToken = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.apiToken = ""
        case .apiToken:
            settings.apiToken = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.enrollmentToken = ""
        }

        settings.assetID = assetID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.groupID = groupID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.hasCompletedOnboarding = true
        settings.markChanged()
    }
}

// MARK: - OnboardingView

/// A three-step wizard that collects hub URL, authentication token, and optional
/// asset identity before starting the agent for the first time.
///
/// The view is intended to be hosted in a dedicated SwiftUI `Window` scene and
/// dismissed once `applyToSettings` + `agentProcess.start()` have been called.
struct OnboardingView: View {

    // MARK: Dependencies

    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess

    // MARK: Private state

    @StateObject private var state = OnboardingState()

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, LT.space24)
                .padding(.bottom, LT.space20)

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, LT.space24)

            navigationBar
                .padding(.horizontal, LT.space24)
                .padding(.bottom, LT.space24)
                .padding(.top, LT.space16)
        }
        .frame(width: 500, height: 450)
        .background(LT.bg)
        .onAppear {
            state.hubURL = settings.hubURL
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: LT.space8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == state.currentStep ? LT.accent : LT.panelBorder)
                    .frame(width: index == state.currentStep ? 20 : 8, height: 6)
                    .animation(LT.springSnappy, value: state.currentStep)
            }
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch state.currentStep {
        case 0:
            OnboardingWelcomeStep(hubURL: $state.hubURL)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case 1:
            OnboardingAuthStep(tokenType: $state.tokenType, tokenValue: $state.tokenValue)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case 2:
            OnboardingIdentityStep(
                state: state,
                settings: settings,
                tlsSkipVerify: settings.tlsSkipVerify,
                assetID: $state.assetID,
                groupID: $state.groupID,
                onFinish: finish
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        default:
            EmptyView()
        }
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            if state.currentStep > 0 {
                Button(L10n.onboardingBack) {
                    withAnimation(LT.springSmooth) {
                        state.currentStep -= 1
                    }
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

            Spacer()

            if state.currentStep < 2 {
                Button(L10n.onboardingNext) {
                    withAnimation(LT.springSmooth) {
                        state.currentStep += 1
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!canAdvanceCurrentStep)
                .opacity(canAdvanceCurrentStep ? 1 : 0.4)
                .accessibilityIdentifier("onboarding-next")
            }
        }
    }

    // MARK: - Helpers

    private var canAdvanceCurrentStep: Bool {
        switch state.currentStep {
        case 0: return state.canAdvanceFromStep0
        case 1: return state.canAdvanceFromStep1
        default: return true
        }
    }

    private func finish() {
        state.applyToSettings(settings)
        agentProcess.start()
    }
}

// MARK: - Button styles

/// Accent-filled primary action button used for wizard progression.
private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.inter(13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, LT.space20)
            .padding(.vertical, LT.space8)
            .background(
                Capsule()
                    .fill(LT.accent.opacity(isHovered ? 0.9 : 0.75))
            )
            .shadow(color: LT.accent.opacity(isHovered ? 0.45 : 0.25), radius: isHovered ? 12 : 6)
            .scaleEffect(configuration.isPressed ? LT.pressScale : 1)
            .animation(LT.springSnappy, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: LT.animFast), value: isHovered)
    }
}

/// Muted secondary button used for backward navigation.
private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.inter(13, weight: .medium))
            .foregroundStyle(isHovered ? LT.textPrimary : LT.textSecondary)
            .padding(.horizontal, LT.space16)
            .padding(.vertical, LT.space8)
            .background(
                Capsule()
                    .fill(LT.panelGlass.opacity(isHovered ? 1.6 : 1))
            )
            .overlay(
                Capsule()
                    .strokeBorder(LT.panelBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? LT.pressScale : 1)
            .animation(LT.springSnappy, value: configuration.isPressed)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: LT.animFast), value: isHovered)
    }
}
