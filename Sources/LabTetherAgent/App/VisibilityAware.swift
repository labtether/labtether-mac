/// Tracks whether any interactive UI surface (menu popover or pop-out panel)
/// is currently visible.
///
/// Each class that needs visibility-aware behaviour owns a `VisibilityGate`
/// instance and delegates the two setter methods to it, reacting to transitions
/// in its own domain-specific way.
@MainActor
final class VisibilityGate {
    private(set) var menuVisible = false
    private(set) var panelVisible = false

    /// `true` when at least one surface is showing.
    var anySurfaceVisible: Bool { menuVisible || panelVisible }

    /// Updates menu visibility and returns `true` when the value actually changed.
    @discardableResult
    func setMenuVisible(_ visible: Bool) -> Bool {
        guard menuVisible != visible else { return false }
        menuVisible = visible
        return true
    }

    /// Updates panel visibility and returns `true` when the value actually changed.
    @discardableResult
    func setPanelVisible(_ visible: Bool) -> Bool {
        guard panelVisible != visible else { return false }
        panelVisible = visible
        return true
    }

    /// Resets both flags to `false`.
    func reset() {
        menuVisible = false
        panelVisible = false
    }
}
