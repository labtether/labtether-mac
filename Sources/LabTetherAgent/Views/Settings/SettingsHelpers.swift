import SwiftUI

// MARK: - SettingsCardSection

struct SettingsCardSection<Content: View>: View {
    let title: String
    var glowHint: Color?
    @ViewBuilder let content: () -> Content

    init(_ title: String, glowHint: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.glowHint = glowHint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            LTSectionHeader(title)
            LTGlassCard(glowColor: glowHint) {
                VStack(spacing: LT.space8) {
                    content()
                }
            }
        }
    }
}

// MARK: - SettingsIconField

struct SettingsIconField: View {
    let icon: String
    let label: String
    @Binding var text: String
    let prompt: String
    var onChange: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: LT.space8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isFocused ? LT.accent : LT.textMuted)
                .animation(.easeInOut(duration: LT.animFast), value: isFocused)
                .frame(width: 16)
            TextField(label, text: $text, prompt: Text(prompt).foregroundColor(LT.textMuted.opacity(0.5)))
                .textFieldStyle(.plain)
                .font(LT.inter(12))
                .foregroundStyle(LT.textPrimary)
                .focused($isFocused)
                .onChange(of: text) { _ in onChange() }
        }
        .padding(.horizontal, LT.space12)
        .padding(.vertical, 7)
        .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
        .ltFocusRing(isFocused)
    }
}

// MARK: - SettingsSecureIconField

struct SettingsSecureIconField: View {
    let icon: String
    let label: String
    @Binding var text: String
    let prompt: String
    var onChange: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: LT.space8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isFocused ? LT.accent : LT.textMuted)
                .animation(.easeInOut(duration: LT.animFast), value: isFocused)
                .frame(width: 16)

            SecureField(label, text: $text, prompt: Text(prompt).foregroundColor(LT.textMuted.opacity(0.5)))
                .textFieldStyle(.plain)
                .font(LT.inter(12))
                .foregroundStyle(LT.textPrimary)
                .focused($isFocused)
                .onChange(of: text) { _ in onChange() }
        }
        .padding(.horizontal, LT.space12)
        .padding(.vertical, 7)
        .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
        .ltFocusRing(isFocused)
    }
}

// MARK: - SettingsToggleRow

struct SettingsToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    var onChange: (() -> Void)?

    var body: some View {
        HStack(spacing: LT.space8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? LT.accent : LT.textMuted)
                .animation(.easeInOut(duration: LT.animFast), value: isOn)
                .frame(width: 16)

            Text(label)
                .font(LT.inter(12, weight: .medium))
                .foregroundStyle(LT.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(LT.accent)
                .scaleEffect(0.7)
                .onChange(of: isOn) { _ in onChange?() }
        }
        .padding(.horizontal, LT.space12)
        .padding(.vertical, LT.space4)
        .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                .strokeBorder(LT.panelBorder, lineWidth: 1)
        )
    }
}
