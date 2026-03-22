import SwiftUI

struct PopOutBackground: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [LT.accent.opacity(0.06), .clear],
                center: UnitPoint(x: 0.3, y: 0.2),
                startRadius: 0,
                endRadius: 200
            )
            RadialGradient(
                colors: [LT.ok.opacity(0.04), .clear],
                center: UnitPoint(x: 0.7, y: 0.8),
                startRadius: 0,
                endRadius: 150
            )
            RadialGradient(
                colors: [LT.warn.opacity(0.03), .clear],
                center: UnitPoint(x: 0.45, y: 0.7),
                startRadius: 0,
                endRadius: 120
            )
        }
        .ignoresSafeArea()
    }
}
