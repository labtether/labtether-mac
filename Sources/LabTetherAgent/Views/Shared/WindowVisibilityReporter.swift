import AppKit
import SwiftUI

/// Reports whether the window this view sits in is on screen.
///
/// The menu bar window is built once and then only ordered in and out, so
/// SwiftUI's `onAppear` fires for the first opening and `onDisappear` never.
/// The window's own state is the record of what the person sees.
struct WindowVisibilityReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReporterView, context: Context) {
        view.onChange = onChange
    }

    final class ReporterView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var reported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else {
                report(false)
                return
            }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.willCloseNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.refresh()
                    // Ordering out finishes just after the window resigns key.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
                })
            }
            refresh()
        }

        private func refresh() {
            report(window?.isVisible ?? false)
        }

        private func report(_ visible: Bool) {
            guard reported != visible else { return }
            reported = visible
            onChange?(visible)
        }

        private func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        deinit { stopObserving() }
    }
}
