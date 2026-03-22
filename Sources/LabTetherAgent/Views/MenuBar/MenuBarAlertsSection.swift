import SwiftUI

struct MenuBarAlertsSection: View {
    @ObservedObject var alerts: LocalAPIAlertsStore
    let consoleBaseURL: URL?

    var body: some View {
        if !alerts.snapshot.firingAlerts.isEmpty {
            VStack(spacing: LT.space4) {
                LTSectionHeader("ALERTS", count: alerts.snapshot.firingAlerts.count, countColor: LT.bad)
                    .padding(.horizontal, LT.space12)
                AlertsView(
                    firingAlerts: alerts.snapshot.firingAlerts,
                    hasCritical: alerts.snapshot.hasCriticalFiring,
                    consoleBaseURL: consoleBaseURL
                )
                    .padding(.horizontal, LT.space12)
            }
            .padding(.bottom, LT.space6)
        }
    }
}
