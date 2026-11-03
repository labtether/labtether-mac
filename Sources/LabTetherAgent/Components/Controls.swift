import SwiftUI

// MARK: - LTMenuItem

/// One row of the menu bar window: outlined icon, label and an optional shortcut hint.
struct LTMenuItem: View {
    let icon: String
    let label: String
    var shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: LT.space8) {
                LTIcon(name: icon)
                Text(label)
                    .font(LT.font(13))
                    .foregroundStyle(LT.text)
                Spacer(minLength: LT.space8)
                if let shortcut {
                    Text(shortcut)
                        .font(LT.font(12).monospacedDigit())
                        .foregroundStyle(LT.text3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, LT.space8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusRow, style: .continuous)
                    .fill(isHovered ? LT.sel : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
    }
}

// MARK: - LTSeparator

/// A hairline between groups of the menu bar window.
struct LTSeparator: View {
    var body: some View {
        Rectangle()
            .fill(LT.hair)
            .frame(height: 1)
            .padding(.vertical, 5)
            .padding(.horizontal, LT.space8)
            .accessibilityHidden(true)
    }
}

// MARK: - LTDisclosureRow

/// A collapsed group ("Identity", "Advanced") with a short note of what is inside.
struct LTDisclosureRow: View {
    let title: String
    let detail: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: LT.animNormal)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: LT.space6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LT.text3)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14)
                Text(title)
                    .font(LT.font(13, weight: .medium))
                    .foregroundStyle(LT.text2)
                Spacer(minLength: LT.space8)
                Text(detail)
                    .font(LT.font(12))
                    .foregroundStyle(LT.text3)
            }
            .padding(.horizontal, LT.space8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(detail)
    }
}

// MARK: - LTFormRow

/// A form row with the label on the left (128 pt column) and the control on the right.
struct LTFormRow<Control: View>: View {
    let label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: alignment, spacing: LT.space12) {
            Text(label)
                .font(LT.font(13))
                .foregroundStyle(LT.text)
                .frame(width: 128, alignment: .leading)
                .padding(.top, alignment == .top ? 5 : 0)
                .accessibilityHidden(label.isEmpty)
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 40)
        .padding(.vertical, 6)
    }
}

// MARK: - LTToggleRow

/// A label with a switch on the right. Switches use the text colour (`LT.switchOn`), never rose.
struct LTToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var detail: String?
    var onChange: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: LT.space12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(LT.font(13))
                    .foregroundStyle(LT.text)
                if let detail {
                    Text(detail)
                        .font(LT.font(12))
                        .foregroundStyle(LT.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: LT.space8)
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(LT.switchOn)
                .labelsHidden()
                .onChange(of: isOn) { _ in onChange?() }
        }
        .frame(minHeight: 40)
        .padding(.vertical, 2)
    }
}
