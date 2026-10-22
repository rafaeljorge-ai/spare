import Foundation
import Testing
import SpareCore
import SpareTestSupport
@testable import SpareApp

/// The cleanup flow through `AppModel`, on a fake home and a folder instead of the Trash.
@MainActor @Suite struct CleanupFlowTests {
    func makeModel(
        _ home: TempHome,
        processes: [RunningProcess] = [],
        processListingFails: Bool = false,
        slowProcessListing: Bool = false
    ) -> AppModel {
        AppModel(
            home: home.url,
            makeEnvironment: { home, _ in
                var environment = SpareEnvironment.test(
                    home: home, processes: processes, processListingFails: processListingFails)
                if slowProcessListing {
                    // Gives the test time to press Stop before the Cleaner reaches its first item.
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
        try home.file("Library/Logs/Example/a.log", bytes: 9_000)
        try home.file("Library/Caches/com.example.app/data", bytes: 30_000)
        try home.file(".npm/_npx/abc123/node_modules/pkg/index.js", bytes: 20_000)
        try home.file("Downloads/old.dmg", bytes: 40_000, modified: daysAgo(60))
        try home.file("Documents/keep.txt", bytes: 100)
    }

    func scanned(_ home: TempHome, _ model: AppModel? = nil) async -> AppModel {
        let model = model ?? makeModel(home)
        model.startScan()
        await model.waitForScan()
        return model
    }

    func cleanedRecord(_ model: AppModel) -> CleanupRecord? {
        guard case .result(let id) = model.cleanupRoute else { return nil }
        return model.record(id: id)
    }

    @Test func nothingRunsWithoutTheConfirmation() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home)

        model.requestClean(model.lastReport!.items(in: .logs))

        #expect(model.pendingPlan?.items.count == 1)
        #expect(!model.isCleaning)
        #expect(model.cleanupRoute == .cards)
        #expect(home.exists("Library/Logs/Example/a.log"))

        model.dismissPlan()
        model.confirmClean()
        await model.waitForClean()

        #expect(model.pendingPlan == nil)
        #expect(!model.isCleaning)
        #expect(model.cleanupRoute == .cards)
        #expect(home.exists("Library/Logs/Example/a.log"))
        #expect(model.history.isEmpty)
    }

    @Test func confirmedCleanDeletesSavesTheRecordAndTrimsTheReport() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home)
        let logs = model.lastReport!.items(in: .logs)

        model.requestClean(logs)
        model.confirmClean()
        #expect(model.cleanupRoute == .progress)
        #expect(model.isCleaning)
        await model.waitForClean()

        #expect(!home.exists("Library/Logs/Example"))
        #expect(home.exists("Documents/keep.txt"))
        let record = cleanedRecord(model)
        #expect(record?.entries.map(\.originalPath) == logs.map(\.url.path))
        #expect(record?.entries.allSatisfy { $0.status == .done } == true)
        #expect(model.history.count == 1)
        #expect(model.isSaved(record!.id))
        #expect(model.lastReport?.items(in: .logs).isEmpty == true)
        #expect(model.lastCleanup?.id == record?.id)
        #expect(!model.isCleaning)
        let saved = try HistoryStore(directory: SpareEnvironment.live(home: home.url).supportDirectory).load()
        #expect(saved.first?.id == record?.id)
    }

    @Test func progressIsMatchedByPathNotByTheOrderAsked() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        try home.file(".Trash/old-thing", bytes: 5_000)
        let model = await scanned(home)
        let report = model.lastReport!
        let trash = report.items(in: .trash)
        let logs = report.items(in: .logs)
        #expect(trash.count == 1)

        // Asked: logs first, Trash last. The Cleaner empties the Trash first.
        model.requestClean(logs + trash)
        model.confirmClean()
        #expect(model.cleanQueue.first?.ruleID == "system.trash")
        await model.waitForClean()

        #expect(model.cleanEntries.first?.ruleID == "system.trash")
        #expect(model.cleanEntries.map(\.originalPath) == model.cleanQueue.map(\.url.path))
        #expect(!home.exists(".Trash/old-thing"))
        #expect(!home.exists("Library/Logs/Example"))
    }

    @Test func itemsInUseOrNotVerifiedNeverEnterAPlan() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let running = RunningProcess(
            pid: 321, uid: getuid(), rssBytes: 1, executablePath: "/usr/local/bin/node",
            commandLine: "node \(home.path(".npm/_npx/abc123").path)/node_modules/.bin/server",
            appBundlePath: nil, appBundleID: nil, name: "Claude")
        let busy = await scanned(home, makeModel(home, processes: [running]))
        let npx = busy.lastReport!.items.filter { $0.ruleID == "dev.npx" }
        #expect(npx.first?.inUseBy == "Claude")
        busy.requestClean(npx)
        #expect(busy.pendingPlan == nil)

        let unknown = await scanned(home, makeModel(home, processListingFails: true))
        let unchecked = unknown.lastReport!.items.filter { $0.inUseBy == InUseGuard.unknownReason }
        #expect(!unchecked.isEmpty)
        unknown.requestClean(unchecked)
        #expect(unknown.pendingPlan == nil)
        unknown.openReview(.devCaches)
        for item in unchecked { unknown.toggle(item) }
        #expect(unknown.selectedItemIDs.isDisjoint(with: unchecked.map(\.id)))
        #expect(home.exists(".npm/_npx/abc123/node_modules/pkg/index.js"))
    }

    @Test func reviewStartsWithSafeFreeItemsSelected() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        try home.file(".npm/_cacache/blob", bytes: 10_000)
        let model = await scanned(home)

        model.openReview(.devCaches)

        let items = model.lastReport!.items(in: .devCaches)
        let safe = Set(items.filter { $0.safety == .safe }.map(\.id))
        #expect(!safe.isEmpty)
        #expect(model.selectedItemIDs == safe)
        #expect(items.contains { $0.safety == .review })
        #expect(model.cleanupRoute == .review(.devCaches))

        model.setAll(true, in: .devCaches)
        #expect(model.selectedItemIDs == Set(items.map(\.id)))
        model.setAll(false, in: .devCaches)
        #expect(model.selectedItems(in: .devCaches).isEmpty)
    }

    @Test func cleanSafeIncludesOnlySafeItems() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home)

        model.requestCleanSafe()

        let plan = try #require(model.pendingPlan)
        #expect(model.selection == .cleanup)
        #expect(plan.items.allSatisfy { $0.safety == .safe && $0.inUseBy == nil })
        #expect(!plan.items.contains { $0.ruleID == "dev.npx" })
        #expect(plan.trashCount == 1)
    }

    @Test func undoBringsTheTrashedItemBack() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home)
        model.requestClean(model.lastReport!.items(in: .installers))
        model.confirmClean()
        await model.waitForClean()
        let record = try #require(cleanedRecord(model))
        #expect(!home.exists("Downloads/old.dmg"))
        #expect(CleanOutcome(record).trashedBytes > 0)

        await model.undo(record.id)

        #expect(home.exists("Downloads/old.dmg"))
        #expect(model.notice == .restored(1, stayed: 0))
        #expect(model.record(id: record.id)?.entries.first?.status == .restored)
        #expect(model.busyRecord == nil)
    }

    @Test func undoKeepsTheItemInTheTrashWhenTheOriginalPlaceIsTaken() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home)
        model.requestClean(model.lastReport!.items(in: .installers))
        model.confirmClean()
        await model.waitForClean()
        let record = try #require(cleanedRecord(model))
        try home.file("Downloads/old.dmg", bytes: 3)

        await model.undo(record.id)

        #expect(model.notice == .restored(0, stayed: 1))
        #expect(try Data(contentsOf: home.path("Downloads/old.dmg")).count == 3)
        #expect(model.record(id: record.id)?.entries.first?.status == .done)
    }

    @Test func freeItNowDeletesOnlySparesTrashItems() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home)
        model.requestClean(model.lastReport!.items(in: .installers))
        model.confirmClean()
        await model.waitForClean()
        let record = try #require(cleanedRecord(model))
        let theirs = home.trashFolder.appendingPathComponent("users-own-file.txt")
        try Data("mine".utf8).write(to: theirs)

        await model.purge(record.id)

        #expect(model.notice == .freed(record.entries[0].sizeBytes, purged: 1, stayed: 0))
        #expect(FileManager.default.fileExists(atPath: theirs.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.trashFolder.path) == ["users-own-file.txt"])
        #expect(model.record(id: record.id)?.entries.first?.status == .purged)
        #expect(CleanOutcome(model.record(id: record.id)!).trashedBytes == 0)
    }

    @Test func stopSkipsTheRestAndStillSavesTheRecord() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home, makeModel(home, slowProcessListing: true))
        let caches = model.lastReport!.items(in: .appCaches)
        #expect(!caches.isEmpty)

        model.requestClean(caches + model.lastReport!.items(in: .logs))
        model.confirmClean()
        model.stopClean()
        #expect(model.isStopping)
        await model.waitForClean()

        let record = try #require(cleanedRecord(model))
        #expect(record.cancelled)
        #expect(record.entries.allSatisfy { $0.status == .skipped && $0.skipReason == .cancelled })
        #expect(home.exists("Library/Caches/com.example.app/data"))
        #expect(!model.isStopping)
        #expect(model.history.count == 1)
    }

    @Test func anUnreadableHistoryIsAnErrorNotAnEmptyList() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let model = await scanned(home)
        model.requestClean(model.lastReport!.items(in: .logs))
        model.confirmClean()
        await model.waitForClean()
        let file = SpareEnvironment.live(home: home.url).supportDirectory.appendingPathComponent("history.json")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        model.reloadHistory()

        #expect(model.historyFailed)
        #expect(model.history.count == 1)
    }

    @Test func entryNotesExplainSkipsAndOutcomes() {
        func entry(_ status: EntryStatus, _ reason: SkipReason? = nil, detail: String? = nil,
                   action: ActionKind = .delete) -> CleanupEntry {
            CleanupEntry(ruleID: "dev.npx", category: .devCaches, originalPath: "/h/x", action: action,
                         sizeBytes: 1, status: status, skipReason: reason, detail: detail)
        }

        #expect(EntryNote(entry(.skipped, .inUse, detail: "Claude")) == .inUse("Claude"))
        #expect(EntryNote(entry(.skipped, .inUse, detail: "unknown")) == .notVerified)
        #expect(EntryNote(entry(.skipped, .notFound)) == .alreadyGone)
        #expect(EntryNote(entry(.skipped, .protected)) == .protected)
        #expect(EntryNote(entry(.skipped, .outsideCatalog)) == .protected)
        #expect(EntryNote(entry(.skipped, .cancelled)) == .stopped)
        #expect(EntryNote(entry(.skipped, .toolNotFound)) == .toolMissing)
        #expect(EntryNote(entry(.skipped, .projectActive)) == .projectActive)
        #expect(EntryNote(entry(.failed, detail: "boom")) == .failed("boom"))
        #expect(EntryNote(entry(.restored, action: .trash)) == .restored)
        #expect(EntryNote(entry(.purged, action: .trash)) == .purged)
        #expect(EntryNote(entry(.done, action: .trash)) == .inTrash)
        #expect(EntryNote(entry(.done)) == .none)
    }

    @Test func friendlyNamesForRulesAndProjects() {
        #expect(ItemName.of(ruleID: "dev.npm", category: .devCaches, path: "/h/.npm/_cacache") == "npm")
        #expect(ItemName.of(ruleID: "project.nodeModules", category: .projectLeftovers,
                            path: "/h/Projetos/imobai/node_modules") == "imobai/node_modules")
        #expect(ItemName.of(ruleID: "downloads.installers", category: .installers,
                            path: "/h/Downloads/Docker.dmg") == "Docker.dmg")
    }
}
