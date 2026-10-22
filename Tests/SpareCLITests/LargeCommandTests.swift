import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct LargeCommandTests {
    func cli(_ home: TempHome, _ output: OutputCapture, errors: OutputCapture? = nil) -> SpareCLI {
        SpareCLI(environment: .test(home: home.url), write: output.write, writeError: errors?.write)
    }

    func store(_ home: TempHome) -> HistoryStore {
        HistoryStore(directory: SpareEnvironment.test(home: home.url).supportDirectory)
    }

    @Test func largeJSONListsFiles() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Movies/a.mov", bytes: 2_000_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["large", "--min-mb", "1", "--json"])

        #expect(code == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = try decoder.decode([LargeFile].self, from: Data(output.text.utf8))
        #expect(files.map(\.url.lastPathComponent) == ["a.mov"])
    }

    @Test func largeListsAGivenFolder() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Movies/a.mov", bytes: 2_000_000)
        try home.file("Downloads/b.zip", bytes: 3_000_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["large", home.path("Downloads").path, "--min-mb", "1"])

        #expect(code == 0)
        #expect(output.text.contains("b.zip"))
        #expect(!output.text.contains("a.mov"))
    }

    @Test func invalidMinimumIsRejected() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()

        #expect(await cli(home, output, errors: errors).run(["large", "--min-mb", "lots"]) == 64)
        #expect(output.text.isEmpty)
        #expect(errors.text.contains("--min-mb"))
    }

    @Test func aFlagWithoutValueIsRejected() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let errors = OutputCapture()

        #expect(await cli(home, OutputCapture(), errors: errors).run(["large", "--limit"]) == 64)
        #expect(errors.text.contains("--limit"))
    }

    @Test func trashWithoutYesOnlyPreviews() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let file = try home.file("Movies/a.mov", bytes: 2_000_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["large", "--trash", file.path])

        #expect(code == 0)
        #expect(home.exists("Movies/a.mov"))
        #expect(output.text.contains("Would move"))
        #expect(output.text.contains("--yes"))
        #expect((try store(home).load()).isEmpty)
    }

    @Test func dryRunWinsOverYes() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let file = try home.file("Movies/a.mov", bytes: 2_000_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["large", "--trash", file.path, "--yes", "--dry-run"])

        #expect(code == 0)
        #expect(home.exists("Movies/a.mov"))
        #expect(output.text.contains("Dry run"))
        #expect((try store(home).load()).isEmpty)
    }

    @Test func trashWithYesMovesRecordsAndCanBeUndone() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let file = try home.file("Movies/a.mov", bytes: 2_000_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["large", "--trash", file.path, "--yes"])

        #expect(code == 0)
        #expect(!home.exists("Movies/a.mov"))
        let records = try store(home).load()
        #expect(records.count == 1)
        #expect(records.first?.entries.first?.category == .largeFiles)
        #expect(output.text.contains("spare undo"))

        let undone = await cli(home, OutputCapture()).run(["undo"])
        #expect(undone == 0)
        #expect(home.exists("Movies/a.mov"))
    }

    @Test func protectedFileIsRefusedWithAnError() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let key = try home.file(".ssh/id_ed25519", bytes: 2_000_000)
        let output = OutputCapture()
        let errors = OutputCapture()

        let code = await cli(home, output, errors: errors).run(["large", "--trash", key.path, "--yes"])

        #expect(code == 1)
        #expect(home.exists(".ssh/id_ed25519"))
        #expect(errors.text.contains("protected"))
    }

    @Test func badRootIsAnErrorOnStderr() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()

        let code = await cli(home, output, errors: errors).run(["large", home.path("nope").path])

        #expect(code != 0)
        #expect(output.text.isEmpty)
        #expect(!errors.text.isEmpty)
    }

    @Test func previewJSONMarksProtectedFiles() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let key = try home.file(".ssh/id_ed25519", bytes: 2_000_000)
        let ok = try home.file("Movies/a.mov", bytes: 2_000_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["large", "--trash", key.path, "--trash", ok.path, "--json"])

        #expect(code == 0)
        let items = try #require(JSONSerialization.jsonObject(with: Data(output.text.utf8)) as? [[String: Any]])
        #expect(items.map { $0["protected"] as? Bool } == [true, false])
    }

    @Test func relativeTrashPathWorks() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Movies/a.mov", bytes: 2_000_000)
        let previous = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(previous) }
        FileManager.default.changeCurrentDirectoryPath(home.path("Movies").path)

        let code = await cli(home, OutputCapture()).run(["large", "--trash", "./a.mov", "--yes"])

        #expect(code == 0)
        #expect(!home.exists("Movies/a.mov"))
    }
}
