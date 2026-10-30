import SwiftUI

struct MenuBarConnectionSection: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var settings: AgentSettings
    @ObservedObject var runtime: LocalAPIRuntimeStore
    let onCopy: (String, String) -> Void
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        VStack(spacing: LT.space4) {
            LTSectionHeader("CONNECTION")
                .padding(.horizontal, LT.space12)
            LTGlassCard(glowColor: runtime.snapshot.hubConnectionState == "connected" ? LT.ok : nil) {
                VStack(spacing: LT.space8) {
                    HStack(spacing: LT.space8) {
                        LTIconBox(icon: connectionIcon, color: hubConnectionColor, size: 28)
                            .rotationEffect(.degrees(animationsActive && runtime.snapshot.hubConnectionState == "connecting" ? 360 : 0))
                            .animation(
                                animationsActive && runtime.snapshot.hubConnectionState == "connecting"
                                    ? .linear(duration: 2).repeatForever(autoreverses: false)
                                    : .default,
                                value: animationsActive && runtime.snapshot.hubConnectionState == "connecting"
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(hubConnectionLabel)
                                .font(LT.inter(11, weight: .semibold))
                                .foregroundStyle(LT.textPrimary)
                            let urlString = status.hubURL.isEmpty ? settings.hubURL : status.hubURL
                            if !urlString.isEmpty {
                                Text(urlString)
                                    .font(LT.mono(9))
                                    .foregroundStyle(LT.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer()

                        if runtime.snapshot.hubConnectionState == "connecting" {
                            LTConnectionPulse(color: hubConnectionColor, size: 6)
                        } else {
                            LTStatusDot(color: hubConnectionColor, size: 6)
                        }
                    }

                    if let fix = connectFix {
                        Text(fix)
                            .font(LT.inter(10))
                            .foregroundStyle(LT.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !status.assetID.isEmpty {
                        LTCopyRow(label: "Asset", value: status.assetID) {
                            onCopy(status.assetID, "Asset")
                        }
                    }
                    if !status.lastEvent.isEmpty && status.lastError.isEmpty {
                        LTCopyRow(label: "Event", value: status.lastEvent) {
                            onCopy(status.lastEvent, "Event")
                        }
                    }
                }
            }
            .ltScanShimmer(color: hubConnectionColor, delay: 0.3)
            .modifier(LTBorderTravel(isActive: runtime.snapshot.hubConnectionState == "connected", color: LT.ok))
            .ltValueFlash(watching: runtime.snapshot.hubConnectionState, color: hubConnectionColor)
            .padding(.horizontal, LT.space12)
        }
        .padding(.bottom, LT.space6)
    }

    /// The fix for the agent's last connect failure, shown while reconnecting.
    private var connectFix: String? {
        guard runtime.snapshot.hubConnectionState == "connecting" else { return nil }
        return HubConnectReason(code: runtime.snapshot.lastErrorReason)?.fix
    }

    private var connectionIcon: String {
        switch runtime.snapshot.hubConnectionState {
        case "connected": return "bolt.fill"
        case "connecting": return "arrow.triangle.2.circlepath"
        case "auth_failed": return "lock.slash.fill"
        default: return "bolt.slash.fill"
        }
    }

    private var hubConnectionColor: Color {
        switch runtime.snapshot.hubConnectionState {
        case "connected": return LT.ok
        case "connecting": return LT.warn
        case "auth_failed": return LT.bad
        default: return LT.textMuted
        }
    }

    private var hubConnectionLabel: String {
        switch runtime.snapshot.hubConnectionState {
        case "connected": return "Connected"
        case "connecting": return "Reconnecting..."
        case "auth_failed": return "Auth Failed"
        default: return "Disconnected"
        }
    }
}
