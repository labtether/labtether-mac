import SwiftUI

struct PopOutScreenSharingSection: View {
    @ObservedObject var screenSharing: ScreenSharingMonitor

    var body: some View {
        if screenSharing.hasChecked {
            LTGlassCard(glowColor: screenSharingGlowColor) {
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
            }
        }
    }

    private var screenSharingSubtitle: String {
        guard screenSharing.isEnabled else { return "Not enabled" }
        return screenSharing.hasControlAccess ? "Full control" : "Observe only"
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
            LTCapsuleBadge(text: "Disabled", color: LT.textMuted)
        }
    }

    private var screenSharingIcon: String {
        guard screenSharing.isEnabled else {
            return "display.trianglebadge.exclamationmark"
        }
        return screenSharing.hasControlAccess ? "display" : "display.trianglebadge.exclamationmark"
    }

    private var screenSharingIconColor: Color {
        guard screenSharing.isEnabled else { return LT.warn }
        return screenSharing.hasControlAccess ? LT.ok : LT.warn
    }

    private var screenSharingGlowColor: Color? {
        guard screenSharing.isEnabled else { return LT.warn }
        return screenSharing.hasControlAccess ? LT.ok : LT.warn
    }
}
