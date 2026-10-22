import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

/// Counts calls from `@Sendable` closures.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func hit() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

@Suite struct CleanerTests {
    let catalog = RuleCatalog.standard

    func item(_ ruleID: String, _ url: URL, size: Int64 = 1_000, inUseBy: String? = nil) -> ScanItem {
        let rule = catalog.rule(id: ruleID)!
        return ScanItem(ruleID: ruleID, category: rule.category, url: url, sizeBytes: size,
                        safety: rule.safety, inUseBy: inUseBy)
    }

    let claude = RunningProcess(
        pid: 1, uid: 501, rssBytes: 1, executablePath: "/Applications/Claude.app/Contents/MacOS/Claude",
        commandLine: "/Applications/Claude.app/Contents/MacOS/Claude",
        appBundlePath: "/Applications/Claude.app", appBundleID: "com.anthropic.claudefordesktop", name: "Claude")

    /// An idle project: manifest, sources and the install all older than the idle window.
    @discardableResult
    func makeProject(_ home: TempHome, _ path: String, touchedDaysAgo: Double = 60) throws -> URL {
        let date = daysAgo(touchedDaysAgo)
        try home.file("\(path)/package.json", bytes: 200, modified: date)
        try home.file("\(path)/src/index.js", bytes: 200, modified: date)
        try home.file("\(path)/node_modules/lib/index.js", bytes: 20_000)
        return try home.directory("\(path)/node_modules", modified: date)
    }

    // MARK: Actions

    @Test func deleteActionRemovesTheItemForGood() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let logs = try home.directory("Library/Logs/SomeApp")
        try home.file("Library/Logs/SomeApp/a.log")

        let record = await Cleaner(environment: .test(home: home.url)).clean([item("apps.logs", logs)])

        #expect(!home.exists("Library/Logs/SomeApp"))
        #expect(record.entries.map(\.status) == [.done])
        #expect(record.entries.first?.action == .delete)
        #expect(record.cleanedBytes == 1_000)
    }

    @Test func trashActionMovesToTrashAndRemembersWhere() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let installer = try home.file("Downloads/old.dmg", modified: daysAgo(60))

        let record = await Cleaner(environment: .test(home: home.url)).clean([item("downloads.installers", installer)])

        let entry = try #require(record.entries.first)
        #expect(entry.status == .done)
        #expect(entry.action == .trash)
        let trashPath = try #require(entry.trashPath)
        #expect(FileManager.default.fileExists(atPath: trashPath))
        #expect(trashPath.hasPrefix(home.trashFolder.path))
        #expect(!home.exists("Downloads/old.dmg"))
        #expect(record.undoableEntries.count == 1)
        #expect(record.trashedBytes == 1_000)
    }

    @Test func commandRunsOncePerRuleAndKeepsFiles() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let cache = try home.directory(".npm/_cacache")
        let runner = RecordingCommandRunner()

        let record = await Cleaner(environment: .test(home: home.url, commandRunner: runner))
            .clean([item("dev.npm", cache), item("dev.npm", cache)])

        #expect(runner.calls == ["npm cache clean --force"])
        #expect(record.entries.map(\.status) == [.done, .done])
    }

    @Test func missingToolIsSkippedNotFailed() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let cache = try home.directory(".cache/uv")

        let record = await Cleaner(environment: .test(home: home.url, commandRunner: RecordingCommandRunner(missing: ["uv"])))
            .clean([item("dev.uv", cache)])

        #expect(record.entries.first?.status == .skipped)
        #expect(record.entries.first?.skipReason == .toolNotFound)
    }

    @Test func failingCommandIsReportedAsFailed() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let cache = try home.directory(".cache/uv")

        let record = await Cleaner(environment: .test(home: home.url, commandRunner: RecordingCommandRunner(exitCode: 2)))
            .clean([item("dev.uv", cache)])

        #expect(record.entries.first?.status == .failed)
        #expect(record.entries.first?.detail?.contains("boom") == true)
    }

    @Test func emptyTrashRemovesContentsButKeepsTheFolder() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let trash = try home.directory(".Trash")
        try home.file(".Trash/old.zip")
        try home.file(".Trash/folder/x.txt")

        let record = await Cleaner(environment: .test(home: home.url)).clean([item("system.trash", trash)])

        #expect(record.entries.first?.status == .done)
        #expect(home.exists(".Trash"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    // MARK: Guards at clean time

    @Test func forgedItemsOutsideTheCatalogAreNeverTouched() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let precious = try home.file("Documents/thesis.pdf")
        let other = try home.directory("Projects-not-root/app/node_modules")

        let record = await Cleaner(environment: .test(home: home.url))
            .clean([item("apps.logs", precious), item("project.nodeModules", other), item("dev.npm", home.url)])

        #expect(FileManager.default.fileExists(atPath: precious.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(record.entries.allSatisfy { $0.status == .skipped })
        #expect(Set(record.entries.compactMap(\.skipReason)).isSubset(of: [.protected, .outsideCatalog]))
    }

    @Test func unknownRuleIsRefused() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let file = try home.file("Library/Logs/x.log")
        let forged = ScanItem(ruleID: "evil.rule", category: .logs, url: file, sizeBytes: 1, safety: .safe)

        let record = await Cleaner(environment: .test(home: home.url)).clean([forged])

        #expect(record.entries.first?.skipReason == .outsideCatalog)
        #expect(home.exists("Library/Logs/x.log"))
    }

    @Test func symlinkToOutsideIsRefusedAndTargetSurvives() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let outside = try TempHome()
        defer { outside.remove() }
        try outside.file("data/important.db")
        try home.directory("Library/Caches")
        let link = home.path("Library/Caches/com.example.link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.path("data"))

        let record = await Cleaner(environment: .test(home: home.url)).clean([item("apps.caches", link)])

        #expect(record.entries.first?.status == .skipped)
        #expect(outside.exists("data/important.db"))
    }

    @Test func itemThatVanishedIsSkippedAsNotFound() async throws {
        let home = try TempHome()
        defer { home.remove() }

        let record = await Cleaner(environment: .test(home: home.url))
            .clean([item("apps.logs", home.path("Library/Logs/gone"))])

        #expect(record.entries.first?.status == .skipped)
        #expect(record.entries.first?.skipReason == .notFound)
    }

    @Test func itemInUseAtCleanTimeIsSkipped() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let vm = try home.directory("Library/Application Support/Claude/vm_bundles")
        try home.file("Library/Application Support/Claude/vm_bundles/disk.img")

        let record = await Cleaner(environment: .test(home: home.url, processes: [claude])).clean([item("ai.claudeVM", vm)])

        #expect(record.entries.first?.skipReason == .inUse)
        #expect(record.entries.first?.detail == "Claude")
        #expect(home.exists("Library/Application Support/Claude/vm_bundles/disk.img"))
    }

    @Test func itemFlaggedInUseByTheScanIsNeverCleaned() async throws {
        let home = try TempHome()
        defer { home.remove() }
        // apps.logs has no in-use check of its own: only the scan's flag protects it.
        let logs = try home.directory("Library/Logs/SomeApp")
        let cache = try home.directory(".npm/_cacache")
        let runner = RecordingCommandRunner()

        let record = await Cleaner(environment: .test(home: home.url, commandRunner: runner)).clean([
            item("apps.logs", logs, inUseBy: "SomeApp"),
            item("dev.npm", cache, inUseBy: InUseGuard.unknownReason),
        ])

        #expect(record.entries.map(\.skipReason) == [.inUse, .inUse])
        #expect(record.entries.map(\.detail) == ["SomeApp", InUseGuard.unknownReason])
        #expect(home.exists("Library/Logs/SomeApp"))
        #expect(runner.calls.isEmpty)
    }

    @Test func processesAreListedOncePerRunNotPerItem() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let a = try home.directory("Library/Caches/com.example.a")
        let b = try home.directory("Library/Caches/com.example.b")
        let c = try home.directory("Library/Caches/com.example.c")
        let counter = CallCounter()
        var environment = SpareEnvironment.test(home: home.url)
        environment.processes = {
            counter.hit()
            return []
        }

        let record = await Cleaner(environment: environment)
            .clean([item("apps.caches", a), item("apps.caches", b), item("apps.caches", c)])

        #expect(counter.count == 1)
        #expect(record.entries.map(\.status) == [.done, .done, .done])
    }

    @Test func failedProcessListingSkipsEveryItemThatNeedsTheCheck() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let cache = try home.directory("Library/Caches/com.example.app")
        let vm = try home.directory("Library/Application Support/Claude/vm_bundles")
        let logs = try home.directory("Library/Logs/SomeApp")
        let npm = try home.directory(".npm/_cacache")
        let runner = RecordingCommandRunner()

        let record = await Cleaner(environment: .test(home: home.url, commandRunner: runner, processListingFails: true))
            .clean([item("apps.caches", cache), item("ai.claudeVM", vm), item("apps.logs", logs), item("dev.npm", npm)])

        #expect(record.entries.map(\.status) == [.skipped, .skipped, .done, .done])
        #expect(record.entries.prefix(2).allSatisfy { $0.skipReason == .inUse && $0.detail == InUseGuard.unknownReason })
        #expect(home.exists("Library/Caches/com.example.app"))
        #expect(home.exists("Library/Application Support/Claude/vm_bundles"))
        #expect(!home.exists("Library/Logs/SomeApp"))
    }

    @Test func safetyGuardRunsRightBeforeActingNotOnlyAtScanTime() async throws {
        let home = try TempHome()
        defer { home.remove() }
        // The scan saw an old installer; it was replaced by a fresh download before the cleanup.
        let installer = try home.file("Downloads/fresh.dmg")

        let record = await Cleaner(environment: .test(home: home.url)).clean([item("downloads.installers", installer)])

        #expect(record.entries.first?.skipReason == .outsideCatalog)
        #expect(home.exists("Downloads/fresh.dmg"))
    }

    @Test func safetyGuardUsesTheEnvironmentClock() async throws {
        let home = try TempHome()
        defer { home.remove() }
        // 20 days old: too young for the 30 day rule today, old enough when the clock is 20 days ahead.
        let installer = try home.file("Downloads/mid.dmg", modified: daysAgo(20))
        let later = Date().addingTimeInterval(20 * 86_400)

        let today = await Cleaner(environment: .test(home: home.url)).clean([item("downloads.installers", installer)])
        let ahead = await Cleaner(environment: .test(home: home.url, now: { later }))
            .clean([item("downloads.installers", installer)])

        #expect(today.entries.first?.skipReason == .outsideCatalog)
        #expect(ahead.entries.first?.status == .done)
    }

    // MARK: Project artifacts

    @Test func idleProjectArtifactIsDeleted() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let artifact = try makeProject(home, "Projetos/old-app")

        let record = await Cleaner(environment: .test(home: home.url, projectRoots: [home.path("Projetos")]))
            .clean([item("project.nodeModules", artifact)])

        #expect(record.entries.first?.status == .done)
        #expect(!home.exists("Projetos/old-app/node_modules"))
        #expect(home.exists("Projetos/old-app/src/index.js"))
    }

    @Test func projectUsedAgainSinceTheScanIsSkipped() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let artifact = try makeProject(home, "Projetos/old-app")
        // The user edited the project after the scan.
        try home.file("Projetos/old-app/src/new.js")

        let record = await Cleaner(environment: .test(home: home.url, projectRoots: [home.path("Projetos")]))
            .clean([item("project.nodeModules", artifact)])

        #expect(record.entries.first?.status == .skipped)
        #expect(record.entries.first?.skipReason == .projectActive)
        #expect(home.exists("Projetos/old-app/node_modules/lib/index.js"))
    }

    @Test func monorepoPackageIsMeasuredAtTheRepositoryRoot() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Projetos/mono/.git/HEAD", bytes: 10, modified: daysAgo(60))
        let artifact = try makeProject(home, "Projetos/mono/packages/a")
        try home.file("Projetos/mono/packages/b/package.json", bytes: 100)  // sibling package touched today

        let record = await Cleaner(environment: .test(home: home.url, projectRoots: [home.path("Projetos")]))
            .clean([item("project.nodeModules", artifact)])

        #expect(record.entries.first?.skipReason == .projectActive)
        #expect(home.exists("Projetos/mono/packages/a/node_modules/lib/index.js"))
    }

    @Test func freshInstallInsideTheArtifactCountsAsActivity() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let artifact = try makeProject(home, "Projetos/old-app")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: artifact.path)

        let record = await Cleaner(environment: .test(home: home.url, projectRoots: [home.path("Projetos")]))
            .clean([item("project.nodeModules", artifact)])

        #expect(record.entries.first?.skipReason == .projectActive)
    }

    // MARK: Record

    @Test func cancellationSkipsRemainingItems() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let a = try home.directory("Library/Logs/A")
        let b = try home.directory("Library/Logs/B")
        var environment = SpareEnvironment.test(home: home.url)
        environment.diskSpace = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return nil
        }
        let cleaner = Cleaner(environment: environment)

        let task = Task { await cleaner.clean([item("apps.logs", a), item("apps.logs", b)]) }
        task.cancel()
        let record = await task.value

        #expect(record.cancelled)
        #expect(record.entries.allSatisfy { $0.skipReason == .cancelled })
        #expect(home.exists("Library/Logs/A"))
    }

    @Test func recordsFreeSpaceBeforeAndAfter() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let logs = try home.directory("Library/Logs/X")

        let record = await Cleaner(environment: .test(home: home.url)).clean([item("apps.logs", logs)])

        #expect(record.freeBytesBefore == 10_000_000_000)
        #expect(record.freeBytesAfter == 10_000_000_000)
    }

    @Test func reportsProgressForEachItem() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let a = try home.directory("Library/Logs/A")
        let b = try home.directory("Library/Logs/B")
        let seen = OutputCapture()

        _ = await Cleaner(environment: .test(home: home.url)).clean([item("apps.logs", a), item("apps.logs", b)]) {
            seen.write("\($0.index + 1)/\($0.total) \($0.entry.status.rawValue)")
        }

        #expect(seen.text == "1/2 done\n2/2 done")
    }
}
