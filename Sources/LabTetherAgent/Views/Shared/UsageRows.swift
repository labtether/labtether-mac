import AppKit
import SwiftUI

/// Network and temperature figures under the usage meters: ↓ 1.2 MB/s  ↑ 340 KB/s … 42°C.
struct NetworkFiguresRow: View {
    let network: MetricsNetworkPresentation
    /// The menu bar window shows binary rates; the pop-out shows decimal rates.
    var compact = true

    var body: some View {
        HStack(spacing: LT.space12) {
            figure("arrow.down", compact ? network.menuRXText : network.popOutRXText, label: "Download")
            figure("arrow.up", compact ? network.menuTXText : network.popOutTXText, label: "Upload")
            Spacer(minLength: LT.space8)
            if let temperature = compact ? network.menuTemperatureText : network.popOutTemperatureText {
                figure("thermometer.medium", temperature, label: "Temperature")
            }
        }
        .font(LT.font(12).monospacedDigit())
        .foregroundStyle(LT.text2)
    }

    private func figure(_ icon: String, _ value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LT.text3)
            Text(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// Screen Sharing state as one row: "Screen Sharing · Full control", or the
/// limited state in amber text with the button that fixes it.
struct ScreenSharingRow: View {
    @ObservedObject var screenSharing: ScreenSharingMonitor
    @ObservedObject var settings: AgentSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.effectiveWebRTCEnabled && !ScreenRecordingPermission.isGranted {
                row(icon: "rectangle.dashed.badge.record", title: "Screen Recording", value: "Not allowed", isProblem: true, fix: "Fix") {
                    NSApp.activate(ignoringOtherApps: true)
                    ScreenRecordingPermission.openSettings()
                }
            }
            if screenSharing.hasChecked {
                sharingRow
            }
            if let feedback = screenSharing.controlAccessFeedback {
                Text(feedback)
                    .font(LT.font(12))
                    .foregroundStyle(LT.badText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, LT.space8)
                    .padding(.bottom, LT.space4)
            }
        }
    }

    @ViewBuilder
    private var sharingRow: some View {
        if !screenSharing.isEnabled {
            row(icon: "lt.display", title: "Screen Sharing", value: "Off", isProblem: true, fix: "Turn on") {
                NSApp.activate(ignoringOtherApps: true)
                ScreenSharingMonitor.openSharingSettings()
            }
        } else if !screenSharing.hasControlAccess {
            row(icon: "lt.display", title: "Screen Sharing", value: "Observe only", isProblem: true, fix: "Fix") {
                NSApp.activate(ignoringOtherApps: true)
                screenSharing.requestControlAccess()
            }
        } else {
            row(icon: "lt.display", title: "Screen Sharing", value: "Full control", isProblem: false, fix: nil) {}
        }
    }

    private func row(
        icon: String,
        title: String,
        value: String,
        isProblem: Bool,
        fix: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: LT.space8) {
            LTIcon(name: icon)
            Text(title)
                .font(LT.font(13))
                .foregroundStyle(LT.text)
            Spacer(minLength: LT.space8)
            Text(value)
                .font(LT.font(12))
                .foregroundStyle(isProblem ? LT.warnText : LT.text3)
            if let fix {
                Button(fix, action: action)
                    .buttonStyle(LTSecondaryButtonStyle(height: 22, fontSize: 12))
            }
        }
        .padding(.horizontal, LT.space8)
        .frame(height: 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(value)")
    }
}
