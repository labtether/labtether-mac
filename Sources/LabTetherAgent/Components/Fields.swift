import SwiftUI

// MARK: - Field box

/// The 2.0 text field frame: 28 pt high, 8 pt corners, a field-coloured border
/// that darkens while focused.
private struct LTFieldFrame: ViewModifier {
    let isFocused: Bool
    var hasError = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(LT.panel, in: RoundedRectangle(cornerRadius: LT.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusControl, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            )
    }

    private var borderColor: Color {
        if hasError { return LT.bad }
        return isFocused ? LT.text3 : LT.field
    }
}

// MARK: - LTTextField

/// A single-line text field with an optional trailing accessory (for example "Paste").
struct LTTextField<Accessory: View>: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var hasError = false
    var onChange: () -> Void = {}
    @ViewBuilder let accessory: () -> Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: LT.space6) {
            TextField(label, text: $text, prompt: Text(prompt).foregroundColor(LT.text3))
                .textFieldStyle(.plain)
                .font(LT.font(13))
                .foregroundStyle(LT.text)
                .focused($isFocused)
                .onChange(of: text) { _ in onChange() }
            accessory()
        }
        .modifier(LTFieldFrame(isFocused: isFocused, hasError: hasError))
    }
}

extension LTTextField where Accessory == EmptyView {
    init(
        label: String,
        text: Binding<String>,
        prompt: String = "",
        hasError: Bool = false,
        onChange: @escaping () -> Void = {}
    ) {
        self.init(label: label, text: text, prompt: prompt, hasError: hasError, onChange: onChange) {
            EmptyView()
        }
    }
}

// MARK: - LTSecretField

/// A token field that hides its value, with an eye button to show it.
struct LTSecretField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var onChange: () -> Void = {}

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: LT.space6) {
            Group {
                if isRevealed {
                    TextField(label, text: $text, prompt: Text(prompt).foregroundColor(LT.text3))
                } else {
                    SecureField(label, text: $text, prompt: Text(prompt).foregroundColor(LT.text3))
                }
            }
            .textFieldStyle(.plain)
            .font(LT.font(13))
            .foregroundStyle(LT.text)
            .focused($isFocused)
            .onChange(of: text) { _ in onChange() }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(LT.text3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRevealed ? "Hide token" : "Show token")
            .accessibilityLabel(isRevealed ? "Hide token" : "Show token")
        }
        .modifier(LTFieldFrame(isFocused: isFocused))
    }
}

// MARK: - LTFieldError

/// A validation message under its field, in red text.
struct LTFieldError: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LT.font(12))
            .foregroundStyle(LT.badText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}
