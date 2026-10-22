import AppKit
import Foundation

/// Launch arguments: `--show <section>` opens the main window on a section (QA), `--snapshot <dir>`
/// walks the key states and saves them as PNG (see `Snapshot`).
@MainActor
enum Launch {
    static func makeModel() -> AppModel {
        let arguments = CommandLine.arguments

        if let directory = value(after: "--snapshot", in: arguments) {
            // A snapshot scans and draws real data: it must never run against the real home.
            guard ProcessInfo.processInfo.environment["SPARE_HOME"] != nil else {
                FileHandle.standardError.write(Data("--snapshot needs SPARE_HOME pointing at a fake home\n".utf8))
                exit(2)
            }
            let model = AppModel(makeEnvironment: Snapshot.environment, monitorDisk: false)
            Task { await Snapshot.run(model: model, into: URL(fileURLWithPath: directory, isDirectory: true)) }
            return model
        }

        let model = AppModel()
        if let raw = value(after: "--show", in: arguments), let section = AppSection(rawValue: raw) {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                model.show(section)
            }
        }
        return model
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
