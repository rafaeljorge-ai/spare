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
        slowProcessListing: Bool = false
    ) -> AppModel {
        AppModel(
            home: home.url,
            makeEnvironment: { home, settings in
                var environment = SpareEnvironment.test(
                    home: home, projectRoots: settings.projectRootPaths.map { URL(fileURLWithPath: $0) },
                    disk: disk, processes: processes, processListingFails: processListingFails)
                if slowProcessListing {
                    // Gives the test time to press Stop before the scan reaches its end.
                    environment.processes = {
                        Thread.sleep(forTimeInterval: 0.3)
                        return []
                    }
                }
                return environment
            },
            monitorDisk: false)
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
        #expect((model.scanTotals[.devCaches] ?? 0) > 0)
        #expect((model.scanTotals[.appCaches] ?? 0) > 0)
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
        let model = makeModel(home, slowProcessListing: true)

        model.startScan()
        model.startScan()
        await model.waitForScan()

        guard case .finished = model.scanState else {
            Issue.record("scan did not finish")
            return
        }
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
