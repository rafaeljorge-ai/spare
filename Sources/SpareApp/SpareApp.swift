import SpareCore
import SwiftUI

/// `@StateObject` instead of `@State`: the `SwiftUIMacros` plugin behind `@State` is missing from
/// Command Line Tools.
@main
struct SpareApp: App {
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
