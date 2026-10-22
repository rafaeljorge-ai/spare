import AppKit
import Darwin
import SpareCore
import SwiftUI

enum ScanState {
    case idle
    case scanning(ScanProgress?)
    case finished(ScanReport)
}

/// App state. `ObservableObject` instead of `@Observable` because the `SwiftUIMacros` plugin is missing
/// from Command Line Tools.
@MainActor
final class AppModel: ObservableObject {
    static let memoryRefreshSeconds = 5
    static let diskRefreshSeconds = 60

    let home: URL
    let volumeName: String
    @Published var settings: SpareSettings
    @Published private(set) var disk: DiskSpace?
    @Published private(set) var memory: MemorySnapshot?
    /// Biggest memory users for the panel (light `ps` listing). Nil until the first read.
    @Published private(set) var consumers: [MemoryConsumer]?
    @Published private(set) var consumersFailed = false
    @Published private(set) var lastReport: ScanReport?
    @Published private(set) var lastCleanup: CleanupRecord?
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scanTotals: [CategoryID: Int64] = [:]
    @Published private(set) var finishedCategories: Set<CategoryID> = []
    @Published var selection: AppSection = .overview

    private let makeEnvironment: @Sendable (SpareSettings) -> SpareEnvironment
    private let settingsStore: SettingsStore
    private let reportStore: ScanReportStore
    private let historyStore: HistoryStore
    private var scanWorker: Task<ScanReport, Never>?
    private var scanTask: Task<Void, Never>?
    private var diskTask: Task<Void, Never>?
    private var lastProgressUpdate = Date.distantPast

    /// - Parameters:
    ///   - makeEnvironment: builds the environment for the current settings (tests and snapshots replace it).
    ///   - monitorDisk: keep refreshing the disk numbers every minute.
    init(
        home: URL = AppModel.defaultHome(),
        makeEnvironment: (@Sendable (URL, SpareSettings) -> SpareEnvironment)? = nil,
        monitorDisk: Bool = true
    ) {
        let resolved = home.resolvingSymlinksInPath()
        self.home = resolved
        let build = makeEnvironment ?? { SpareEnvironment.live(home: $0, settings: $1) }
        self.makeEnvironment = { build(resolved, $0) }
        let support = SpareEnvironment.live(home: resolved).supportDirectory
        settingsStore = SettingsStore(directory: support)
        reportStore = ScanReportStore(directory: support)
        historyStore = HistoryStore(directory: support)
        settings = settingsStore.load(home: resolved)
        volumeName = (try? resolved.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
        lastReport = reportStore.load()
        lastCleanup = (try? historyStore.load())?.first
        refreshDisk()
        refreshMemory()
        if monitorDisk { startDiskMonitoring() }
    }

    /// `SPARE_HOME` points the app at a throwaway home (QA and snapshots); otherwise the real one.
    static func defaultHome() -> URL {
        if let path = ProcessInfo.processInfo.environment["SPARE_HOME"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    var environment: SpareEnvironment { makeEnvironment(settings) }

    // MARK: Monitoring

    func refreshDisk() {
        disk = environment.diskSpace(home)
    }

    func refreshMemory() {
        memory = environment.memory()
    }

    /// Reads the biggest memory users off the main actor (it runs `ps`).
    func refreshConsumers() async {
        let environment = environment
        let result = await Task.detached(priority: .utility) {
            try? MemoryMonitor.topConsumers(
                processes: environment.memoryProcesses(), currentUID: getuid(), ownPID: getpid(), limit: 3)
        }.value
        consumers = result ?? []
        consumersFailed = result == nil
    }

    /// Refreshes memory every 5 s until the calling task is cancelled (`.task` on the view that shows it).
    func watchMemory() async {
        while !Task.isCancelled {
            refreshMemory()
            await refreshConsumers()
            try? await Task.sleep(for: .seconds(Self.memoryRefreshSeconds))
        }
    }

    private func startDiskMonitoring() {
        diskTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.diskRefreshSeconds))
                self?.refreshDisk()
                self?.refreshMemory()
            }
        }
    }

    // MARK: Menu bar

    var isDiskLow: Bool {
        guard let disk else { return false }
        return disk.freeBytes < Int64(settings.diskAlertThresholdGB) * 1_000_000_000
    }

    var menuTitle: String {
        guard let disk else { return "Spare" }
        return "\(ByteFormat.gigabytes(disk.freeBytes)) GB"
    }

    var recommendation: Recommendation {
        Recommendation.compute(disk: disk, thresholdGB: settings.diskAlertThresholdGB,
                               lastScan: lastReport, memory: memory)
    }

    // MARK: Scan

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    /// 0...1 once the scan knows how many items it has; nil while it is still looking for projects.
    var scanFraction: Double? {
        guard case .scanning(let progress?) = scanState, progress.total > 0 else { return nil }
        return min(1, Double(progress.completed) / Double(progress.total))
    }

    func startScan() {
        guard !isScanning else { return }
        scanTotals = [:]
        finishedCategories = []
        lastProgressUpdate = .distantPast
        scanState = .scanning(nil)

        // The scan, its project discovery and the single `environment.processes()` call all run here, off
        // the main actor. Progress travels through a stream so updates keep their order.
        let scanner = Scanner(environment: environment)
        let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)
        let worker = Task.detached(priority: .userInitiated) {
            await scanner.scan { continuation.yield($0) }
        }
        scanWorker = worker
        scanTask = Task { [weak self] in
            let updates = Task { @MainActor [weak self] in
                for await progress in stream { self?.apply(progress) }
            }
            let report = await worker.value
            continuation.finish()
            await updates.value
            self?.finishScan(report)
        }
    }

    func cancelScan() {
        scanWorker?.cancel()
    }

    private func apply(_ progress: ScanProgress) {
        guard isScanning else { return }
        if let item = progress.item {
            scanTotals[item.category, default: 0] += item.sizeBytes
        }
        if let category = progress.finishedCategory {
            finishedCategories.insert(category)
        }
        let now = Date()
        if now.timeIntervalSince(lastProgressUpdate) > 0.1 || progress.finishedCategory != nil {
            lastProgressUpdate = now
            scanState = .scanning(progress)
        }
    }

    private func finishScan(_ report: ScanReport) {
        scanWorker = nil
        scanTask = nil
        lastReport = report
        scanTotals = Dictionary(grouping: report.items, by: \.category).mapValues { $0.reduce(0) { $0 + $1.sizeBytes } }
        finishedCategories = Set(CategoryID.allCases)
        scanState = .finished(report)
        try? reportStore.save(report)
        refreshDisk()
    }

    // MARK: Navigation and settings

    func show(_ section: AppSection) {
        selection = section
        MainWindowController.shared.show(model: self)
    }

    func saveSettings() {
        try? settingsStore.save(settings)
    }

    // MARK: Snapshots (fixed states for QA images)

    func freezeScanning(path: String) {
        scanTotals = [.projectLeftovers: 9_400_000_000, .devCaches: 3_100_000_000, .aiTools: 1_900_000_000]
        finishedCategories = [.projectLeftovers, .devCaches, .aiTools]
        scanState = .scanning(ScanProgress(currentPath: path, completed: 31, total: 56, item: nil, finishedCategory: nil))
    }

    func resetScan() {
        scanState = .idle
        scanTotals = [:]
        finishedCategories = []
    }

    /// Waits until the running scan, if any, has produced its report.
    func waitForScan() async {
        await scanTask?.value
    }
}
