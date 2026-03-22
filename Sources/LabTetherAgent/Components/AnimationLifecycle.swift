import SwiftUI

// MARK: - Animation Lifecycle

/// Controls whether repeating animations are active.
/// Injected as `false` when the popover/window is not visible,
/// causing all `repeatForever` animations to pause.
private struct AnimationsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var animationsActive: Bool {
        get { self[AnimationsActiveKey.self] }
        set { self[AnimationsActiveKey.self] = newValue }
    }
}
