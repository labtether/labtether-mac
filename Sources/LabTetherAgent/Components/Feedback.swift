import SwiftUI

// MARK: - LTToast

/// A short message that floats at the top of a window ("Diagnostics copied").
struct LTToast: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(LT.font(12, weight: .medium))
            .foregroundStyle(isError ? LT.badText : LT.text)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space6)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusControl, style: .continuous)
                    .fill(LT.pop)
                    .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusControl, style: .continuous)
                    .strokeBorder(LTTokens.Colors.ring, lineWidth: 1)
            )
            .accessibilityAddTraits(.updatesFrequently)
    }
}
