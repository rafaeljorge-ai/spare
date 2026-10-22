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
            if let problem = snapshotHomeProblem(spareHome: ProcessInfo.processInfo.environment["SPARE_HOME"]) {
                FileHandle.standardError.write(Data("--snapshot \(problem)\n".utf8))
                exit(2)
            }
            let model = AppModel(makeEnvironment: Snapshot.environment, monitorDisk: false)
            AppDelegate.model = model
            Task { await Snapshot.run(model: model, into: URL(fileURLWithPath: directory, isDirectory: true)) }
            return model
        }

        let model = AppModel()
        model.startAlerts()
        AppDelegate.model = model
        if let raw = value(after: "--show", in: arguments), let section = AppSection(rawValue: raw) {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                model.show(section)
            }
        }
        return model
    }

    /// Why `--snapshot` must not run, nil when the home is a throwaway one. It cleans for real, so the
    /// real home (however it is spelled, symlinks included) is refused.
    nonisolated static func snapshotHomeProblem(
        spareHome: String?,
        realHomes: [URL] = [FileManager.default.homeDirectoryForCurrentUser, URL(fileURLWithPath: NSHomeDirectory())]
    ) -> String? {
        guard let spareHome, !spareHome.isEmpty else { return "needs SPARE_HOME pointing at a fake home" }
        let chosen = URL(fileURLWithPath: spareHome).resolvingSymlinksInPath().standardizedFileURL.path
        let real = realHomes.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        return real.contains(chosen) ? "refuses SPARE_HOME that is the real home folder" : nil
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
