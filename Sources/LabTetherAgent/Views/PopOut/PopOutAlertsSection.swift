import SwiftUI

struct PopOutAlertsSection: View {
    @ObservedObject var alerts: LocalAPIAlertsStore
    let consoleBaseURL: URL?

    var body: some View {
        if !alerts.snapshot.firingAlerts.isEmpty {
            VStack(spacing: LT.space8) {
                LTSectionHeader("ALERTS", count: alerts.snapshot.firingAlerts.count, countColor: LT.bad)
                AlertsView(
                    firingAlerts: alerts.snapshot.firingAlerts,
                    hasCritical: alerts.snapshot.hasCriticalFiring,
                    consoleBaseURL: consoleBaseURL
                )
            }
            LTSeparator()
        }
    }
}
