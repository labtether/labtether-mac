import SwiftUI
import AppKit

// MARK: - ConnectionDiagnosticsSheet

/// A sheet that runs and displays full connection diagnostics step by step.
///
/// Presents a live waterfall of four network checks (DNS, TCP, TLS, HTTP) and
/// lets the user copy a plain-text report of the results to the pasteboard.
struct ConnectionDiagnosticsSheet: View {

    // MARK: Inputs

    let hubURL: String
    let tlsSkipVerify: Bool

    // MARK: State

    @State private var steps: [DiagnosticStep] = []
    @State private var isRunning = false
    @State private var hasRun = false

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
                .background(Color.white.opacity(0.08))
            stepListSection
            Divider()
                .background(Color.white.opacity(0.08))
            bottomBar
        }
        .frame(width: 420)
        .frame(minHeight: 360)
        .background(LT.bg)
        .onAppear {
            runDiagnostics()
        }
    }

    // MARK: - Subviews

    /// Title and hub URL display area.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            Text(L10n.diagnosticsTitle)
                .font(LT.sora(16, weight: .semibold))
                .foregroundStyle(LT.textPrimary)

            Text(hubURL)
                .font(LT.mono(12))
                .foregroundStyle(LT.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, LT.space20)
        .padding(.vertical, LT.space16)
    }

    /// Scrollable list of diagnostic step rows, or placeholder when empty.
    private var stepListSection: some View {
        Group {
            if steps.isEmpty {
                placeholderText
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: LT.space8) {
                        ForEach(steps) { step in
                            StepRow(step: step)
                        }
                    }
                    .padding(.horizontal, LT.space20)
                    .padding(.vertical, LT.space16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placeholderText: some View {
        Text("Press Run to start diagnostics.")
            .font(LT.inter(13))
            .foregroundStyle(LT.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(LT.space20)
    }

    /// Bottom action bar with Copy Results, Run/Re-run, and Close buttons.
    private var bottomBar: some View {
        HStack(spacing: LT.space8) {
            if hasRun {
                Button(L10n.diagnosticsCopyResults) {
                    copyResults()
                }
                .buttonStyle(.plain)
                .font(LT.inter(13))
                .foregroundStyle(LT.textSecondary)
            }

            Spacer()

            Button(hasRun ? L10n.diagnosticsRerun : L10n.diagnosticsRun) {
                runDiagnostics()
            }
            .buttonStyle(.borderedProminent)
            .tint(LT.accent)
            .font(LT.inter(13, weight: .medium))
            .disabled(isRunning)

            Button(L10n.diagnosticsClose) {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(LT.inter(13))
            .foregroundStyle(LT.textSecondary)
        }
        .padding(.horizontal, LT.space20)
        .padding(.vertical, LT.space16)
    }

    // MARK: - Actions

    /// Launches the full diagnostics waterfall on a background task.
    private func runDiagnostics() {
        isRunning = true
        Task {
            await ConnectionTester.fullDiagnostics(
                hubURL: hubURL,
                tlsSkipVerify: tlsSkipVerify
            ) { updatedSteps in
                Task { @MainActor in
                    steps = updatedSteps
                }
            }
            await MainActor.run {
                isRunning = false
                hasRun = true
            }
        }
    }

    /// Formats the current step results as a plain-text report and writes it to the pasteboard.
    private func copyResults() {
        let report = ConnectionTester.formatDiagnosticsReport(steps, hubURL: hubURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}

// MARK: - StepRow

/// A single row in the diagnostics waterfall showing a status icon, step name, and detail text.
private struct StepRow: View {

    let step: DiagnosticStep

    var body: some View {
        HStack(alignment: .top, spacing: LT.space8) {
            statusIcon
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: LT.space4) {
                Text(step.name)
                    .font(LT.inter(13, weight: .medium))
                    .foregroundStyle(LT.textPrimary)

                if let detail = detailText {
                    Text(detail.text)
                        .font(LT.mono(11))
                        .foregroundStyle(detail.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Status icon

    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.25))

        case .running:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.55)

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(LT.ok)

        case .failure:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(LT.bad)
        }
    }

    // MARK: Detail text

    private struct DetailText {
        let text: String
        let color: Color
    }

    private var detailText: DetailText? {
        switch step.status {
        case .pending, .running:
            return nil
        case .success(let message):
            return DetailText(text: message, color: LT.ok)
        case .failure(let message):
            return DetailText(text: message, color: LT.bad)
        }
    }
}
