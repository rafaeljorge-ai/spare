import Foundation
import Testing
import SpareCore
import SpareTestSupport
@testable import SpareApp

@MainActor @Suite struct LargeFilesModelTests {
    func makeModel(
        _ home: TempHome, search: @escaping LargeFilesModel.Search = { _, _, _, _ in LargeFileSearch(files: [], partial: false) },
        diskChanges: Counter = Counter()
    ) -> LargeFilesModel {
        let environment = SpareEnvironment.test(home: home.url)
        return LargeFilesModel(home: home.url, environment: { environment }, didChangeDisk: { diskChanges.bump() }, search: search)
    }

    final class Counter {
        var value = 0
        func bump() { value += 1 }
    }

    func file(_ url: URL, _ bytes: Int64) -> LargeFile {
        LargeFile(url: url, sizeBytes: bytes, lastOpened: nil)
    }

    // MARK: Search

    @Test func searchPublishesTheResultAndTheMinimumSize() async throws {
        let home = try TempHome()
        let seenMinimum = Box<Int64>(0)
        let big = file(home.path("Movies/a.mov"), 2_000_000_000)
        let model = makeModel(home, search: { _, minBytes, _, _ in
            seenMinimum.set(minBytes)
            return LargeFileSearch(files: [big], partial: false)
        })
        model.minMB = 750
        model.startSearch()
        #expect(model.isSearching)
        await model.waitForSearch()
        #expect(model.files == [big])
        #expect(model.phase == .done(partial: false))
        #expect(seenMinimum.value == 750_000_000)
    }

    @Test func stopKeepsWhatWasFoundAndSaysPartial() async throws {
        let home = try TempHome()
        let partial = file(home.path("Movies/a.mov"), 900_000_000)
        let model = makeModel(home, search: { _, _, _, _ in
            while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.005) }
            return LargeFileSearch(files: [partial], partial: true)
        })
        model.startSearch()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.isSearching)
        model.stopSearch()
        await model.waitForSearch()
        #expect(model.phase == .done(partial: true))
        #expect(model.files == [partial])
    }

    @Test func aBadFolderIsAnErrorNotAnEmptyResult() async throws {
        let home = try TempHome()
        let model = makeModel(home, search: { folder, _, _, _ in throw LargeFileError.notFound(folder.path) })
        model.startSearch()
        await model.waitForSearch()
        #expect(model.phase == .failed(.notFound(home.url.path)))
    }

    @Test func searchRunsOffTheMainThread() async throws {
        let home = try TempHome()
        let onMain = Box<Bool>(true)
        let model = makeModel(home, search: { _, _, _, _ in
            onMain.set(Thread.isMainThread)
            return LargeFileSearch(files: [], partial: false)
        })
        model.startSearch()
        await model.waitForSearch()
        #expect(!onMain.value)
    }

    @Test func aSecondSearchWhileRunningIsIgnored() async throws {
        let home = try TempHome()
        let runs = Box<Int>(0)
        let model = makeModel(home, search: { _, _, _, _ in
            runs.set(runs.value + 1)
            Thread.sleep(forTimeInterval: 0.05)
            return LargeFileSearch(files: [], partial: false)
        })
        model.startSearch()
        model.startSearch()
        await model.waitForSearch()
        #expect(runs.value == 1)
    }

    // MARK: Trash

    @Test func nothingMovesWithoutAConfirmation() async throws {
        let home = try TempHome()
        let url = try home.file("Movies/big.mov", bytes: 1000)
        let model = makeModel(home)
        await model.confirmTrash()
        #expect(FileManager.default.fileExists(atPath: url.path))

        model.ask(file(url, 1000))
        model.cancelPending()
        await model.confirmTrash()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(model.outcome == nil)
    }

    @Test func confirmingMovesTheFileRecordsHistoryAndUndoBringsItBack() async throws {
        let home = try TempHome()
        let url = try home.file("Movies/big.mov", bytes: 1000)
        let big = file(url, 1000)
        let other = file(home.path("Movies/other.mov"), 500)
        let changes = Counter()
        let model = makeModel(home, search: { _, _, _, _ in LargeFileSearch(files: [big, other], partial: false) }, diskChanges: changes)
        model.startSearch()
        await model.waitForSearch()

        model.ask(big)
        await model.confirmTrash()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(model.files == [other])
        #expect(changes.value == 1)
        guard case .trashed(let moved, let recordID) = model.outcome else {
            Issue.record("expected a trashed outcome, got \(String(describing: model.outcome))")
            return
        }
        #expect(moved == big)

        let environment = SpareEnvironment.test(home: home.url)
        let history = try HistoryStore(directory: environment.supportDirectory).load()
        #expect(history.map(\.id) == [recordID])
        #expect(history[0].entries.first?.originalPath == url.path)
        #expect(history[0].entries.first?.category == .largeFiles)

        await model.undoLast()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(model.files.map(\.id) == [big.id, other.id])
        #expect(model.outcome == .restored("big.mov"))
    }

    @Test func aFailedHistoryWriteIsToldAndOffersNoUndo() async throws {
        let home = try TempHome()
        let url = try home.file("Movies/big.mov", bytes: 1000)
        // A plain file where the support folder should be: the History cannot be written.
        try home.file("Library/Application Support", bytes: 1)
        let model = makeModel(home)
        model.ask(file(url, 1000))
        await model.confirmTrash()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(model.outcome == .trashedUnrecorded(file(url, 1000)))
        await model.undoLast()  // nothing to undo: the outcome stays
        #expect(model.outcome == .trashedUnrecorded(file(url, 1000)))
    }

    @Test func aMissingFileIsNotMovedAndLeavesNoHistory() async throws {
        let home = try TempHome()
        let ghost = file(home.path("Movies/gone.mov"), 1000)
        let model = makeModel(home)
        model.ask(ghost)
        await model.confirmTrash()
        guard case .notMoved = model.outcome else {
            Issue.record("expected notMoved, got \(String(describing: model.outcome))")
            return
        }
        let environment = SpareEnvironment.test(home: home.url)
        #expect(try HistoryStore(directory: environment.supportDirectory).load().isEmpty)
    }

    @Test func aProtectedFileIsRefused() async throws {
        let home = try TempHome()
        let url = try home.file("Library/Mail/V10/mail.db", bytes: 1000)
        let model = makeModel(home)
        model.ask(file(url, 1000))
        await model.confirmTrash()
        #expect(FileManager.default.fileExists(atPath: url.path))
        guard case .notMoved = model.outcome else {
            Issue.record("expected notMoved, got \(String(describing: model.outcome))")
            return
        }
    }
}

final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func set(_ value: Value) { lock.withLock { stored = value } }
}
