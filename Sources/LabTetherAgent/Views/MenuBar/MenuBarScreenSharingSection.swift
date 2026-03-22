import SwiftUI

struct MenuBarScreenSharingSection: View {
    @ObservedObject var screenSharing: ScreenSharingMonitor
    @ObservedObject var settings: AgentSettings

    var body: some View {
        if settings.effectiveWebRTCEnabled && !ScreenRecordingPermission.isGranted {
            HStack(spacing: LT.space8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(LT.warn)
                Text("Screen Recording permission required for remote desktop")
                    .font(LT.inter(10, weight: .medium))
                    .foregroundStyle(LT.warn)
                Spacer()
                LTPillButton("Fix", icon: "gearshape", color: LT.warn) {
                    NSApp.activate(ignoringOtherApps: true)
                    ScreenRecordingPermission.openSettings()
                }
            }
            .padding(.horizontal, LT.space12)
            .padding(.bottom, LT.space4)
        }

        if screenSharing.hasChecked {
            LTGlassCard(glowColor: screenSharingGlowColor) {
                VStack(spacing: LT.space8) {
                    HStack(spacing: LT.space8) {
                        LTIconBox(icon: screenSharingIcon, color: screenSharingIconColor, size: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screen Sharing")
                                .font(LT.inter(11, weight: .semibold))
                                .foregroundStyle(LT.textPrimary)
                            Text(screenSharingSubtitle)
                                .font(LT.mono(9))
                                .foregroundStyle(LT.textMuted)
                        }
                        Spacer()
                        screenSharingBadge
                    }

                    if screenSharing.isEnabled && !screenSharing.hasControlAccess {
                        HStack(spacing: LT.space4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(LT.warn)
                            Text("Mouse/keyboard input disabled")
                                .font(LT.inter(10, weight: .medium))
                                .foregroundStyle(LT.warn)
                            Spacer()
                            LTPillButton("Fix", icon: "wrench", color: LT.warn) {
                                NSApp.activate(ignoringOtherApps: true)
                                ScreenSharingMonitor.grantControlAccess()
                            }
                        }
                    }
                }
            }
            .ltScanShimmer(color: screenSharingGlowColor ?? LT.textMuted, delay: 0.5)
            .padding(.horizontal, LT.space12)
            .padding(.bottom, LT.space6)
        }
    }

    @ViewBuilder
    private var screenSharingBadge: some View {
        if screenSharing.isEnabled {
            LTCapsuleBadge(
                text: screenSharing.hasControlAccess ? "On" : "Observe Only",
                color: screenSharing.hasControlAccess ? LT.ok : LT.warn,
                withGlow: screenSharing.hasControlAccess
            )
        } else {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                ScreenSharingMonitor.openSharingSettings()
            } label: {
                LTCapsuleBadge(text: "Enable", color: LT.warn)
            }
            .buttonStyle(.plain)
        }
    }

    private var screenSharingIcon: String {
        guard screenSharing.isEnabled else { return "display.trianglebadge.exclamationmark" }
        return screenSharing.hasControlAccess ? "display" : "display.trianglebadge.exclamationmark"
    }

    private var screenSharingIconColor: Color {
        guard screenSharing.isEnabled else { return LT.warn }
        return screenSharing.hasControlAccess ? LT.ok : LT.warn
    }

    private var screenSharingSubtitle: String {
        guard screenSharing.isEnabled else { return "Not enabled" }
        return screenSharing.hasControlAccess ? "Full control" : "Observe only"
    }

    private var screenSharingGlowColor: Color? {
        guard screenSharing.isEnabled else { return LT.warn }
        return screenSharing.hasControlAccess ? LT.ok : LT.warn
    }
}
