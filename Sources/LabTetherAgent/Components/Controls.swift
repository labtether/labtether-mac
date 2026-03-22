import SwiftUI

// MARK: - LTSectionHeader

/// A terminal-style section header rendered as `// TITLE (count)`.
///
/// The `//` prefix and title are displayed in `LT.mono` at muted opacity,
/// while the optional count appears in the supplied `countColor`.
struct LTSectionHeader: View {
    let title: String
    let count: Int?
    let countColor: Color

    /// Creates an `LTSectionHeader`.
    /// - Parameters:
    ///   - title:      The section label, uppercased automatically.
    ///   - count:      Optional count shown in parentheses after the title.
    ///   - countColor: Color applied to the count. Defaults to `LT.accent`.
    init(_ title: String, count: Int? = nil, countColor: Color = LT.accent) {
        self.title = title
        self.count = count
        self.countColor = countColor
    }

    @State private var lineAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("// \(title.uppercased())")
                    .font(LT.mono(10, weight: .medium))
                    .foregroundStyle(LT.textMuted)
                    .tracking(1)

                if let count {
                    Text(" (\(count))")
                        .font(LT.mono(10, weight: .medium))
                        .foregroundStyle(countColor)
                        .tracking(1)
                }

                Spacer()
            }

            // Animated gradient underline
            LinearGradient(
                colors: [
                    (count != nil ? countColor : LT.accent).opacity(0.4),
                    (count != nil ? countColor : LT.accent).opacity(0.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
            .opacity(lineAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.1), value: lineAppeared)
        }
        .onAppear { lineAppeared = true }
    }
}

// MARK: - LTMenuRow

/// A compact, hoverable action row for menu-style lists.
///
/// Displays a leading SF Symbol icon, a label, and an optional keyboard shortcut hint.
struct LTMenuRow: View {
    let icon: String
    let label: String
    let shortcut: String?
    let showChevron: Bool
    let badge: String?
    let badgeColor: Color
    let action: () -> Void

    @State private var isHovered = false

    /// Creates an `LTMenuRow`.
    /// - Parameters:
    ///   - icon:        SF Symbol name for the leading icon.
    ///   - label:       Primary action label.
    ///   - shortcut:    Optional keyboard shortcut string displayed in muted mono type.
    ///   - showChevron: When `true`, a trailing chevron indicates external navigation.
    ///   - badge:       Optional count badge text shown before the shortcut.
    ///   - badgeColor:  Color for the badge. Defaults to `LT.bad`.
    ///   - action:      Closure invoked on tap.
    init(icon: String, label: String, shortcut: String? = nil, showChevron: Bool = false,
         badge: String? = nil, badgeColor: Color = LT.bad, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.shortcut = shortcut
        self.showChevron = showChevron
        self.badge = badge
        self.badgeColor = badgeColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: LT.space8) {
                // Icon with subtle tinted background
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill((isHovered ? LT.accent : LT.textMuted).opacity(isHovered ? 0.14 : 0.08))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isHovered ? LT.accent : LT.textSecondary)
                        .scaleEffect(isHovered ? 1.15 : 1.0)
                }

                Text(label)
                    .font(LT.inter(12, weight: .medium))
                    .foregroundStyle(isHovered ? LT.textPrimary : LT.textSecondary)

                Spacer()

                if let badge {
                    LTCapsuleBadge(text: badge, color: badgeColor, withGlow: true)
                }

                if let shortcut {
                    Text(shortcut)
                        .font(LT.mono(9))
                        .foregroundStyle(LT.textMuted.opacity(isHovered ? 0.8 : 0.4))
                }

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isHovered ? LT.accent.opacity(0.6) : LT.textMuted.opacity(0.5))
                }
            }
            .padding(.horizontal, LT.space8)
            .padding(.vertical, LT.space4 + 1)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                    .fill(isHovered ? LT.hover : Color.clear)
            )
        }
        .buttonStyle(LTPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: LT.animFast), value: isHovered)
        .accessibilityLabel(label)
    }
}

// MARK: - LTSeparator

/// A subtle 0.5 pt horizontal divider with gradient-faded edges matching web console separators.
struct LTSeparator: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: LT.panelBorder, location: 0.15),
                .init(color: LT.panelBorder, location: 0.85),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: 0.5)
        .padding(.vertical, LT.space4)
    }
}

// MARK: - LTCopyRow

/// A compact key-value row with hover-reveal copy icon and click-to-copy action.
/// Used for connection info, diagnostics, and metadata rows.
struct LTCopyRow: View {
    let label: String
    let value: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(LT.mono(10, weight: .medium))
                    .foregroundStyle(LT.textMuted)
                    .frame(width: 36, alignment: .trailing)
                Text(value)
                    .font(LT.inter(11))
                    .foregroundStyle(isHovered ? LT.textPrimary : LT.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isHovered ? LT.accent : LT.textMuted.opacity(0.3))
                    .scaleEffect(isHovered ? 1.1 : 1.0)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, LT.space4)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                    .fill(isHovered ? LT.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: LT.animFast), value: isHovered)
        .help("Click to copy \(label)")
    }
}
