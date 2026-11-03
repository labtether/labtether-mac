import SwiftUI

// MARK: - LTSheet

/// A plain sheet on the window canvas: panel fill, 12 pt corners and a hairline ring.
/// Sheets are never nested.
struct LTSheet<Content: View>: View {
    let padding: EdgeInsets
    @ViewBuilder let content: () -> Content

    init(padding: CGFloat = LT.space4, @ViewBuilder content: @escaping () -> Content) {
        self.padding = EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        self.content = content
    }

    init(padding: EdgeInsets, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LT.panel, in: RoundedRectangle(cornerRadius: LT.radiusSheet, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusSheet, style: .continuous)
                    .strokeBorder(LT.hair, lineWidth: 1)
            )
    }
}

// MARK: - LTSectionTitle

/// A sentence-case section title with an optional fact on the right ("Updated 4s ago").
struct LTSectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(LT.font(13, weight: .semibold))
                .foregroundStyle(LT.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LT.space8)
            trailing()
        }
    }
}

extension LTSectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

extension LTSectionTitle where Trailing == Text {
    init(_ title: String, detail: String) {
        self.init(title) {
            Text(detail)
                .font(LT.font(12))
                .foregroundColor(LT.text3)
        }
    }
}

// MARK: - LTPlaceholderText

/// One line of muted text for an empty or waiting sheet.
struct LTPlaceholderText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LT.font(13))
            .foregroundStyle(LT.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space8)
    }
}
