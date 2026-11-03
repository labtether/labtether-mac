import SwiftUI

/// Screen Sharing as a one-row sheet, the same row as the menu bar window.
struct PopOutScreenSharingSection: View {
    @ObservedObject var screenSharing: ScreenSharingMonitor
    @ObservedObject var settings: AgentSettings

    var body: some View {
        if screenSharing.hasChecked {
            VStack(alignment: .leading, spacing: LT.space8) {
                LTSectionTitle("Remote View")
                LTSheet {
                    ScreenSharingRow(screenSharing: screenSharing, settings: settings)
                }
            }
        }
    }
}
