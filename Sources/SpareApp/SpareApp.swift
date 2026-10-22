import SpareCore
import AppKit
import SwiftUI

/// `@StateObject` instead of `@State`: the `SwiftUIMacros` plugin behind `@State` is missing from
/// Command Line Tools.
@main
struct SpareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = Launch.makeModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Quitting during a cleanup waits for the item in progress and for the record to be saved, so the
/// items already in the Trash can still be undone.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.terminateReply(model: Self.model) { sender.reply(toApplicationShouldTerminate: true) }
    }

    /// `.terminateNow` when idle. During a cleanup: `.terminateLater`, then `reply` runs once it is saved.
    static func terminateReply(model: AppModel?, reply: @escaping @MainActor () -> Void) -> NSApplication.TerminateReply {
        guard let model, model.isCleaning else { return .terminateNow }
        Task { @MainActor in
            await model.finishCleanBeforeQuit()
            reply()
        }
        return .terminateLater
    }
}
