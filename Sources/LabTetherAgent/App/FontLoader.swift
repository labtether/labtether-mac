import SwiftUI
import CoreText

// MARK: - Debug Boot

private func debugBoot(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["LABTETHER_AGENT_DEBUG_BOOT"] == "1" else { return }
    fputs("[boot] \(message())\n", stderr)
}

// MARK: - Font Loader

/// Registers all bundled premium fonts with Core Text at app launch.
enum FontLoader {
    /// Names of all TTF font files bundled under Resources/Fonts.
    private static let fontFileNames: [String] = [
        "Sora-Regular",
        "Sora-Medium",
        "Sora-SemiBold",
        "Sora-Bold",
        "Inter-Regular",
        "Inter-Medium",
        "Inter-SemiBold",
        "JetBrainsMono-Regular",
        "JetBrainsMono-Medium",
        "JetBrainsMono-SemiBold",
    ]

    /// Registers all bundled fonts with Core Text so they are available
    /// to SwiftUI's `.custom` font initializer throughout the app.
    static func registerAll() {
        for name in fontFileNames {
            guard let url = resolveFont(named: name) else {
                debugBoot("FontLoader: could not locate \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !ok {
                let desc = error?.takeRetainedValue().localizedDescription ?? "unknown error"
                debugBoot("FontLoader: failed to register \(name).ttf — \(desc)")
            } else {
                debugBoot("FontLoader: registered \(name).ttf")
            }
        }
    }

    /// Resolves the URL for a font file, searching Bundle.main with both
    /// a Fonts subdirectory path and a flat resource path as fallbacks.
    private static func resolveFont(named name: String) -> URL? {
        // Primary: Resources/Fonts subdirectory (SPM .copy placement)
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
            return url
        }
        // Fallback: flat resource lookup
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
            return url
        }
        return nil
    }
}
