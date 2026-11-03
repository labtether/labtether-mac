import AppKit
import SwiftUI

// MARK: - LT Design Token Namespace

/// The app's names for the LabTether 2.0 tokens.
///
/// Every value comes from the generated `LTTokens` (the Hub console's light and
/// dark colours, radii and type scale). Colours follow the system appearance.
/// Do not add hex values here; regenerate `LTTokens.swift` instead.
enum LT {

    // MARK: Colours

    /// Window background ("canvas").
    static var canvas: Color { LTTokens.Colors.canvas }
    /// Sheet on the canvas.
    static var panel: Color { LTTokens.Colors.panel }
    /// Menu bar window and other popovers.
    static var pop: Color { LTTokens.Colors.panelGlass }
    /// Sunken areas such as the log text.
    static var sunk: Color { LTTokens.Colors.sunk }

    /// Primary text.
    static var text: Color { LTTokens.Colors.text }
    /// Secondary text.
    static var text2: Color { LTTokens.Colors.text2 }
    /// Muted text: labels, times, placeholders. Still meets AA on canvas and sheets.
    static var text3: Color { LTTokens.Colors.text3 }
    static var textDisabled: Color { LTTokens.Colors.textDisabled }

    /// Hairline separators and sheet rings.
    static var hair: Color { LTTokens.Colors.line }
    /// Text field border.
    static var field: Color { LTTokens.Colors.fieldLine }
    static var hover: Color { LTTokens.Colors.hover }
    static var sel: Color { LTTokens.Colors.sel }
    /// Meter and segmented-control track.
    static var track: Color { LTTokens.Colors.track }
    /// Segmented-control thumb.
    static var thumb: Color { LTTokens.Colors.thumb }
    /// Switch track when on: the text colour in light mode, secondary text in dark
    /// mode so the white macOS knob stays visible. Never rose.
    static var switchOn: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(LT.text2) : NSColor(LT.text)
        })
    }

    /// Rose. Only for the one main button of a window.
    static var accent: Color { LTTokens.Colors.accent }
    static var accentHover: Color { LTTokens.Colors.accentHover }
    static var accentContrast: Color { LTTokens.Colors.accentContrast }

    static var ok: Color { LTTokens.Colors.ok }
    static var warn: Color { LTTokens.Colors.warn }
    static var bad: Color { LTTokens.Colors.bad }
    /// Warning text (AA on canvas and sheets).
    static var warnText: Color { LTTokens.Colors.warnText }
    /// Error text (AA on canvas and sheets).
    static var badText: Color { LTTokens.Colors.badText }

    static var chart: Color { LTTokens.Colors.chart }
    static var chartFill: Color { LTTokens.Colors.chartFill }

    // MARK: Typography

    /// The system font (SF Pro). macOS sizes: body 13, meta 12.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// JetBrains Mono, only for log lines, paths and code.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular", size: size)
    }

    // MARK: Spacing

    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24

    // MARK: Corner radii

    /// Rows and small buttons.
    static let radiusRow: CGFloat = LTTokens.Radius.r2
    /// Controls and fields.
    static let radiusControl: CGFloat = LTTokens.Radius.r3
    /// Sheets and windows.
    static let radiusSheet: CGFloat = LTTokens.Radius.r4

    // MARK: Motion

    static let animFast: Double = 0.12
    static let animNormal: Double = 0.2
    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.75)
}
