import SwiftUI

/// Settings › Connection: the agent status sheet, then the Hub form, then Identity (collapsed).
struct SettingsConnectionTab: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var status: AgentStatus
    @ObservedObject var runtime: LocalAPIRuntimeStore
    /// Scrolls the view with this id into sight (the trust question must
    /// never sit below the window's edge with its buttons cut off).
    var reveal: (String) -> Void = { _ in }
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var isTestingConnection = false
    @State private var showDiagnosticsSheet = false
    @State private var showIdentity = false
    @State private var hubChange: HubChangeVerdict = .unchanged
    @StateObject private var trust = HubTrustFlow()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsAgentStatusSheet(
                settings: settings,
                agentProcess: agentProcess,
                status: status,
                runtime: runtime,
                issue: validationIssues.first { !AgentSettingsValidator.isHubAddressIssue($0) }
            )

            SettingsSection("Hub") {
                SettingsTextRow(
                    label: L10n.settingsHubURL,
                    text: $settings.hubURL,
                    prompt: "hub.lan:8443",
                    error: hubAddressError,
                    onChange: { settings.markChanged() }
                )
                .accessibilityIdentifier("settings-hub-url")
                .task(id: settings.hubURL) {
                    hubChange = .unchanged
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    hubChange = await settings.checkHubChange()
                }

                if let note = HubChangeNote(verdict: hubChange) {
                    LTFormRow(label: "") {
                        Text(note.text)
                            .font(LT.font(12))
                            .foregroundStyle(note.isWarning ? LT.warnText : LT.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LTFormRow(label: "") { testRow }

                if let offer = trust.offer {
                    HubTrustPanel(
                        offer: offer,
                        isWorking: trust.isWorking,
                        onTrust: {
                            Task {
                                connectionTestResult = await trust.trust(settings: settings)
                                settings.markChanged()
                            }
                        },
                        onCancel: { trust.cancel() }
                    )
                    .padding(.vertical, LT.space6)
                    .id(Self.trustPanelID)
                    .onAppear { DispatchQueue.main.async { reveal(Self.trustPanelID) } }
                }

                SettingsSecretRow(
                    label: L10n.settingsAPIToken,
                    text: $settings.apiToken,
                    prompt: "Agent token for this Mac",
                    onChange: { settings.markChanged() }
                )
                SettingsSecretRow(
                    label: L10n.settingsEnrollmentToken,
                    text: $settings.enrollmentToken,
                    prompt: "Instead of an API token",
                    onChange: { settings.markChanged() }
                )
            }
            .padding(.top, LT.space24)

            LTDisclosureRow(title: "Identity", detail: "Asset ID, group ID", isExpanded: $showIdentity)
                .padding(.top, LT.space12)

            if showIdentity {
                LTSheet(padding: EdgeInsets(top: 6, leading: LT.space16, bottom: 6, trailing: LT.space16)) {
                    VStack(spacing: 0) {
                        SettingsTextRow(
                            label: L10n.settingsAssetID,
                            text: $settings.assetID,
                            prompt: "From the host name",
                            onChange: { settings.markChanged() }
                        )
                        SettingsTextRow(
                            label: L10n.settingsGroupID,
                            text: $settings.groupID,
                            prompt: "Optional",
                            onChange: { settings.markChanged() }
                        )
                    }
                }
                .padding(.top, LT.space4)
            }
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            ConnectionDiagnosticsSheet(
                hubURL: settings.hubURL,
                tlsSkipVerify: settings.tlsSkipVerify,
                tlsCAFile: settings.effectiveTLSCAFile
            )
        }
    }

    private static let trustPanelID = "hub-trust-panel"

    private var testRow: some View {
        HStack(spacing: LT.space8) {
            Button {
                Task {
                    isTestingConnection = true
                    connectionTestResult = nil
                    connectionTestResult = await trust.test(hubURL: settings.hubURL, settings: settings)
                    isTestingConnection = false
                }
            } label: {
                HStack(spacing: LT.space6) {
                    if isTestingConnection {
                        LTSpinnerArc(color: LT.text3, size: 11)
                    }
                    Text(L10n.settingsTestConnection)
                }
            }
            .buttonStyle(LTSecondaryButtonStyle())
            .fixedSize()   // the result beside it wraps; the label is never cut ("Test conne…")
            .disabled(isTestingConnection || trust.offer != nil)
            .accessibilityIdentifier("settings-test-connection")
            .accessibilityHint("Tests the connection to the Hub")

            ConnectionTestResultText(result: connectionTestResult)

            Spacer(minLength: LT.space4)

            if connectionTestResult != nil {
                Button(L10n.settingsFullDiagnostics) { showDiagnosticsSheet = true }
                    .buttonStyle(LTTextButtonStyle(fontSize: 12))
                    .fixedSize()
            }
        }
    }

    private var validationIssues: [String] {
        settings.validationErrors()
    }

    private var hubAddressError: String? {
        // An empty address is shown as the prompt, not as an error.
        guard !settings.hubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return validationIssues.first(where: AgentSettingsValidator.isHubAddressIssue)
    }
}

/// "Reachable · 24 ms" in secondary text, or the failure in red.
struct ConnectionTestResultText: View {
    let result: ConnectionTestResult?

    var body: some View {
        switch result {
        case .success(let milliseconds):
            Text(ConnectionTestText.success(milliseconds))
                .font(LT.font(12).monospacedDigit())
                .foregroundStyle(LT.text2)
                .lineLimit(1)
                .fixedSize()   // "Reachable · 12 ms" stays on one line
        case .failure(let message):
            Text(message)
                .font(LT.font(12))
                .foregroundStyle(LT.badText)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .help(message)
        case nil:
            EmptyView()
        }
    }
}

/// The agent's state first: status word and uptime, with Restart and Stop (or Start).
struct SettingsAgentStatusSheet: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var status: AgentStatus
    @ObservedObject var runtime: LocalAPIRuntimeStore
    let issue: String?

    private var hero: AgentHeroPresentation {
        .resolve(agentProcess: agentProcess, status: status, runtime: runtime, settings: settings, includeHost: false)
    }

    private var canStartAgent: Bool {
        settings.isConfigured && settings.validationErrors().isEmpty && !agentProcess.isStarting
    }

    var body: some View {
        LTSheet(padding: EdgeInsets(top: LT.space12, leading: LT.space16, bottom: LT.space12, trailing: LT.space12)) {
            HStack(spacing: LT.space8) {
                HStack(alignment: .firstTextBaseline, spacing: LT.space8) {
                    Text(hero.label)
                        .font(LT.font(13, weight: .medium))
                        .foregroundStyle(LT.text)
                    Text(line.text)
                        .font(LT.font(13).monospacedDigit())
                        .foregroundStyle(line.color)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: LT.space8)
                controls
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if agentProcess.isRunning {
            Button(L10n.settingsRestart) { agentProcess.restart() }
                .buttonStyle(LTSecondaryButtonStyle())
            Button(L10n.settingsStop) { agentProcess.stop() }
                .buttonStyle(LTSecondaryButtonStyle())
        } else if agentProcess.isStarting {
            LTSpinnerArc(color: LT.text3, size: 14)
        } else {
            Button(L10n.settingsStart) { agentProcess.start() }
                .buttonStyle(LTSecondaryButtonStyle())
                .disabled(!canStartAgent)
        }
    }

    private var line: (text: String, color: Color) {
        if agentProcess.needsRestart && agentProcess.isRunning {
            return (L10n.settingsRestartRequired, LT.warnText)
        }
        if !agentProcess.isRunning && !agentProcess.isStarting {
            if let issue { return (issue, LT.badText) }
            if !settings.isConfigured { return ("Add the Hub address and a token", LT.warnText) }
        }
        let color: Color = hero.tone == .bad ? LT.badText : (hero.tone == .warn ? LT.warnText : LT.text3)
        return (hero.subtitle, color)
    }
}

/// The line under a changed Hub address: whether this Mac keeps its token.
struct HubChangeNote: Equatable {
    let text: String
    let isWarning: Bool

    init?(verdict: HubChangeVerdict) {
        switch verdict {
        case .unchanged:
            return nil
        case .sameHub:
            text = "Same Hub. This Mac keeps its token."
            isWarning = false
        case .otherHub:
            text = "Another Hub. Restart removes this Mac's token; then add a token from that Hub."
            isWarning = true
        case .unknown:
            text = "Can't confirm this is the same Hub. Restart asks before removing this Mac's token."
            isWarning = true
        }
    }
}
