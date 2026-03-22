import SwiftUI

/// Collapsible panel showing firing alerts fetched from the local agent API.
/// The parent is responsible for hiding this view when `alerts` is empty.
struct AlertsView: View {
    let firingAlerts: [AlertSnapshot]
    let hasCritical: Bool
    let consoleBaseURL: URL?

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            headerButton
            if isExpanded {
                alertList
            }
        }
    }

    // MARK: - Header

    private var headerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: LT.animNormal)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: LT.space8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LT.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: LT.animNormal), value: isExpanded)
                    .frame(width: 12)

                Text(
                    "\(firingAlerts.count) alert\(firingAlerts.count == 1 ? "" : "s")"
                )
                .font(LT.inter(11, weight: .semibold))
                .foregroundStyle(LT.textPrimary)

                Spacer()

                if hasCritical {
                    CritBadge()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Alert list

    private var alertList: some View {
        VStack(spacing: 3) {
            if firingAlerts.isEmpty {
                emptyState
            } else {
                ForEach(Array(firingAlerts.enumerated()), id: \.element.id) { _, alert in
                    alertRow(alert)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: LT.space8) {
            LTAnimatedCheck(color: LT.ok, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("All Clear")
                    .font(LT.inter(11, weight: .semibold))
                    .foregroundStyle(LT.ok)
                Text("No active alerts")
                    .font(LT.inter(10))
                    .foregroundStyle(LT.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: - Alert row

    @ViewBuilder
    private func alertRow(_ alert: AlertSnapshot) -> some View {
        Button {
            openAlertsPage()
        } label: {
            AlertRowContent(alert: alert, severityColor: severityColor(for: alert.severity))
        }
        .buttonStyle(AlertRowButtonStyle())
        .opacity(alert.state == "resolved" ? 0.45 : 1)
    }

    // MARK: - Helpers

    private func openAlertsPage() {
        guard let base = consoleBaseURL else { return }
        // Append /alerts without double-slashing; appendingPathComponent handles this.
        NSWorkspace.shared.open(base.appendingPathComponent("alerts"))
    }

    private func severityColor(for severity: String) -> Color {
        switch severity {
        case "critical": return LT.bad
        case "high":     return LT.warn
        case "medium":   return LT.accent
        default:         return LT.textMuted   // low + unknown
        }
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let seconds = max(0, Int(-date.timeIntervalSinceNow))
        if seconds < 60    { return "\(seconds)s ago" }
        if seconds < 3600  { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

// MARK: - CritBadge

/// A pulsing critical severity badge with breathing glow shadow.
private struct CritBadge: View {
    @State private var pulse = false
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        Text("CRIT")
            .font(LT.mono(9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(LT.bad, in: Capsule())
            .shadow(color: LT.bad.opacity(pulse ? 0.7 : 0.3), radius: pulse ? 8 : 4)
            .onAppear {
                guard animationsActive else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .onChange(of: animationsActive) { active in
                if !active { pulse = false }
            }
    }
}

// MARK: - AlertRowContent

/// The interior layout of a single alert row, extracted so the pulsing
/// @State animation for critical dots is owned inside the row lifecycle.
private struct AlertRowContent: View {
    let alert: AlertSnapshot
    let severityColor: Color

    @State private var pulse = false
    @Environment(\.animationsActive) private var animationsActive

    private var isCritical: Bool { alert.severity == "critical" }

    var body: some View {
        HStack(spacing: 0) {
            // Severity edge bar — scan severity down the left edge
            LTSeverityEdge(color: severityColor)
                .padding(.vertical, 2)
                .opacity(isCritical ? (pulse ? 0.6 : 1.0) : 1.0)

            HStack(spacing: LT.space8) {
                LTStatusDot(
                    color: severityColor,
                    size: 6,
                    pulsing: isCritical,
                    pulseSpeed: 1.5
                )

                Text(alert.title)
                    .font(LT.inter(11, weight: .medium))
                    .foregroundStyle(LT.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(relativeTime(alert.timestamp))
                    .font(LT.mono(10))
                    .foregroundStyle(LT.textMuted)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(severityColor.opacity(0.35))
                    .frame(width: 8)
            }
            .padding(.horizontal, LT.space8)
        }
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                .fill(LT.panelGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                .strokeBorder(severityColor.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onAppear {
            if isCritical && animationsActive {
                withAnimation(
                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                ) {
                    pulse = true
                }
            }
        }
        .onChange(of: animationsActive) { active in
            if !active { pulse = false }
        }
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let seconds = max(0, Int(-date.timeIntervalSinceNow))
        if seconds < 60    { return "\(seconds)s ago" }
        if seconds < 3600  { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

// MARK: - AlertRowButtonStyle

/// A button style with press-scale feedback for alert rows.
private struct AlertRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? LT.pressScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(LT.springSnappy, value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("AlertsView — firing alerts") {
    let now = Date()
    let alerts: [AlertSnapshot] = [
        AlertSnapshot(
            id: "1",
            severity: "critical",
            title: "CPU usage above 95%",
            summary: "Host CPU has been above 95% for 10 minutes.",
            state: "firing",
            timestamp: now.addingTimeInterval(-120)
        ),
        AlertSnapshot(
            id: "2",
            severity: "high",
            title: "Memory pressure elevated",
            summary: "Available memory below 500 MB.",
            state: "firing",
            timestamp: now.addingTimeInterval(-240)
        ),
        AlertSnapshot(
            id: "3",
            severity: "medium",
            title: "Disk warning on /var",
            summary: "Disk usage at 88%.",
            state: "firing",
            timestamp: now.addingTimeInterval(-300)
        ),
    ]
    return AlertsView(firingAlerts: alerts, hasCritical: true, consoleBaseURL: URL(string: "http://localhost:3000"))
        .padding()
        .frame(width: 340)
        .background(LT.bg)
}

#Preview("AlertsView — no active alerts") {
    return AlertsView(firingAlerts: [], hasCritical: false, consoleBaseURL: nil)
        .padding()
        .frame(width: 340)
        .background(LT.bg)
}
