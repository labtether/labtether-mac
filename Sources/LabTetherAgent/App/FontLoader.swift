import SwiftUI
import CoreText

// MARK: - Debug Boot

private func debugBoot(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["LABTETHER_AGENT_DEBUG_BOOT"] == "1" else { return }
    fputs("[boot] \(message())\n", stderr)
}

// MARK: - Font Loader

/// Registers the bundled mono font with Core Text at app launch.
enum FontLoader {
    /// JetBrains Mono, bundled for log lines and paths. Everything else uses the system font.
    private static let fontFileNames: [String] = [
        "JetBrainsMono-Regular",
        "JetBrainsMono-Medium",
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
                debugBoot("FontLoader: failed to register \(name).ttf: \(desc)")
            } else {
                debugBoot("FontLoader: registered \(name).ttf")
            }
        }
    }

    /// Resolves the URL for a font file, searching the SwiftPM resource bundle with both
    /// a Fonts subdirectory path and a flat resource path as fallbacks.
    private static func resolveFont(named name: String) -> URL? {
        let resources = BundleHelper.resourceBundle
        // Primary: Resources/Fonts subdirectory (SPM .copy placement)
        if let url = resources.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
            return url
        }
        // Fallback: flat resource lookup
        if let url = resources.url(forResource: name, withExtension: "ttf") {
            return url
        }
        return nil
    }
}
