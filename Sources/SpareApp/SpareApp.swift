import AppKit
import SpareCore
import SwiftUI

/// Holds the menu bar title. `@StateObject` is used instead of `@State` because the
/// `SwiftUIMacros` plugin behind the `@State` macro is missing from Command Line Tools.
@MainActor
final class TitleModel: ObservableObject {
    @Published var title = SpareApp.currentTitle()

    func refresh() { title = SpareApp.currentTitle() }
}

@main
struct SpareApp: App {
    @StateObject private var model = TitleModel()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Free space")
                    .font(.headline)
                Text(verbatim: model.title)
                    .font(.title2.monospacedDigit())
                Divider()
                Button("Quit Spare") { NSApp.terminate(nil) }
            }
            .padding(16)
            .frame(width: 240)
            .onAppear { model.refresh() }
        } label: {
            Label(model.title, systemImage: "internaldrive")
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }

    static func currentTitle() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let space = DiskMonitor.space(at: home) else { return "Spare" }
        return "\(ByteFormat.gigabytes(space.freeBytes)) GB"
    }
}
