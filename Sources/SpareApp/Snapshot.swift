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
        // Cleaning really runs on the fake home, so nothing may reach the real Trash or run a real tool.
        let trashFolder = home.deletingLastPathComponent()
            .appendingPathComponent(home.lastPathComponent + "-trash", isDirectory: true)
        environment.trash = DirectoryTrash(folder: trashFolder)
        environment.commandRunner = SnapshotCommands()
        let disk = SnapshotDisk.shared(home: home, trash: trashFolder)
        environment.diskSpace = { _ in disk.space() }
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

        await runCleanup(model: model, into: directory)

        NSApp.terminate(nil)
    }

    /// The cleanup flow on the fake home: cards, review, confirmation, progress, a real clean and its result.
    private static func runCleanup(model: AppModel, into directory: URL) async {
        model.show(.cleanup)
        try? await Task.sleep(for: .milliseconds(900))
        save(MainWindowController.shared.contentView, name: "5-cleanup-cards", into: directory)

        model.openReview(.devCaches)
        try? await Task.sleep(for: .milliseconds(700))
        save(MainWindowController.shared.contentView, name: "6-cleanup-review", into: directory)

        let safe = (model.lastReport?.items ?? []).filter { $0.safety == .safe && $0.inUseBy == nil }
        let plan = CleanPlan(items: safe)
        await saveSheet(ConfirmCleanContent(plan: plan, onCancel: {}, onConfirm: {}),
                        name: "7-cleanup-confirm", into: directory)

        // Progress: a fixed moment in the middle of the run.
        let catalog = RuleCatalog.standard
        let done = plan.executionOrder.prefix(7).map { item in
            CleanupEntry(ruleID: item.ruleID, category: item.category, originalPath: item.url.path,
                         action: catalog.rule(id: item.ruleID).map { ActionKind($0.action) } ?? .delete,
                         sizeBytes: item.sizeBytes, status: .done)
        }
        model.freezeCleaning(queue: plan.executionOrder, done: Array(done))
        try? await Task.sleep(for: .milliseconds(700))
        save(MainWindowController.shared.contentView, name: "8-cleanup-progress", into: directory)

        // Then the real thing, on the fake home.
        model.cleanupRoute = .cards
        model.requestCleanSafe()
        model.confirmClean()
        await model.waitForClean()
        try? await Task.sleep(for: .milliseconds(1_200))
        save(MainWindowController.shared.contentView, name: "9-cleanup-result", into: directory)

        model.show(.history)
        try? await Task.sleep(for: .milliseconds(900))
        save(MainWindowController.shared.contentView, name: "10-history", into: directory)
    }

    /// A sheet may not render with `cacheDisplay`, so its content is drawn in a borderless window.
    private static func saveSheet<Content: View>(_ content: Content, name: String, into directory: URL) async {
        let host = NSHostingView(rootView: content.preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 460, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(600))
        window.setContentSize(host.fittingSize)
        try? await Task.sleep(for: .milliseconds(700))
        save(host, name: name, into: directory)
        window.close()
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


/// Tools never run in a snapshot: every command "succeeds" without doing anything.
private struct SnapshotCommands: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        CommandResult(exitCode: 0, output: "")
    }
}

/// Fixed disk numbers that still move with the fake home: free space grows by what leaves the home folder
/// for good (items in the Trash still count as used), so the result screen shows a real before and after.
private final class SnapshotDisk: @unchecked Sendable {
    private let lock = NSLock()
    private let home: URL
    private let trash: URL
    private var initialUsed: Int64?

    private init(home: URL, trash: URL) {
        self.home = home
        self.trash = trash
    }

    /// The app builds its environment on every read: they must all share one starting point.
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: SnapshotDisk] = [:]

    static func shared(home: URL, trash: URL) -> SnapshotDisk {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[home.path] { return existing }
        let created = SnapshotDisk(home: home, trash: trash)
        registry[home.path] = created
        return created
    }

    func space() -> DiskSpace {
        lock.lock()
        defer { lock.unlock() }
        let used = SizeCalculator.allocatedSize(of: home) + SizeCalculator.allocatedSize(of: trash)
        let first = initialUsed ?? used
        initialUsed = first
        return DiskSpace(freeBytes: 15_400_000_000 + max(0, first - used), totalBytes: 245_100_000_000)
    }
}
