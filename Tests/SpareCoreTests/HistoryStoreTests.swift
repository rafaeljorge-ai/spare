import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct HistoryStoreTests {
    func record(entries: [CleanupEntry], at date: Date = Date()) -> CleanupRecord {
        CleanupRecord(startedAt: date, finishedAt: date, freeBytesBefore: 1, freeBytesAfter: 2,
                      entries: entries, cancelled: false)
    }

    func trashedEntry(_ home: TempHome, original: String) throws -> CleanupEntry {
        let file = try home.file(original, bytes: 2_000)
        let trashed = try FolderTrash(folder: home.trashFolder).moveToTrash(file)
        return CleanupEntry(ruleID: "downloads.installers", category: .installers, originalPath: file.path,
                            trashPath: trashed.path, trashIdentity: HistoryStore.identity(of: trashed.path),
                            action: .trash, sizeBytes: 2_000, status: .done)
    }

    func trash(_ home: TempHome) -> FolderTrash {
        FolderTrash(folder: home.trashFolder)
    }

    func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    @Test func appendsAndLoadsNewestFirst() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let older = record(entries: [], at: daysAgo(2))
        let newer = record(entries: [], at: daysAgo(1))

        try store.append(older)
        try store.append(newer)

        #expect((try store.load()).map(\.id) == [newer.id, older.id])
    }

    @Test func keepsOnlyTheLimit() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"), limit: 3)

        for _ in 0..<5 { try store.append(record(entries: [])) }

        #expect((try store.load()).count == 3)
    }

    @Test func folderIsPrivateAndFileIsOwnerOnly() throws {
        let home = try TempHome()
        defer { home.remove() }
        let folder = home.path("Library/Application Support/Spare")
        let store = HistoryStore(directory: folder)

        try store.append(record(entries: []))

        func mode(_ url: URL) throws -> Int {
            (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1
        }
        #expect(try mode(folder) == 0o700)
        #expect(try mode(folder.appendingPathComponent("history.json")) == 0o600)
    }

    @Test func corruptFileIsSetAsideAndHistoryStartsEmpty() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("support/history.json", bytes: 10)
        let store = HistoryStore(directory: home.path("support"))

        #expect((try store.load()).isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: home.path("support").path)
        #expect(leftovers.contains { $0.hasPrefix("history.json.corrupt-") })
        try store.append(record(entries: []))
        #expect((try store.load()).count == 1)
    }

    @Test func twoCorruptFilesInTheSameSecondAreBothKept() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        try home.file("support/history.json", bytes: 10)
        _ = (try store.load())
        try home.file("support/history.json", bytes: 11)
        _ = (try store.load())

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: home.path("support").path)
        #expect(leftovers.filter { $0.hasPrefix("history.json.corrupt-") }.count == 2)
    }

    @Test func undoRestoresTrashedItemsWithTheirContent() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)

        let result = try store.undo(recordID: saved.id, trash: trash(home))

        #expect(result.restored == 1)
        #expect(result.failed.isEmpty)
        #expect(try Data(contentsOf: home.path("Downloads/old.dmg")).count == 2_000)
        #expect((try store.load()).first?.entries.first?.status == .restored)
    }

    @Test func undoNeverOverwritesARecreatedOriginal() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        try home.file("Downloads/old.dmg", bytes: 7)

        let result = try store.undo(recordID: saved.id, trash: trash(home))

        #expect(result.restored == 0)
        #expect(result.failed == [entry.originalPath])
        #expect(result.failures.first?.reason == .destinationExists)
        #expect(try Data(contentsOf: home.path("Downloads/old.dmg")).count == 7)
        #expect(FileManager.default.fileExists(atPath: entry.trashPath!))
        #expect((try store.load()).first?.entries.first?.status == .done)
    }

    @Test func undoNeverOverwritesADanglingSymlinkAtTheOriginal() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        try FileManager.default.createSymbolicLink(
            atPath: entry.originalPath, withDestinationPath: home.path("nowhere").path)

        let result = try store.undo(recordID: saved.id, trash: trash(home))

        #expect(result.restored == 0)
        #expect(result.failures.first?.reason == .destinationExists)
        #expect(FileManager.default.fileExists(atPath: entry.trashPath!))
    }

    @Test func undoReportsAnItemThatLeftTheTrash() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        try FileManager.default.removeItem(atPath: entry.trashPath!)

        let result = try store.undo(recordID: saved.id, trash: trash(home))

        #expect(result.restored == 0)
        #expect(result.failures.first?.reason == .missingInTrash)
        #expect((try store.load()).first?.entries.first?.status == .done)
    }

    @Test func undoSkipsAnItemSomeoneElsePutAtTheSameTrashPath() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        try FileManager.default.removeItem(atPath: entry.trashPath!)
        try Data(repeating: 0x62, count: 9).write(to: URL(fileURLWithPath: entry.trashPath!))

        let result = try store.undo(recordID: saved.id, trash: trash(home))

        #expect(result.restored == 0)
        #expect(result.failures.first?.reason == .changedInTrash)
        #expect(!exists(entry.originalPath))
        #expect(exists(entry.trashPath!))
    }

    @Test func undoRefusesPathsOutsideTheTrash() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let precious = try home.file("Documents/precious.txt", bytes: 5)
        let forged = CleanupEntry(ruleID: "downloads.installers", category: .installers,
                                  originalPath: home.path("Downloads/elsewhere.txt").path, trashPath: precious.path,
                                  trashIdentity: HistoryStore.identity(of: precious.path), action: .trash, sizeBytes: 5, status: .done)
        let saved = record(entries: [forged])
        try store.append(saved)

        let result = try store.undo(recordID: saved.id, trash: trash(home))

        #expect(result.restored == 0)
        #expect(result.failures.first?.reason == .changedInTrash)
        #expect(exists(precious.path))
        #expect(!home.exists("Downloads/elsewhere.txt"))
    }

    @Test func undoRefusesNonNormalizedOriginals() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let forged = CleanupEntry(ruleID: entry.ruleID, category: entry.category,
                                  originalPath: home.url.path + "/Downloads/../Escaped.dmg", trashPath: entry.trashPath,
                                  trashIdentity: entry.trashIdentity, action: .trash, sizeBytes: 2_000, status: .done)
        let saved = record(entries: [forged])
        try store.append(saved)

        let result = try store.undo(recordID: saved.id, trash: trash(home))

        #expect(result.restored == 0)
        #expect(result.failures.first?.reason == .invalidPath)
        #expect(exists(entry.trashPath!))
    }

    @Test func purgeDeletesOnlySparesTrashedItems() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let unrelated = home.trashFolder.appendingPathComponent("-unrelated-trash-item")
        try Data([1, 2, 3]).write(to: unrelated)
        let saved = record(entries: [entry])
        try store.append(saved)

        let freed = try store.purge(recordID: saved.id, trash: trash(home)).freedBytes

        #expect(freed == 2_000)
        #expect(!exists(entry.trashPath!))
        #expect(exists(unrelated.path))
        #expect((try store.load()).first?.entries.first?.status == .purged)
    }

    @Test func purgeIsIdempotent() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let saved = record(entries: [try trashedEntry(home, original: "Downloads/old.dmg")])
        try store.append(saved)

        #expect(try store.purge(recordID: saved.id, trash: trash(home)).freedBytes == 2_000)
        #expect(try store.purge(recordID: saved.id, trash: trash(home)).freedBytes == 0)
    }

    @Test func purgeSkipsAnItemReplacedAtTheSameTrashPath() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        // The user emptied the Trash and later trashed a different file that got the same name.
        try FileManager.default.removeItem(atPath: entry.trashPath!)
        try Data(repeating: 0x62, count: 9).write(to: URL(fileURLWithPath: entry.trashPath!))

        let freed = try store.purge(recordID: saved.id, trash: trash(home)).freedBytes

        #expect(freed == 0)
        #expect(exists(entry.trashPath!))
        #expect((try store.load()).first?.entries.first?.status == .done)
    }

    @Test func purgeNeverFollowsASymlinkPlacedInTheTrash() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        let precious = try home.file("Documents/precious/keep.txt", bytes: 5)
        try FileManager.default.removeItem(atPath: entry.trashPath!)
        try FileManager.default.createSymbolicLink(
            atPath: entry.trashPath!, withDestinationPath: precious.deletingLastPathComponent().path)

        let freed = try store.purge(recordID: saved.id, trash: trash(home)).freedBytes

        #expect(freed == 0)
        #expect(exists(precious.path))
        #expect(exists(entry.trashPath!))
    }

    @Test func purgeNeverDeletesOutsideTheTrash() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let precious = try home.file("Documents/precious.txt", bytes: 5)
        let forged = CleanupEntry(ruleID: "downloads.installers", category: .installers,
                                  originalPath: home.path("Downloads/x.dmg").path, trashPath: precious.path,
                                  trashIdentity: HistoryStore.identity(of: precious.path), action: .trash, sizeBytes: 5, status: .done)
        let saved = record(entries: [forged])
        try store.append(saved)

        #expect(try store.purge(recordID: saved.id, trash: trash(home)).freedBytes == 0)
        #expect(exists(precious.path))
    }

    @Test func purgeIgnoresEntriesThatAreNotUndoableTrashItems() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        var restored = try trashedEntry(home, original: "Downloads/a.dmg")
        restored.status = .restored
        var deleted = try trashedEntry(home, original: "Downloads/b.dmg")
        deleted.action = .delete
        let saved = record(entries: [restored, deleted])
        try store.append(saved)

        #expect(try store.purge(recordID: saved.id, trash: trash(home)).freedBytes == 0)
        #expect(exists(restored.trashPath!))
        #expect(exists(deleted.trashPath!))
    }

    @Test func pendingPurgeListsWithoutDeleting() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)

        let pending = try store.pendingPurge(recordID: saved.id, trash: trash(home))

        #expect(pending.map(\.originalPath) == [entry.originalPath])
        #expect(exists(entry.trashPath!))
        #expect((try store.load()).first?.entries.first?.status == .done)
    }

    @Test func unknownRecordThrows() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))

        #expect(throws: HistoryError.recordNotFound) {
            try store.undo(recordID: UUID(), trash: trash(home))
        }
        #expect(throws: HistoryError.recordNotFound) {
            try store.purge(recordID: UUID(), trash: trash(home))
        }
    }

    @Test func clearRemovesEverything() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        try store.append(record(entries: []))

        try store.clear()

        #expect((try store.load()).isEmpty)
    }

    // MARK: Round 1 fixes

    @Test func unreadableHistoryFileFailsInsteadOfBeingReplaced() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        try store.append(record(entries: []))
        let file = home.path("support/history.json")
        let before = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        #expect(throws: (any Error).self) { try store.append(record(entries: [])) }
        #expect(throws: (any Error).self) { _ = try store.load() }

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == before)
        #expect(try store.load().count == 1)
    }

    @Test func missingFileIsAnEmptyHistory() throws {
        let home = try TempHome()
        defer { home.remove() }

        #expect(try HistoryStore(directory: home.path("never-created")).load().isEmpty)
    }

    @Test func concurrentAppendsAreAllKept() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let count = 64

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask { try store.append(record(entries: [])) }
            }
            try await group.waitForAll()
        }

        #expect(try store.load().count == count)
    }

    @Test func appendDoesNotStampIdentityItself() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        var entry = try trashedEntry(home, original: "Downloads/old.dmg")
        entry.trashIdentity = nil
        let saved = record(entries: [entry])
        try store.append(saved)

        #expect(try store.load().first?.entries.first?.trashIdentity == nil)
        #expect(try store.purge(recordID: saved.id, trash: trash(home)).freedBytes == 0)
        #expect(exists(entry.trashPath!))
    }

    @Test func itemReplacedInTheTrashBetweenCleanAndSaveIsNotPurged() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let installer = try home.file("Downloads/old.dmg", bytes: 1_000, modified: daysAgo(60))
        let scanned = ScanItem(ruleID: "downloads.installers", category: .installers, url: installer,
                               sizeBytes: 1_000, safety: .safe)
        let cleaned = await Cleaner(environment: .test(home: home.url)).clean([scanned])
        let entry = try #require(cleaned.entries.first)
        #expect(entry.trashIdentity != nil)
        // Minutes pass: the user empties the Trash and later trashes another file with the same name.
        try FileManager.default.removeItem(atPath: entry.trashPath!)
        try Data(repeating: 0x62, count: 9).write(to: URL(fileURLWithPath: entry.trashPath!))
        let store = HistoryStore(directory: home.path("support"))
        try store.append(cleaned)

        let result = try store.purge(recordID: cleaned.id, trash: trash(home))

        #expect(result.freedBytes == 0)
        #expect(exists(entry.trashPath!))
        #expect(result.failures.first?.path == entry.originalPath)
    }

    @Test func undoPreviewChangesNothing() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let blocked = try trashedEntry(home, original: "Downloads/taken.dmg")
        let saved = record(entries: [entry, blocked])
        try store.append(saved)
        try home.file("Downloads/taken.dmg", bytes: 3)

        let preview = try store.previewUndo(recordID: saved.id, trash: trash(home))

        #expect(preview.wouldRestore.map(\.originalPath) == [entry.originalPath])
        #expect(preview.failures == [UndoFailure(path: blocked.originalPath, reason: .destinationExists)])
        #expect(!home.exists("Downloads/old.dmg"))
        #expect(exists(entry.trashPath!))
        #expect(try store.load().first?.entries.allSatisfy { $0.status == .done } == true)
    }

    @Test func purgeReportsAnItemItCouldNotRemove() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        // A folder the owner cannot write into cannot have its children removed.
        let locked = home.trashFolder
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }

        let result = try store.purge(recordID: saved.id, trash: trash(home))

        #expect(result.freedBytes == 0)
        #expect(result.failures.map(\.path) == [entry.originalPath])
        #expect(try store.load().first?.entries.first?.status == .done)
    }

    @Test func purgeUnlinksAValidlyStampedSymlinkAndSparesItsTarget() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let precious = try home.file("Documents/precious/keep.txt", bytes: 5)
        _ = trash(home) // creates the fake Trash folder
        let link = home.trashFolder.appendingPathComponent("link-to-outside")
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: precious.deletingLastPathComponent().path)
        // Stamped from the link itself (lstat), so identity matches and the purge really reaches `removeItem`.
        let entry = CleanupEntry(ruleID: "downloads.installers", category: .installers,
                                 originalPath: home.path("Downloads/x.dmg").path, trashPath: link.path,
                                 trashIdentity: HistoryStore.identity(of: link.path),
                                 action: .trash, sizeBytes: 77, status: .done)
        let saved = record(entries: [entry])
        try store.append(saved)

        let result = try store.purge(recordID: saved.id, trash: trash(home))

        #expect(result.freedBytes == 77)
        #expect(!exists(link.path))
        #expect(try Data(contentsOf: precious).count == 5)
        #expect(try store.load().first?.entries.first?.status == .purged)
    }
}
