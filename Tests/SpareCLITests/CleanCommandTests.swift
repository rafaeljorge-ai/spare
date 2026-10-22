import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct CleanCommandTests {
    func cli(_ home: TempHome, _ output: OutputCapture, errors: OutputCapture? = nil) -> SpareCLI {
        SpareCLI(environment: .test(home: home.url), write: output.write, writeError: errors?.write)
    }

    func store(_ home: TempHome) -> HistoryStore {
        HistoryStore(directory: SpareEnvironment.test(home: home.url).supportDirectory)
    }

    func trashContents(_ home: TempHome) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: home.trashFolder.path)) ?? []
    }

    @Test func withoutYesItOnlyPreviews() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Library/Logs/App/a.log", bytes: 5_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["clean", "--rule", "apps.logs"])

        #expect(code == 0)
        #expect(home.exists("Library/Logs/App/a.log"))
        #expect(output.text.contains("Would clean"))
        #expect(output.text.contains("--yes"))
        #expect(store(home).load().isEmpty)
    }

    @Test func dryRunWinsOverYes() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Library/Logs/App/a.log", bytes: 5_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["clean", "--rule", "apps.logs", "--yes", "--dry-run"])

        #expect(code == 0)
        #expect(home.exists("Library/Logs/App/a.log"))
        #expect(output.text.contains("Would clean"))
        #expect(store(home).load().isEmpty)
    }

    @Test func withYesItCleansAndRecordsHistory() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Library/Logs/App/a.log", bytes: 5_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["clean", "--rule", "apps.logs", "--yes"])

        #expect(code == 0)
        #expect(!home.exists("Library/Logs/App"))
        #expect(store(home).load().count == 1)
    }

    @Test func itemsInUseAreNeverCleaned() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".npm/_npx/abc/node_modules/x/index.js", bytes: 5_000)
        let busy = RunningProcess(pid: 4242, uid: 501, rssBytes: 1, executablePath: "/usr/local/bin/node",
                                  commandLine: "node \(home.path(".npm/_npx/abc").path)/node_modules/.bin/server",
                                  appBundlePath: nil, appBundleID: nil, name: "node")
        let output = OutputCapture()
        let env = SpareEnvironment.test(home: home.url, processes: [busy])

        let code = await SpareCLI(environment: env, write: output.write)
            .run(["clean", "--rule", "dev.npx", "--yes"])

        #expect(code == 0)
        #expect(home.exists(".npm/_npx/abc/node_modules/x/index.js"))
    }

    @Test func undoRestoresTheLastCleanup() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Downloads/old.dmg", bytes: 5_000, modified: daysAgo(60))
        let output = OutputCapture()
        _ = await cli(home, output).run(["clean", "--rule", "downloads.installers", "--yes"])
        #expect(!home.exists("Downloads/old.dmg"))

        let code = await cli(home, output).run(["undo"])

        #expect(code == 0)
        #expect(home.exists("Downloads/old.dmg"))
        #expect(output.text.contains("Restored 1"))
    }

    @Test func undoSaysWhyAnItemStayedInTheTrash() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Downloads/old.dmg", bytes: 5_000, modified: daysAgo(60))
        let output = OutputCapture()
        _ = await cli(home, output).run(["clean", "--rule", "downloads.installers", "--yes"])
        try home.file("Downloads/old.dmg", bytes: 3)
        let errors = OutputCapture()

        let code = await cli(home, output, errors: errors).run(["undo"])

        #expect(code == 1)
        #expect(errors.text.contains("already exists"))
        #expect(trashContents(home).count == 1)
    }

    @Test func purgeWithoutYesOnlyPreviews() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Downloads/old.dmg", bytes: 5_000, modified: daysAgo(60))
        let output = OutputCapture()
        _ = await cli(home, output).run(["clean", "--rule", "downloads.installers", "--yes"])

        let code = await cli(home, output).run(["purge"])

        #expect(code == 0)
        #expect(trashContents(home).count == 1)
        #expect(output.text.contains("Would delete forever"))
    }

    @Test func purgeFreesOnlySparesTrashedItems() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Downloads/old.dmg", bytes: 5_000, modified: daysAgo(60))
        let output = OutputCapture()
        _ = await cli(home, output).run(["clean", "--rule", "downloads.installers", "--yes"])
        let foreign = home.trashFolder.appendingPathComponent("users-own-file.txt")
        try Data([1]).write(to: foreign)

        let code = await cli(home, output).run(["purge", "--yes"])

        #expect(code == 0)
        #expect(trashContents(home) == ["users-own-file.txt"])
        #expect(store(home).load().first?.entries.first?.status == .purged)
    }

    @Test func historyJSONListsRecords() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Library/Logs/App/a.log")
        let output = OutputCapture()
        _ = await cli(home, output).run(["clean", "--rule", "apps.logs", "--yes"])
        let historyOutput = OutputCapture()

        let code = await cli(home, historyOutput).run(["history", "--json"])

        #expect(code == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([CleanupRecord].self, from: Data(historyOutput.text.utf8)).count == 1)
    }

    @Test func rulesListsTheCatalog() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()

        let code = await cli(home, output).run(["rules"])

        #expect(code == 0)
        #expect(output.text.contains("apps.logs"))
        #expect(output.text.contains("downloads.installers"))
    }

    @Test func cleanRequiresKnownRules() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()

        #expect(await cli(home, output, errors: errors).run(["clean"]) == 64)
        #expect(await cli(home, output, errors: errors).run(["clean", "--rule", "nope"]) == 64)
        #expect(output.text.isEmpty)
    }

    @Test func badRecordIDFailsWithoutTouchingAnything() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()

        #expect(await cli(home, output, errors: errors).run(["undo", "not-a-uuid"]) == 64)
        #expect(await cli(home, output, errors: errors).run(["purge", "not-a-uuid", "--yes"]) == 64)
    }

    @Test func undoWithEmptyHistoryFailsGracefully() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()

        #expect(await cli(home, output, errors: errors).run(["undo"]) == 1)
        #expect(errors.text.contains("No cleanup"))
    }
}
