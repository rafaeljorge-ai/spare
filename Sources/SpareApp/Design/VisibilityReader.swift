import AppKit
import SwiftUI

/// Reports whether the window that hosts this view is really on screen (ordered in and not fully
/// occluded). Used to sample memory only while something shows it: the menu bar panel is hidden, not
/// destroyed, so its SwiftUI lifecycle (`onAppear`, `.task`) says nothing about visibility.
struct VisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private let observers = Observers()
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            observers.removeAll()
            guard let window else {
                report(false)
                return
            }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
            ]
            for name in names {
                observers.add(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
            }
            observers.add(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report(false) }
            })
            refresh()
        }

        private func refresh() {
            guard let window else { return report(false) }
            report(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            onChange?(visible)
        }
    }

    /// Owns the notification tokens and removes them when it goes away.
    private final class Observers: @unchecked Sendable {
        private var tokens: [NSObjectProtocol] = []

        func add(_ token: NSObjectProtocol) { tokens.append(token) }

        func removeAll() {
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
        }

        deinit { removeAll() }
    }
}
