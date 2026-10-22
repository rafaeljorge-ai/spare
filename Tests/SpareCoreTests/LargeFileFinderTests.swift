import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct LargeFileFinderTests {
    @Test func listsFilesAboveTheMinimumBiggestFirst() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Movies/a.mov", bytes: 300_000)
        try home.file("Downloads/b.zip", bytes: 500_000)
        try home.file("Documents/small.txt", bytes: 1_000)

        let found = LargeFileFinder.find(in: home.url, minBytes: 100_000)

        #expect(found.map(\.url.lastPathComponent) == ["b.zip", "a.mov"])
        #expect(found.first!.sizeBytes >= 500_000)
    }

    @Test func respectsTheLimit() throws {
        let home = try TempHome()
        defer { home.remove() }
        for index in 0..<5 { try home.file("f\(index).bin", bytes: 100_000 + index * 10_000) }

        let found = LargeFileFinder.find(in: home.url, minBytes: 50_000, limit: 2)

        #expect(found.map(\.url.lastPathComponent) == ["f4.bin", "f3.bin"])
    }

    @Test func keepsTheBiggestWhenManyFilesQualify() throws {
        let home = try TempHome()
        defer { home.remove() }
        // Shuffled sizes: the top 3 must survive no matter the visit order.
        for index in [7, 2, 9, 0, 5, 3, 8, 1, 6, 4] { try home.file("d\(index % 3)/f\(index).bin", bytes: 100_000 + index * 8_192) }

        let found = LargeFileFinder.find(in: home.url, minBytes: 50_000, limit: 3)

        #expect(found.map(\.url.lastPathComponent) == ["f9.bin", "f8.bin", "f7.bin"])
    }

    @Test func ignoresSymlinks() throws {
        let home = try TempHome()
        defer { home.remove() }
        let outside = try TempHome()
        defer { outside.remove() }
        try outside.file("huge.bin", bytes: 400_000)
        try FileManager.default.createSymbolicLink(at: home.path("link.bin"), withDestinationURL: outside.path("huge.bin"))
        try FileManager.default.createSymbolicLink(at: home.path("linkdir"), withDestinationURL: outside.url)

        #expect(LargeFileFinder.find(in: home.url, minBytes: 100_000).isEmpty)
    }

    @Test func skipsProtectedFoldersAndPackages() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".ssh/id_ed25519", bytes: 300_000)
        try home.file(".aws/blob", bytes: 300_000)
        try home.file("Library/Keychains/login.keychain-db", bytes: 300_000)
        try home.file("Library/Mail/V10/big.emlx", bytes: 300_000)
        try home.file("Library/Messages/chat.db", bytes: 300_000)
        try home.file("Library/Mobile Documents/com~apple~CloudDocs/x.bin", bytes: 300_000)
        try home.file(".Trash/old.bin", bytes: 300_000)
        try home.file("Apps/Tool.app/Contents/MacOS/Tool", bytes: 300_000)
        try home.file("Photos.photoslibrary/originals/a.heic", bytes: 300_000)
        try home.file("Movies/ok.mov", bytes: 300_000)

        let found = LargeFileFinder.find(in: home.url, minBytes: 100_000, home: home.url)

        #expect(found.map(\.url.lastPathComponent) == ["ok.mov"])
    }

    @Test func aSystemFolderAsRootFindsNothing() {
        #expect(LargeFileFinder.find(in: URL(fileURLWithPath: "/System"), minBytes: 1).isEmpty)
        #expect(LargeFileFinder.find(in: URL(fileURLWithPath: "/usr/bin"), minBytes: 1).isEmpty)
    }

    @Test func aSymlinkAsRootIsNotFollowed() throws {
        let home = try TempHome()
        defer { home.remove() }
        let outside = try TempHome()
        defer { outside.remove() }
        try outside.file("huge.bin", bytes: 400_000)
        let link = home.path("rootlink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.url)

        #expect(LargeFileFinder.find(in: link, minBytes: 100_000).isEmpty)
    }

    @Test func cancellationStopsTheWalk() async throws {
        let home = try TempHome()
        defer { home.remove() }
        for index in 0..<2_500 { try home.file("d\(index % 25)/f\(index).bin", bytes: 8) }

        let task = Task { () -> [LargeFile] in
            // Wait until cancelled, so the walk starts already cancelled.
            while !Task.isCancelled { await Task.yield() }
            return LargeFileFinder.find(in: home.url, minBytes: 1, limit: 5_000)
        }
        task.cancel()
        let found = await task.value

        #expect(found.count < 2_500)
    }

    @Test func progressReportsTheCurrentFolder() throws {
        let home = try TempHome()
        defer { home.remove() }
        for index in 0..<2_200 { try home.file("d\(index % 10)/f\(index).bin", bytes: 8) }
        let seen = LockedBox<[String]>([])

        _ = LargeFileFinder.find(in: home.url, minBytes: 1, limit: 3) { path in seen.mutate { $0.append(path) } }

        #expect(seen.value.count >= 2)
    }

    @Test func libraryIsSkippedUnlessIncluded() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Library/Application Support/Big/data.bin", bytes: 300_000)
        try home.file("Movies/ok.mov", bytes: 300_000)

        let skipped = try LargeFileFinder.search(in: home.url, minBytes: 100_000, home: home.url)
        let included = try LargeFileFinder.search(in: home.url, minBytes: 100_000, home: home.url, includeLibrary: true)

        #expect(skipped.files.map(\.url.lastPathComponent) == ["ok.mov"])
        #expect(Set(included.files.map(\.url.lastPathComponent)) == ["ok.mov", "data.bin"])
    }

    @Test func dependencyFoldersAreSkippedByName() throws {
        let home = try TempHome()
        defer { home.remove() }
        for dir in ["node_modules", ".venv", ".next", "target", "DerivedData"] {
            try home.file("proj/\(dir)/blob.bin", bytes: 300_000)
        }
        try home.file("proj/src/ok.bin", bytes: 300_000)

        let found = LargeFileFinder.find(in: home.url, minBytes: 100_000, home: home.url)

        #expect(found.map(\.url.lastPathComponent) == ["ok.bin"])
    }

    @Test func lastOpenedIsFilledForTheFinalFiles() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("a.bin", bytes: 300_000)

        let found = LargeFileFinder.find(in: home.url, minBytes: 100_000, home: home.url)

        #expect(found.first?.lastOpened != nil)
    }

    @Test func badRootsAreErrors() throws {
        let home = try TempHome()
        defer { home.remove() }
        let file = try home.file("a.bin", bytes: 10)
        #expect(throws: LargeFileError.self) { try LargeFileFinder.search(in: home.path("nope"), minBytes: 1) }
        #expect(throws: LargeFileError.self) { try LargeFileFinder.search(in: file, minBytes: 1) }
        #expect(throws: LargeFileError.self) { try LargeFileFinder.search(in: URL(fileURLWithPath: "/System"), minBytes: 1) }
    }

    @Test func cancelledSearchIsPartial() async throws {
        let home = try TempHome()
        defer { home.remove() }
        for index in 0..<2_500 { try home.file("d\(index % 25)/f\(index).bin", bytes: 8) }
        let task = Task { () -> LargeFileSearch in
            while !Task.isCancelled { await Task.yield() }
            return try LargeFileFinder.search(in: home.url, minBytes: 1, limit: 5_000, home: home.url)
        }
        task.cancel()
        #expect(try await task.value.partial)
        let full = try LargeFileFinder.search(in: home.url, minBytes: 1, limit: 5_000, home: home.url)
        #expect(!full.partial)
    }

    @Test func refusesTrashGitAndTrashesFolders() throws {
        let home = try TempHome()
        defer { home.remove() }
        let paths = [".Trash/old.bin", "proj/.git/objects/pack.bin"]
        let files = try paths.map { LargeFile(url: try home.file($0, bytes: 300_000), sizeBytes: 300_000, lastOpened: nil) }

        let record = LargeFileCleaner(environment: .test(home: home.url)).trash(files)

        for path in paths { #expect(home.exists(path)) }
        #expect(record.entries.allSatisfy { $0.skipReason == .protected })
    }

    @Test func trashingRecordsAnUndoableCleanup() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Movies/a.mov", bytes: 300_000)
        let files = LargeFileFinder.find(in: home.url, minBytes: 100_000)

        let record = LargeFileCleaner(environment: .test(home: home.url)).trash(files)

        #expect(!home.exists("Movies/a.mov"))
        #expect(record.undoableEntries.count == 1)
        #expect(record.entries.first?.category == .largeFiles)
        #expect(record.entries.first?.ruleID == "user.largeFile")
        #expect(record.entries.first?.trashIdentity != nil)
    }

    @Test func trashedFileCanBeUndoneThroughHistory() throws {
        let home = try TempHome()
        defer { home.remove() }
        let env = SpareEnvironment.test(home: home.url)
        try home.file("Movies/a.mov", bytes: 300_000)
        let record = LargeFileCleaner(environment: env).trash(LargeFileFinder.find(in: home.url, minBytes: 100_000))
        let store = HistoryStore(directory: env.supportDirectory)
        try store.append(record)

        let result = try store.undo(recordID: record.id, trash: env.trash)

        #expect(result.restored == 1)
        #expect(home.exists("Movies/a.mov"))
    }

    @Test func refusesCriticalFiles() throws {
        let home = try TempHome()
        defer { home.remove() }
        let key = try home.file(".ssh/id_ed25519", bytes: 300_000)
        let forged = LargeFile(url: key, sizeBytes: 300_000, lastOpened: nil)

        let record = LargeFileCleaner(environment: .test(home: home.url)).trash([forged])

        #expect(home.exists(".ssh/id_ed25519"))
        #expect(record.entries.first?.skipReason == .protected)
    }

    @Test func refusesMailMessagesAndICloudFiles() throws {
        let home = try TempHome()
        defer { home.remove() }
        let paths = ["Library/Mail/V10/a.emlx", "Library/Messages/chat.db", "Library/Mobile Documents/x/y.bin"]
        let files = try paths.map { LargeFile(url: try home.file($0, bytes: 300_000), sizeBytes: 300_000, lastOpened: nil) }

        let record = LargeFileCleaner(environment: .test(home: home.url)).trash(files)

        for path in paths { #expect(home.exists(path)) }
        #expect(record.entries.allSatisfy { $0.skipReason == .protected })
    }

    @Test func refusesFoldersAndSymlinksAndMissingFiles() throws {
        let home = try TempHome()
        defer { home.remove() }
        let outside = try TempHome()
        defer { outside.remove() }
        let target = try outside.file("t.bin", bytes: 300_000)
        let folder = try home.directory("Downloads/stuff")
        try home.file("Downloads/stuff/x.bin", bytes: 300_000)
        let link = home.path("Downloads/link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let missing = home.path("Downloads/gone.bin")
        let files = [folder, link, missing].map { LargeFile(url: $0, sizeBytes: 300_000, lastOpened: nil) }

        let record = LargeFileCleaner(environment: .test(home: home.url)).trash(files)

        #expect(home.exists("Downloads/stuff/x.bin"))
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(record.entries.map(\.skipReason) == [.outsideCatalog, .outsideCatalog, .notFound])
        #expect(record.entries.allSatisfy { $0.status == .skipped })
    }

    @Test func aPathListedTwiceIsMovedOnce() throws {
        let home = try TempHome()
        defer { home.remove() }
        let url = try home.file("Downloads/a.bin", bytes: 300_000)
        let file = LargeFile(url: url, sizeBytes: 300_000, lastOpened: nil)

        let record = LargeFileCleaner(environment: .test(home: home.url)).trash([file, file])

        #expect(record.entries.count == 1)
        #expect(record.undoableEntries.count == 1)
    }

    @Test func parentTraversalIsRefused() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Downloads/a.bin", bytes: 300_000)
        let sneaky = home.url.appendingPathComponent("Downloads/../Downloads/a.bin")

        let record = LargeFileCleaner(environment: .test(home: home.url))
            .trash([LargeFile(url: sneaky, sizeBytes: 300_000, lastOpened: nil)])

        #expect(home.exists("Downloads/a.bin"))
        #expect(record.entries.first?.skipReason == .outsideCatalog)
    }

    @Test func cancelledRunTouchesNothing() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let url = try home.file("Downloads/a.bin", bytes: 300_000)
        let file = LargeFile(url: url, sizeBytes: 300_000, lastOpened: nil)
        let env = SpareEnvironment.test(home: home.url)

        let task = Task { () -> CleanupRecord in
            while !Task.isCancelled { await Task.yield() }
            return LargeFileCleaner(environment: env).trash([file])
        }
        task.cancel()
        let record = await task.value

        #expect(home.exists("Downloads/a.bin"))
        #expect(record.cancelled)
        #expect(record.entries.first?.skipReason == .cancelled)
    }
}

/// Tiny lock-protected box for collecting values from `@Sendable` callbacks.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout Value) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}
