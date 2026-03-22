import SwiftUI

struct SettingsConnectionTab: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var status: AgentStatus
    @State private var showToken = false
    @FocusState private var tokenFocused: Bool
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var isTestingConnection = false
    @State private var showDiagnosticsSheet = false

    var body: some View {
        LazyVStack(spacing: LT.space12) {
            // Hub Connection card
            SettingsCardSection("HUB CONNECTION") {
                SettingsIconField(icon: "globe", label: "Hub URL",
                                  text: $settings.hubURL,
                                  prompt: "wss://localhost:8443/ws/agent",
                                  onChange: { settings.markChanged() })
                .accessibilityIdentifier("settings-hub-url")

                // Test Connection row
                HStack(spacing: LT.space8) {
                    Button {
                        Task {
                            isTestingConnection = true
                            connectionTestResult = nil
                            connectionTestResult = await ConnectionTester.quickTest(
                                hubURL: settings.hubURL,
                                tlsSkipVerify: settings.tlsSkipVerify
                            )
                            isTestingConnection = false
                        }
                    } label: {
                        HStack(spacing: LT.space4) {
                            if isTestingConnection {
                                LTSpinnerArc(color: LT.accent, size: 11)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 11))
                            }
                            Text(L10n.settingsTestConnection)
                                .font(LT.inter(12))
                        }
                        .foregroundStyle(LT.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingConnection)
                    .accessibilityIdentifier("settings-test-connection")
                    .accessibilityHint("Tests connectivity to the hub server")

                    if let result = connectionTestResult {
                        switch result {
                        case .success(let responseTimeMs):
                            HStack(spacing: LT.space4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LT.ok)
                                Text("\(responseTimeMs) ms")
                                    .font(LT.mono(11))
                                    .foregroundStyle(LT.textSecondary)
                            }
                        case .failure(let error):
                            HStack(spacing: LT.space4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(LT.bad)
                                Text(error)
                                    .font(LT.mono(11))
                                    .foregroundStyle(LT.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    if connectionTestResult != nil {
                        Button(L10n.settingsFullDiagnostics) {
                            showDiagnosticsSheet = true
                        }
                        .buttonStyle(.plain)
                        .font(LT.inter(11))
                        .foregroundStyle(LT.textSecondary)
                    }
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, 6)

                HStack(spacing: LT.space8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokenFocused ? LT.accent : LT.textMuted)
                        .animation(.easeInOut(duration: LT.animFast), value: tokenFocused)
                        .frame(width: 16)

                    if showToken {
                        TextField("API Token", text: $settings.apiToken,
                                  prompt: Text("Owner or agent token").foregroundColor(LT.textMuted.opacity(0.5)))
                            .textFieldStyle(.plain)
                            .font(LT.inter(12))
                            .foregroundStyle(LT.textPrimary)
                            .focused($tokenFocused)
                            .onChange(of: settings.apiToken) { _ in settings.markChanged() }
                    } else {
                        SecureField("API Token", text: $settings.apiToken,
                                    prompt: Text("Owner or agent token").foregroundColor(LT.textMuted.opacity(0.5)))
                            .textFieldStyle(.plain)
                            .font(LT.inter(12))
                            .foregroundStyle(LT.textPrimary)
                            .focused($tokenFocused)
                            .onChange(of: settings.apiToken) { _ in settings.markChanged() }
                    }

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(LT.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showToken ? "Hide token" : "Show token")
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, 7)
                .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
                .ltFocusRing(tokenFocused)

                SettingsSecureIconField(icon: "ticket.fill", label: "Enrollment Token",
                                        text: $settings.enrollmentToken,
                                        prompt: "Alternative to API token",
                                        onChange: { settings.markChanged() })
            }

            // Identity card
            SettingsCardSection("IDENTITY") {
                SettingsIconField(icon: "desktopcomputer", label: "Asset ID",
                                  text: $settings.assetID,
                                  prompt: "Auto-detected from hostname",
                                  onChange: { settings.markChanged() })

                SettingsIconField(icon: "mappin.circle.fill", label: "Group ID",
                                  text: $settings.groupID,
                                  prompt: "Optional group assignment",
                                  onChange: { settings.markChanged() })
            }

            // Agent Control card
            SettingsCardSection("AGENT CONTROL") {
                HStack(spacing: LT.space8) {
                    // State indicator
                    LTStatusDot(color: status.state.color, size: 6)
                    Text(status.state.rawValue)
                        .font(LT.inter(11, weight: .medium))
                        .foregroundStyle(LT.textSecondary)

                    if let pid = status.pid, agentProcess.isRunning {
                        LTCapsuleBadge(text: "PID \(pid)", color: LT.textMuted)
                    }

                    Spacer()

                    if agentProcess.needsRestart {
                        HStack(spacing: LT.space4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("Restart required")
                                .font(LT.inter(10, weight: .medium))
                        }
                        .foregroundStyle(LT.warn)
                    } else if agentProcess.isStarting {
                        Text("Launching agent…")
                            .font(LT.inter(10, weight: .medium))
                            .foregroundStyle(LT.accent)
                    } else if let issue = validationIssues.first {
                        Text(issue)
                            .font(LT.inter(10, weight: .medium))
                            .foregroundStyle(LT.warn)
                    } else if !settings.isConfigured {
                        Text("Hub URL and token required")
                            .font(LT.inter(10, weight: .medium))
                            .foregroundStyle(LT.warn)
                    }
                }

                HStack(spacing: LT.space8) {
                    if agentProcess.isRunning {
                        LTPillButton("Restart", icon: "arrow.clockwise", color: LT.warn) {
                            agentProcess.restart()
                        }
                        LTPillButton("Stop", icon: "stop.fill", color: LT.bad) {
                            agentProcess.stop()
                        }
                    } else if agentProcess.isStarting {
                        HStack(spacing: LT.space8) {
                            LTSpinnerArc(color: LT.accent, size: 14)
                            Text("Starting…")
                                .font(LT.inter(11, weight: .semibold))
                                .foregroundStyle(LT.accent)
                        }
                        .padding(.horizontal, LT.space12)
                        .padding(.vertical, LT.space4 + 2)
                        .background(LT.accent.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(LT.accent.opacity(0.25), lineWidth: 1))
                    } else {
                        LTPillButton("Start", icon: "play.fill", color: LT.ok) {
                            agentProcess.start()
                        }
                        .opacity(canStartAgent ? 1 : 0.4)
                        .allowsHitTesting(canStartAgent)
                    }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            ConnectionDiagnosticsSheet(
                hubURL: settings.hubURL,
                tlsSkipVerify: settings.tlsSkipVerify
            )
        }
    }

    // MARK: - Computed Properties

    var validationIssues: [String] {
        settings.validationErrors()
    }

    var canStartAgent: Bool {
        settings.isConfigured && validationIssues.isEmpty && !agentProcess.isStarting
    }
}
