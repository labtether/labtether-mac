import AppKit
import SwiftUI

/// "Update available" menu item. It only opens the GitHub release page;
/// the signed app is never replaced in place.
struct MenuBarAppUpdateSection: View {
    @ObservedObject var updates: AppUpdateChecker

    var body: some View {
        if let update = updates.availableUpdate {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSWorkspace.shared.open(update.pageURL)
            } label: {
                HStack(spacing: LT.space8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LT.accent)
                    Text("Update available (v\(update.version))")
                        .font(LT.inter(11, weight: .semibold))
                        .foregroundStyle(LT.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LT.textMuted)
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, LT.space6)
                .background(
                    LT.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the LabTether for macOS release page")
            .accessibilityLabel("Update available, version \(update.version). Opens the release page.")
            .padding(.horizontal, LT.space12)
            .padding(.bottom, LT.space6)
        }
    }
}
