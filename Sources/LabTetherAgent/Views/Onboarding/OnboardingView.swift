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

    /// Fires a quick probe against `hubURL` and stores the result.
    func testConnection(tlsSkipVerify: Bool, tlsCAFile: String = "") async {
        guard !isTesting else { return }
        isTesting = true
        connectionTestResult = nil
        let result = await ConnectionTester.quickTest(hubURL: hubURL, tlsSkipVerify: tlsSkipVerify, tlsCAFile: tlsCAFile)
        isTesting = false
        connectionTestResult = result
    }

    /// Writes the draft into `settings` and marks setup complete.
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

/// Setup in one window: Hub address, token, test, Advanced (collapsed), Connect.
/// Hosted in its own `Window` scene and dismissed after starting or restarting the agent.
struct OnboardingView: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess

    @StateObject private var state = OnboardingState()
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
                LTDisclosureRow(title: L10n.onboardingAdvanced, detail: "Asset ID, group ID", isExpanded: $showAdvanced)
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
                    .disabled(!state.canConnect)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding-finish")
            }
            .padding(EdgeInsets(top: LT.space20, leading: 32, bottom: LT.space24, trailing: 32))
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .background(LT.canvas)
        .onAppear {
            state.hubURL = settings.hubURL
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
                            Task { await state.testConnection(tlsSkipVerify: settings.tlsSkipVerify, tlsCAFile: settings.tlsCAFile) }
                        } label: {
                            HStack(spacing: LT.space6) {
                                if state.isTesting { LTSpinnerArc(color: LT.text3, size: 11) }
                                Text(L10n.settingsTestConnection)
                            }
                        }
                        .buttonStyle(LTSecondaryButtonStyle())
                        .disabled(state.isTesting || AgentSettingsNormalization.canonicalHubWebSocketURL(from: state.hubURL) == nil)
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

    private func finish() {
        guard state.canConnect else { return }
        state.applyToSettings(settings)
        if agentProcess.isRunning {
            agentProcess.restart()
        } else {
            agentProcess.start()
        }
        dismiss()
    }
}
