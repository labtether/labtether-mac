import SwiftUI

// MARK: - SettingsSection

/// A sentence-case title over one sheet of form rows, with an optional footnote.
struct SettingsSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            LTSectionTitle(title)
            LTSheet(padding: EdgeInsets(top: 6, leading: LT.space16, bottom: 6, trailing: LT.space16)) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
            }
            if let footnote {
                Text(footnote)
                    .font(LT.font(12))
                    .foregroundStyle(LT.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, LT.space8)
            }
        }
    }
}

// MARK: - Rows

/// A labelled text field row.
struct SettingsTextRow: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var error: String?
    var onChange: () -> Void = {}

    var body: some View {
        LTFormRow(label: label, alignment: error == nil ? .center : .top) {
            VStack(alignment: .leading, spacing: 0) {
                LTTextField(label: label, text: $text, prompt: prompt, hasError: error != nil, onChange: onChange)
                if let error {
                    LTFieldError(text: error)
                }
            }
        }
    }
}

/// A labelled token field row.
struct SettingsSecretRow: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var onChange: () -> Void = {}

    var body: some View {
        LTFormRow(label: label) {
            LTSecretField(label: label, text: $text, prompt: prompt, onChange: onChange)
        }
    }
}

/// A labelled number field that keeps digits only and clamps to `range` as the person types.
struct SettingsNumberRow: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    let range: ClosedRange<Int>
    var onChange: () -> Void = {}

    var body: some View {
        LTFormRow(label: label) {
            LTTextField(label: label, text: $text, prompt: prompt, onChange: {
                let clamped = SettingsNumberRow.clamped(text, to: range)
                if clamped != text { text = clamped }
                onChange()
            })
            .frame(maxWidth: 140)
        }
    }

    /// Digits only; above the range becomes the maximum, a non-empty value below it the minimum.
    static func clamped(_ text: String, to range: ClosedRange<Int>) -> String {
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits) else { return digits }
        if value > range.upperBound { return String(range.upperBound) }
        if value < range.lowerBound { return String(range.lowerBound) }
        return digits
    }
}

/// A labelled native segmented control.
/// Long option titles use a pop-up menu instead (`segmented: false`).
struct SettingsPickerRow<Value: Hashable>: View {
    let label: String
    let selection: Binding<Value>
    let options: [(title: String, value: Value)]
    var segmented = true

    var body: some View {
        LTFormRow(label: label) {
            if segmented {
                picker.pickerStyle(.segmented).labelsHidden().fixedSize()
            } else {
                picker.pickerStyle(.menu).labelsHidden().fixedSize()
            }
        }
    }

    private var picker: some View {
        Picker(label, selection: selection) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
    }
}
