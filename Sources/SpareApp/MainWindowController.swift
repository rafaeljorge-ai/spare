import AppKit
import SwiftUI

/// Owns the main window. The Dock icon exists only while the window is open: `.regular` when it is
/// shown, back to `.accessory` (menu bar only) when it closes.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()
    static let size = NSSize(width: 1000, height: 660)

    private var window: NSWindow?

    /// The window's content view, for snapshots.
    var contentView: NSView? { window?.contentView }

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: Self.size),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Spare"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(red: 0.09, green: 0.08, blue: 0.22, alpha: 1)
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Free the SwiftUI tree while only the menu bar item is left (the app stays light).
        Task { @MainActor in
            window?.contentView = nil
            window?.delegate = nil
            window = nil
        }
    }
}
