import Foundation
import Testing
import SpareCore
import SpareTestSupport
@testable import SpareApp

@MainActor @Suite struct AppModelTests {
    func makeModel(
        _ home: TempHome,
        disk: DiskSpace? = DiskSpace(freeBytes: 80_000_000_000, totalBytes: 228_000_000_000),
        processes: [RunningProcess] = [],
        processListingFails: Bool = false,
        slowProcessListing: Bool = false,
        slowDiskForScan: Bool = false,
        processCalls: OutputCapture? = nil,
        readOnInit: Bool = true
    ) -> AppModel {
        AppModel(
            home: home.url,
            makeEnvironment: { home, settings in
                var environment = SpareEnvironment.test(
                    home: home, projectRoots: settings.projectRootPaths.map { URL(fileURLWithPath: $0) },
                    disk: disk, processes: processes, processListingFails: processListingFails)
                if slowDiskForScan {
                    // Only the scan reads the disk on a background thread; init and refreshes (main) do not wait.
                    environment.diskSpace = { _ in
                        if !Thread.isMainThread { Thread.sleep(forTimeInterval: 0.3) }
                        return disk
                    }
                }
                if slowProcessListing {
                    // Gives the test time to press Stop before the scan reaches its end.
                    environment.processes = {
                        Thread.sleep(forTimeInterval: 0.3)
                        return []
                    }
                }
                if let processCalls {
                    let listing = environment.processes
                    environment.processes = {
                        processCalls.write("listed")
                        return try listing()
                    }
                }
                return environment
            },
            monitorDisk: false, readOnInit: readOnInit)
    }

    func makeJunk(_ home: TempHome) throws {
        try home.file(".npm/_cacache/blob", bytes: 50_000)
        try home.file("Library/Caches/com.example.app/data", bytes: 30_000)
        try home.file(".npm/_npx/abc123/node_modules/pkg/index.js", bytes: 20_000)
    }

    @Test func scanFinishesWithTotalsAndSavesTheReport() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = makeModel(home)

        model.startScan()
        #expect(model.isScanning)
        await model.waitForScan()

        guard case .finished(let report) = model.scanState else {
            Issue.record("scan did not finish")
            return
        }
        #expect(!report.cancelled)
        #expect(model.lastReport?.items.count == report.items.count)
        #expect(report.totalBytes(in: .devCaches) > 0)
        #expect(report.totalBytes(in: .appCaches) > 0)
        #expect(model.finishedCategories == Set(CategoryID.allCases))
        let saved = ScanReportStore(directory: SpareEnvironment.live(home: home.url).supportDirectory).load()
        #expect(saved?.items.count == report.items.count)
    }

    @Test func stopKeepsTheCancelledPartialReport() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = makeModel(home, slowProcessListing: true)

        model.startScan()
        model.cancelScan()
        await model.waitForScan()

        guard case .finished(let report) = model.scanState else {
            Issue.record("scan did not finish")
            return
        }
        #expect(report.cancelled)
        #expect(!model.isScanning)
    }

    @Test func aSecondStartWhileScanningIsIgnored() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let calls = OutputCapture()
        let model = makeModel(home, slowProcessListing: true, processCalls: calls)

        model.startScan()
        model.startScan()
        model.startScan()
        await model.waitForScan()

        // One scan lists the running processes exactly once.
        #expect(calls.text.split(separator: "\n").count == 1)
        guard case .finished = model.scanState else {
            Issue.record("scan did not finish")
            return
        }
    }

    @Test func stopDuringProjectDiscoveryEndsCancelledWithoutListingProcesses() async throws {
        let home = try TempHome()
        defer { home.remove() }
        for name in ["a", "b", "c"] {
            try home.file("Projetos/\(name)/package.json", bytes: 100, modified: daysAgo(90))
            try home.file("Projetos/\(name)/node_modules/x.js", bytes: 40_000)
            try home.directory("Projetos/\(name)/node_modules", modified: daysAgo(90))
            try home.directory("Projetos/\(name)", modified: daysAgo(90))
        }
        try home.directory("Projetos", modified: daysAgo(90))
        let calls = OutputCapture()
        let model = makeModel(home, slowDiskForScan: true, processCalls: calls)

        model.startScan()
        model.cancelScan()
        await model.waitForScan()

        guard case .finished(let report) = model.scanState else {
            Issue.record("scan did not finish")
            return
        }
        #expect(report.cancelled)
        #expect(report.items.filter { $0.category == .projectLeftovers }.isEmpty)
        #expect(calls.text.isEmpty)
    }

    @Test func aStoppedScanWithNothingKeepsThePreviousReportOnDisk() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = makeModel(home)
        model.startScan()
        await model.waitForScan()
        let complete = model.lastReport
        #expect(complete?.cancelled == false)

        let stopped = makeModel(home, slowDiskForScan: true)
        stopped.startScan()
        stopped.cancelScan()
        await stopped.waitForScan()

        #expect(stopped.lastReport?.items.count == complete?.items.count)
        let saved = ScanReportStore(directory: SpareEnvironment.live(home: home.url).supportDirectory).load()
        #expect(saved?.cancelled == false)
        #expect(saved?.items.count == complete?.items.count)
        guard case .finished(let shown) = stopped.scanState else {
            Issue.record("scan did not finish")
            return
        }
        #expect(shown.cancelled)
    }

    @Test func keepRuleForStoppedScans() {
        func report(items: Int, cancelled: Bool) -> ScanReport {
            let item = ScanItem(ruleID: "dev.npm", category: .devCaches, url: URL(fileURLWithPath: "/x"),
                                sizeBytes: 5, safety: .safe)
            return ScanReport(items: Array(repeating: item, count: items), startedAt: Date(), finishedAt: Date(),
                              freeBytesBefore: nil, cancelled: cancelled)
        }
        let complete = report(items: 2, cancelled: false)
        let partial = report(items: 1, cancelled: true)

        #expect(AppModel.shouldKeep(complete, over: nil))
        #expect(AppModel.shouldKeep(complete, over: partial))
        #expect(!AppModel.shouldKeep(report(items: 0, cancelled: true), over: complete))
        #expect(!AppModel.shouldKeep(report(items: 0, cancelled: true), over: nil))
        #expect(!AppModel.shouldKeep(partial, over: complete))
        #expect(AppModel.shouldKeep(partial, over: nil))
        #expect(AppModel.shouldKeep(partial, over: report(items: 3, cancelled: true)))
    }

    @Test func panelShowsDashesUntilTheFirstReadArrives() throws {
        let home = try TempHome()
        defer { home.remove() }
        let model = makeModel(home, readOnInit: false)

        #expect(!model.diskLoaded && !model.memoryLoaded)
        #expect(model.disk == nil && model.memory == nil)

        model.refreshDisk()
        model.refreshMemory()

        #expect(model.diskLoaded && model.memoryLoaded)
        #expect(model.disk != nil)
    }

    @Test func memorySamplingFollowsVisibility() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let model = makeModel(home)
        #expect(model.memorySamples == 0)

        model.setVisible(true, source: "panel")
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.memorySamples == 1)
        #expect(model.consumers != nil)

        model.setVisible(false, source: "panel")
    }

    @Test func failedProcessListingLeavesItemsNotVerifiedAndNotSelectable() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = makeModel(home, processListingFails: true)

        model.startScan()
        await model.waitForScan()

        guard case .finished(let report) = model.scanState,
              let npx = report.items.first(where: { $0.ruleID == "dev.npx" })
        else {
            Issue.record("npx item missing")
            return
        }
        #expect(npx.availability == .notVerified)
        #expect(!npx.availability.isSelectable)
        #expect(report.safeReclaimableBytes == report.items.filter { $0.safety == .safe && $0.inUseBy == nil }.reduce(0) { $0 + $1.sizeBytes })
    }

    @Test func itemsInUseNameTheAppAndAreNotSelectable() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let running = RunningProcess(
            pid: 321, uid: getuid(), rssBytes: 1, executablePath: "/usr/local/bin/node",
            commandLine: "node \(home.path(".npm/_npx/abc123").path)/node_modules/.bin/server",
            appBundlePath: nil, appBundleID: nil, name: "Claude")
        let model = makeModel(home, processes: [running])

        model.startScan()
        await model.waitForScan()

        guard case .finished(let report) = model.scanState,
              let npx = report.items.first(where: { $0.ruleID == "dev.npx" })
        else {
            Issue.record("npx item missing")
            return
        }
        #expect(npx.availability == .inUse(by: "Claude"))
        #expect(!npx.availability.isSelectable)
        #expect(report.items.first { $0.ruleID == "dev.npm" }?.availability == .ready)
    }

    @Test func menuBarShowsRoundedFreeGigabytesAndAlertsBelowTheThreshold() throws {
        let home = try TempHome()
        defer { home.remove() }

        let roomy = makeModel(home, disk: DiskSpace(freeBytes: 15_400_000_000, totalBytes: 228_000_000_000))
        #expect(roomy.menuTitle == "15 GB")
        #expect(!roomy.isDiskLow)

        let tight = makeModel(home, disk: DiskSpace(freeBytes: 9_000_000_000, totalBytes: 228_000_000_000))
        #expect(tight.menuTitle == "9 GB")
        #expect(tight.isDiskLow)
        #expect(tight.recommendation == .lowDisk(freeBytes: 9_000_000_000))

        let unknown = makeModel(home, disk: nil)
        #expect(unknown.menuTitle == "Spare")
        #expect(!unknown.isDiskLow)
        #expect(unknown.recommendation == .allGood)
    }

    @Test func settingsPersistAcrossLaunches() throws {
        let home = try TempHome()
        defer { home.remove() }
        let model = makeModel(home)
        model.settings.diskAlertThresholdGB = 25
        model.saveSettings()

        #expect(makeModel(home).settings.diskAlertThresholdGB == 25)
    }

    @Test func memoryPanelListsTheBiggestUsersOfTheCurrentUser() async throws {
        let home = try TempHome()
        defer { home.remove() }
        func app(_ pid: Int32, _ name: String, mb: Int64, uid: UInt32 = getuid()) -> RunningProcess {
            RunningProcess(pid: pid, uid: uid, rssBytes: mb * 1_000_000,
                           executablePath: "/Applications/\(name).app/Contents/MacOS/\(name)",
                           commandLine: name, appBundlePath: "/Applications/\(name).app",
                           appBundleID: "com.example.\(name)", name: name)
        }
        let model = makeModel(home, processes: [app(401, "Small", mb: 100), app(402, "Big", mb: 900),
                                                 app(403, "Other", mb: 5_000, uid: getuid() &+ 1)])

        await model.refreshConsumers()

        #expect(model.consumers?.map(\.name) == ["Big", "Small"])
        #expect(!model.consumersFailed)
    }

    @Test func failedMemoryListingIsReportedNotHidden() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let model = makeModel(home, processListingFails: true)

        await model.refreshConsumers()

        #expect(model.consumersFailed)
        #expect(model.consumers?.isEmpty == true)
    }
}
