import SwiftUI

/// A rotating arc spinner with a glow trail for loading/starting states.
struct LTSpinnerArc: View {
    let color: Color
    var size: CGFloat = 16

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(color)
            .controlSize(.small)
            .scaleEffect(max(CGFloat(0.6), size / 16))
            .frame(width: size, height: size)
            .accessibilityLabel("Loading")
            .accessibilityAddTraits(.isImage)
    }
}
