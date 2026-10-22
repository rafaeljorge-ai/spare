import AppKit
import Darwin
import SpareCore

/// Snapshot states of the tool screens (Large Files, Memory, Settings). Same rules as `Snapshot`: fake home,
/// fixed numbers, and nothing is ever confirmed here, so no process is quit and no file reaches the Trash.
extension Snapshot {
    /// More memory users for the Memory list. All stay under the menu panel's top three apps.
    nonisolated static func extraMemoryProcesses() -> [RunningProcess] {
        let apps = [("Slack", 1_500), ("Spotify", 1_100), ("Figma", 900), ("Xcode", 820), ("Notion", 640), ("Mail", 410)]
        var result = apps.enumerated().map { index, app -> RunningProcess in
            let bundle = "/Applications/\(app.0).app"
            return RunningProcess(
                pid: Int32(1_000 + index), uid: getuid(), rssBytes: Int64(app.1) * 1_000_000,
                executablePath: "\(bundle)/Contents/MacOS/\(app.0)", commandLine: "\(bundle)/Contents/MacOS/\(app.0)",
                appBundlePath: bundle, appBundleID: nil, name: app.0)
        }
        // One tool that groups several processes: the confirmation lists their pids and commands.
        let scripts = ["next dev", "vite --port 5173", "tsx watch src/server.ts", "mcp-server --stdio"]
        result += scripts.enumerated().map { index, script in
            RunningProcess(
                pid: Int32(1_100 + index), uid: getuid(), rssBytes: Int64(190 - index * 30) * 1_000_000,
                executablePath: "/opt/homebrew/bin/node", commandLine: "node /Users/demo/Projetos/app/node_modules/.bin/\(script)",
                appBundlePath: nil, appBundleID: nil, name: "node")
        }
        return result
    }

    static func runTools(model: AppModel, into directory: URL) async {
        model.show(.largeFiles)
        model.largeFiles.startSearch()
        await model.largeFiles.waitForSearch()
        try? await Task.sleep(for: .milliseconds(900))
        save(MainWindowController.shared.contentView, name: "t11-large-files-result", into: directory)

        if let file = model.largeFiles.files.dropFirst().first {
            model.largeFiles.ask(file)
            try? await Task.sleep(for: .milliseconds(600))
            save(MainWindowController.shared.contentView, name: "t11-large-files-confirm", into: directory)
            model.largeFiles.cancelPending()
        }

        model.show(.memory)
        await model.refreshConsumers()
        try? await Task.sleep(for: .milliseconds(900))
        save(MainWindowController.shared.contentView, name: "t11-memory", into: directory)

        if let node = model.memoryScreen.consumers?.first(where: { $0.name == "node" }) {
            model.memoryScreen.ask(node)
            try? await Task.sleep(for: .milliseconds(600))
            save(MainWindowController.shared.contentView, name: "t11-memory-confirm", into: directory)
            model.memoryScreen.cancelPending()
        }

        model.show(.settings)
        try? await Task.sleep(for: .milliseconds(900))
        save(MainWindowController.shared.contentView, name: "t11-settings", into: directory)
    }
}
