import SwiftUI
import AppKit

/// The LabTether product mark used where the app needs to identify itself.
///
/// The compact status glyph stays separate so the full mark does not make the
/// macOS menu bar item too wide or hide its live connection signal.
struct LTBrandMark: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
