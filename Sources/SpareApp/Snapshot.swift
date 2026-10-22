import AppKit
import Darwin
import SpareCore
import SwiftUI

/// `--snapshot <dir>` (with `SPARE_HOME` on a fake home) walks the key states and saves them as PNG.
/// It draws the views in-process with `cacheDisplay`, so no Screen Recording permission is needed.
/// Disk, memory and process numbers are fixed so the images look the same on every machine; the scan
/// itself is real, run on the fake home.
@MainActor
enum Snapshot {
    nonisolated static func environment(home: URL, settings: SpareSettings) -> SpareEnvironment {
        var environment = SpareEnvironment.live(home: home, settings: settings)
        environment.diskSpace = { _ in DiskSpace(freeBytes: 15_400_000_000, totalBytes: 245_100_000_000) }
        environment.memory = {
            MemorySnapshot(totalBytes: 16_000_000_000, usedBytes: 11_800_000_000,
                           compressedBytes: 2_000_000_000, level: .normal)
        }
        let apps = [("Claude", 3_100), ("Google Chrome", 2_400), ("Cursor", 1_900)]
        let listing: @Sendable () -> [RunningProcess] = {
            apps.enumerated().map { index, app in
                let bundle = "/Applications/\(app.0).app"
                return RunningProcess(
                    pid: Int32(900 + index), uid: getuid(), rssBytes: Int64(app.1) * 1_000_000,
                    executablePath: "\(bundle)/Contents/MacOS/\(app.0)", commandLine: "\(bundle)/Contents/MacOS/\(app.0)",
                    appBundlePath: bundle, appBundleID: nil, name: app.0)
            }
        }
        environment.memoryProcesses = { listing() }
        // One npx tool is "running" so the in-use state shows up.
        let npx = home.appendingPathComponent(".npm/_npx/eb65ac700b3c4dc9").path
        environment.processes = {
            listing() + [RunningProcess(
                pid: 950, uid: getuid(), rssBytes: 80_000_000, executablePath: "/usr/local/bin/node",
                commandLine: "node \(npx)/node_modules/.bin/mcp-server", appBundlePath: nil, appBundleID: nil, name: "Claude")]
        }
        return environment
    }

    static func run(model: AppModel, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .milliseconds(800))

        await savePanel(model: model, name: "1-panel", into: directory)

        model.show(.overview)
        try? await Task.sleep(for: .milliseconds(900))
        save(MainWindowController.shared.contentView, name: "2-overview-idle", into: directory)

        model.freezeScanning(path: "~/.npm/_npx/eb65ac700b3c4dc9/node_modules")
        try? await Task.sleep(for: .milliseconds(900))
        save(MainWindowController.shared.contentView, name: "3-overview-scanning", into: directory)

        model.resetScan()
        model.startScan()
        await model.waitForScan()
        try? await Task.sleep(for: .milliseconds(1_200))
        save(MainWindowController.shared.contentView, name: "4-overview-done", into: directory)

        NSApp.terminate(nil)
    }

    /// The menu bar panel cannot be opened from code, so it is drawn in a borderless window.
    private static func savePanel(model: AppModel, name: String, into directory: URL) async {
        let host = NSHostingView(rootView: MenuPanel(model: model))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 340, height: 520),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(800))
        window.setContentSize(host.fittingSize)
        try? await Task.sleep(for: .milliseconds(900))
        save(host, name: name, into: directory)
        window.close()
    }

    private static func save(_ view: NSView?, name: String, into directory: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
