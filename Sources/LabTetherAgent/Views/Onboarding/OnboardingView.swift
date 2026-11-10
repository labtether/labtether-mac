import AppKit
import SwiftUI

// MARK: - OnboardingTokenType

/// The authentication mode selected during setup.
enum OnboardingTokenType: String, CaseIterable {
    /// Short-lived enrollment token issued by the hub.
    case enrollment = "enrollment"
    /// Long-lived API token for direct agent authentication.
    case apiToken = "apiToken"

    /// Label in the segmented control.
    var displayName: String {
        switch self {
        case .enrollment: return L10n.settingsEnrollmentToken
        case .apiToken:   return L10n.settingsAPIToken
        }
    }
}

// MARK: - OnboardingState

/// Draft values for the setup window.
///
/// All mutations happen on the main actor because the class publishes to
/// SwiftUI state. `testConnection` awaits the probe and applies the result here.
@MainActor
final class OnboardingState: ObservableObject {
    /// The Hub address as typed: host:port, https:// or wss:// are all accepted.
    @Published var hubURL: String = ""
    @Published var tokenType: OnboardingTokenType = .enrollment
    /// The enrollment or API token, depending on `tokenType`.
    @Published var tokenValue: String = ""
    @Published var assetID: String = ""
    @Published var groupID: String = ""

    /// Result of the last connection probe, or `nil` if not yet tested.
    @Published var connectionTestResult: ConnectionTestResult?
    /// `true` while a connection probe is in flight.
    @Published var isTesting: Bool = false

    /// Connect is available once the address is usable and a token is entered.
    var canConnect: Bool {
        AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL) != nil
            && !tokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What Connect should do after the certificate has been looked at.
    enum ConnectStep: Equatable {
        /// Settings are saved and the agent may start: the token can be sent.
        case go
        /// The trust question is on screen; nothing is saved or sent.
        case waitingForTrust
        /// The Hub's certificate is not acceptable; the words are shown.
        case stopped
    }

    /// Connect was pressed and waits for the trust answer.
    private var connectAfterTrust = false

    /// Test connection: the result, or the trust question when the Hub uses
    /// its own certificate.
    func testConnection(settings: AgentSettings, trust: HubTrustFlow) async {
        guard !isTesting else { return }
        isTesting = true
        connectionTestResult = nil
        connectAfterTrust = false
        connectionTestResult = await trust.test(hubURL: hubURL, settings: settings)
        isTesting = false
    }

    /// Connect: looks at the Hub's certificate first. The token is written to
    /// the settings (and so sent by the agent) only on `.go`.
    func connect(settings: AgentSettings, trust: HubTrustFlow) async -> ConnectStep {
        guard canConnect, !isTesting else { return .stopped }
        isTesting = true
        defer { isTesting = false }
        connectionTestResult = nil
        let result = await trust.test(hubURL: hubURL, settings: settings)
        if trust.offer != nil {
            connectAfterTrust = true
            return .waitingForTrust
        }
        if trust.stoppedOnCertificate {
            connectionTestResult = result
            return .stopped
        }
        // Unreachable or slow Hubs are the agent's to retry, as before.
        applyToSettings(settings)
        return .go
    }

    /// "Trust this Hub" was pressed.
    func trustHub(settings: AgentSettings, trust: HubTrustFlow) async -> ConnectStep {
        let result = await trust.trust(settings: settings)
        let wasConnecting = connectAfterTrust
        connectAfterTrust = false
        guard case .success = result else {
            connectionTestResult = result
            return .stopped
        }
        guard wasConnecting, canConnect else {
            connectionTestResult = result
            return .stopped
        }
        applyToSettings(settings)
        return .go
    }

    func cancelTrust(_ trust: HubTrustFlow) {
        connectAfterTrust = false
        trust.cancel()
    }

    /// Writes the draft into `settings`, marks setup complete and turns on
    /// Start at login.
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
        LoginItemManager.turnOnAfterSetup(settings)
        settings.markChanged()
    }
}

// MARK: - OnboardingView

/// Setup in one window: Hub address, token, test, Advanced (collapsed), Connect.
/// Hosted in its own `Window` scene and dismissed after starting or restarting the agent.
struct OnboardingView: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess

    @StateObject private var state = OnboardingState()
    @StateObject private var trust = HubTrustFlow()
    @State private var showAdvanced = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                LTBrandMark(size: 56)
                    .accessibilityHidden(true)
                Text(L10n.onboardingWelcomeTitle)
                    .font(LT.font(22, weight: .semibold))
                    .foregroundStyle(LT.text)
                    .padding(.top, LT.space16)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.onboardingWelcomeSubtitle)
                    .font(LT.font(13))
                    .foregroundStyle(LT.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, LT.space6)
            }
            .padding(.horizontal, 32)
            .padding(.top, LT.space4)

            VStack(alignment: .leading, spacing: 0) {
                form
                if let offer = trust.offer {
                    HubTrustPanel(
                        offer: offer,
                        isWorking: trust.isWorking,
                        onTrust: { Task { if await state.trustHub(settings: settings, trust: trust) == .go { startAndClose() } } },
                        onCancel: { state.cancelTrust(trust) }
                    )
                    .padding(.top, LT.space12)
                }
                // Not animated: the window follows its content only for plain
                // changes, and an animated one left Connect below the bottom edge.
                LTDisclosureRow(title: L10n.onboardingAdvanced, detail: "Asset ID, group ID",
                                isExpanded: $showAdvanced, animated: false)
                    .padding(.top, LT.space12)
                if showAdvanced {
                    advancedFields
                        .padding(.top, LT.space4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, LT.space24)

            HStack {
                Spacer()
                Button(L10n.onboardingFinish, action: finish)
                    .buttonStyle(LTPrimaryButtonStyle(height: 32, radius: LT.radiusControl))
                    .disabled(!state.canConnect || state.isTesting || trust.offer != nil)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding-finish")
            }
            .padding(EdgeInsets(top: LT.space20, leading: 32, bottom: LT.space24, trailing: 32))
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .background(LT.canvas)
        .onAppear {
            // First launch shows the empty field and its example, not the built-in default.
            state.hubURL = settings.hubURL == AgentSettings.defaultHubURL ? "" : settings.hubURL
        }
    }

    private var form: some View {
        LTSheet(padding: EdgeInsets(top: 6, leading: LT.space16, bottom: 6, trailing: LT.space16)) {
            VStack(spacing: 0) {
                LTFormRow(label: L10n.settingsHubURL) {
                    LTTextField(label: L10n.settingsHubURL, text: $state.hubURL, prompt: "hub.lan:8443", accessory: {
                        Button(L10n.onboardingPasteClipboard, action: pasteHubAddress)
                            .buttonStyle(LTTextButtonStyle(fontSize: 12))
                            .accessibilityLabel("Paste Hub address")
                    })
                }
                LTFormRow(label: L10n.onboardingToken, alignment: .top) {
                    VStack(alignment: .leading, spacing: LT.space8) {
                        Picker("Token type", selection: $state.tokenType) {
                            ForEach(OnboardingTokenType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .onChange(of: state.tokenType) { _ in state.tokenValue = "" }
                        LTSecretField(
                            label: state.tokenType.displayName,
                            text: $state.tokenValue,
                            prompt: state.tokenType == .enrollment ? "Paste the enrollment token" : "Paste the API token"
                        )
                    }
                }
                LTFormRow(label: "") {
                    HStack(spacing: 10) {
                        Button {
                            Task { await state.testConnection(settings: settings, trust: trust) }
                        } label: {
                            HStack(spacing: LT.space6) {
                                if state.isTesting { LTSpinnerArc(color: LT.text3, size: 11) }
                                Text(L10n.settingsTestConnection)
                            }
                        }
                        .buttonStyle(LTSecondaryButtonStyle())
                        .fixedSize()
                        .disabled(state.isTesting || trust.offer != nil
                                  || AgentSettingsNormalization.canonicalHubWebSocketURL(from: state.hubURL) == nil)
                        ConnectionTestResultText(result: state.connectionTestResult)
                    }
                }
            }
        }
    }

    private var advancedFields: some View {
        LTSheet(padding: EdgeInsets(top: 6, leading: LT.space16, bottom: 6, trailing: LT.space16)) {
            VStack(spacing: 0) {
                LTFormRow(label: L10n.settingsAssetID) {
                    LTTextField(label: L10n.settingsAssetID, text: $state.assetID, prompt: "From the host name")
                }
                LTFormRow(label: L10n.settingsGroupID) {
                    LTTextField(label: L10n.settingsGroupID, text: $state.groupID, prompt: "Optional")
                }
            }
        }
    }

    private func pasteHubAddress() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { state.hubURL = trimmed }
    }

    /// Connect: the certificate is looked at first; the agent (and with it
    /// the token) starts only once the Hub verifies.
    private func finish() {
        Task {
            if await state.connect(settings: settings, trust: trust) == .go { startAndClose() }
        }
    }

    private func startAndClose() {
        if agentProcess.isRunning {
            agentProcess.restart()
        } else {
            agentProcess.start()
        }
        dismiss()
    }
}
