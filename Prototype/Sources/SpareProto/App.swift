import AppKit
import SwiftUI

@main
struct SpareProtoApp: App {
    @StateObject private var model = ProtoModel()

    var body: some Scene {
        Window("Spare", id: "main") {
            RootView(model: model)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    if let dir = Snapshot.directory { Snapshot.run(model: model, into: dir) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// `--snapshot <dir>` walks through the key states and saves the app's own window as PNG.
/// It draws the window contents in-process, so no Screen Recording permission is needed.
@MainActor
enum Snapshot {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func run(model: ProtoModel, into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let steps: [(String, () -> Void)] = [
            ("1-visao-geral", { model.route = .overview }),
            ("2-analisando", { model.freezeScanning() }),
            ("3-analise-concluida", { model.freezeDone() }),
            ("4-limpeza", { model.route = .cleanup }),
            ("5-revisao", { model.selectDefaults(in: "appcaches"); model.route = .review("appcaches") }),
            ("6-resultado", { model.selected = ["p1", "p2", "p3", "d1", "b1"]; model.performClean() }),
            ("7-memoria", { model.route = .memory }),
            ("8-maiores-arquivos", { model.route = .largeFiles }),
        ]
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            for (name, apply) in steps {
                apply()
                try? await Task.sleep(for: .milliseconds(900))
                save(name, into: dir)
            }
            NSApp.terminate(nil)
        }
    }

    private static func save(_ name: String, into dir: URL) {
        guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
