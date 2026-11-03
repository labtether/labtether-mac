import SwiftUI

// MARK: - Button styles

/// Secondary button: control fill, hairline ring, primary text.
struct LTSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var fontSize: CGFloat = 13
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.font(fontSize, weight: .medium))
            .foregroundStyle(LT.text)
            .lineLimit(1)
            .padding(.horizontal, fontSize < 13 ? 10 : 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusRow, style: .continuous)
                    .fill(configuration.isPressed ? LTTokens.Colors.ctlPress : LTTokens.Colors.ctlBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusRow, style: .continuous)
                    .strokeBorder(LTTokens.Colors.ring, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// The one rose button of a window.
struct LTPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var radius: CGFloat = LT.radiusRow
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.font(13, weight: .medium))
            .foregroundStyle(LT.accentContrast)
            .lineLimit(1)
            .padding(.horizontal, height > 28 ? 16 : 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(configuration.isPressed ? LTTokens.Colors.rosePress : LT.accent)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// A text-only button in secondary text, used for small inline actions ("Paste", "Diagnostics…").
struct LTTextButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 12
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.font(fontSize, weight: .medium))
            .foregroundStyle(configuration.isPressed ? LT.text : LT.text2)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

// MARK: - LTQuietIconButton

/// A borderless 28 pt icon button with a hover fill. Always carries an accessibility label.
struct LTQuietIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(LT.text2)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: LT.radiusRow, style: .continuous)
                        .fill(isHovered ? LT.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - LTMoreMenu

/// A "⋯" menu button. `bordered` draws it as a secondary control (pop-out header);
/// otherwise it is quiet (menu bar footer).
struct LTMoreMenu<Items: View>: View {
    let label: String
    var bordered = false
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(LT.text2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .background(
            RoundedRectangle(cornerRadius: LT.radiusRow, style: .continuous)
                .fill(bordered ? LTTokens.Colors.ctlBg : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LT.radiusRow, style: .continuous)
                .strokeBorder(bordered ? LTTokens.Colors.ring : Color.clear, lineWidth: 1)
        )
        .help(label)
        .accessibilityLabel(label)
    }
}
