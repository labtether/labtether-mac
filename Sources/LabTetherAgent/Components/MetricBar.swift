import SwiftUI

/// A thin usage bar for the live 5 s polling path: neutral fill, amber from 85 %.
struct LTMetricBar: View {
    let fraction: Double
    var isHot = false
    var accessibilityName: String = "Metric"

    private var clampedFraction: CGFloat {
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(max(fraction, 0), 1))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LT.track)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isHot ? LT.warn : LT.text3)
                .scaleEffect(x: clampedFraction, y: 1, anchor: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(Int((clampedFraction * 100).rounded())) percent")
    }
}

/// One usage meter of the menu bar window: label and value above a thin bar.
struct LTMeter: View {
    let label: String
    let gauge: MetricGaugePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(LT.text3)
                Spacer(minLength: LT.space4)
                Text(gauge.percentText)
                    .fontWeight(.medium)
                    .foregroundStyle(gauge.isHot ? LT.warnText : LT.text)
            }
            .font(LT.font(12).monospacedDigit())
            LTMetricBar(fraction: gauge.fraction, isHot: gauge.isHot, accessibilityName: label)
        }
        .accessibilityElement(children: .combine)
    }
}
