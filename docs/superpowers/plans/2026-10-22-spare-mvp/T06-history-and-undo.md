# Task 6: History, undo, purge and the cleaning CLI

Persists every cleanup in `history.json`, restores trashed items (Undo), permanently deletes Spare's own items from the Trash (Purge, the step that actually frees the space of trashed items), and exposes `spare clean`, `spare undo`, `spare purge` and `spare history`. After this task the engine is complete end to end from the terminal.

**Files:**
- Create: `Sources/SpareCore/History/JSONFileStore.swift`, `Sources/SpareCore/History/HistoryStore.swift`
- Modify: `Sources/SpareCore/Support/SpareEnvironment.swift` (add `supportDirectory`)
- Modify: `Sources/SpareCLI/SpareCLI.swift` (add commands)
- Create: `scripts/qa-fake-home.sh`
- Test: `Tests/SpareCoreTests/HistoryStoreTests.swift`, `Tests/SpareCLITests/CleanCommandTests.swift`
- Modify: `README.md` (CLI usage), `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `CleanupRecord`, `CleanupEntry`, `EntryStatus`, `TrashService`, `Cleaner`, `Scanner`, `SpareCLI.option`, `SpareCLI.encode`.
- Produces:
  - `JSONFileStore<Value: Codable>(url:)` with `load() -> Value?` (corrupt file renamed to `<name>.corrupt-<unix time>.json`, returns nil) and `save(_:) throws` (atomic, creates the folder with 0700).
  - `HistoryStore(directory: URL, limit: Int = 100)`: `load() -> [CleanupRecord]` (newest first), `append(_:) throws`, `undo(recordID: UUID, trash: any TrashService) throws -> UndoResult`, `purge(recordID: UUID) throws -> Int64`, `clear() throws`.
  - `struct UndoResult: Codable, Sendable { restored: Int; failed: [String] }`, `enum HistoryError: Error { case recordNotFound }`.
  - `SpareEnvironment.supportDirectory: URL` (computed: `<home>/Library/Application Support/Spare`).
  - CLI: `spare clean --rule ID... [--yes] [--json]`, `spare undo [RECORD_ID]`, `spare purge [RECORD_ID]`, `spare history [--json]`.

- [ ] **Step 1: Write the failing history tests**

`Tests/SpareCoreTests/HistoryStoreTests.swift`:

```swift
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
                            trashPath: trashed.path, action: .trash, sizeBytes: 2_000, status: .done)
    }

    @Test func appendsAndLoadsNewestFirst() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let older = record(entries: [], at: daysAgo(2))
        let newer = record(entries: [], at: daysAgo(1))

        try store.append(older)
        try store.append(newer)

        #expect(store.load().map(\.id) == [newer.id, older.id])
    }

    @Test func keepsOnlyTheLimit() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"), limit: 3)

        for _ in 0..<5 { try store.append(record(entries: [])) }

        #expect(store.load().count == 3)
    }

    @Test func corruptFileIsSetAsideAndHistoryStartsEmpty() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("support/history.json", bytes: 10)
        let store = HistoryStore(directory: home.path("support"))

        #expect(store.load().isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: home.path("support").path)
        #expect(leftovers.contains { $0.hasPrefix("history.json.corrupt-") })
        try store.append(record(entries: []))
        #expect(store.load().count == 1)
    }

    @Test func undoRestoresTrashedItemsWithTheirContent() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)

        let result = try store.undo(recordID: saved.id, trash: FolderTrash(folder: home.trashFolder))

        #expect(result.restored == 1)
        #expect(result.failed.isEmpty)
        #expect(try Data(contentsOf: home.path("Downloads/old.dmg")).count == 2_000)
        #expect(store.load().first?.entries.first?.status == .restored)
    }

    @Test func undoNeverOverwritesARecreatedOriginal() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let saved = record(entries: [entry])
        try store.append(saved)
        try home.file("Downloads/old.dmg", bytes: 7)

        let result = try store.undo(recordID: saved.id, trash: FolderTrash(folder: home.trashFolder))

        #expect(result.restored == 0)
        #expect(result.failed == [entry.originalPath])
        #expect(try Data(contentsOf: home.path("Downloads/old.dmg")).count == 7)
        #expect(FileManager.default.fileExists(atPath: entry.trashPath!))
        #expect(store.load().first?.entries.first?.status == .done)
    }

    @Test func purgeDeletesOnlySparesTrashedItems() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        let entry = try trashedEntry(home, original: "Downloads/old.dmg")
        let unrelated = try home.file("-unrelated-trash-item")
        let saved = record(entries: [entry])
        try store.append(saved)

        let freed = try store.purge(recordID: saved.id)

        #expect(freed == 2_000)
        #expect(!FileManager.default.fileExists(atPath: entry.trashPath!))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(store.load().first?.entries.first?.status == .purged)
    }

    @Test func unknownRecordThrows() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))

        #expect(throws: HistoryError.recordNotFound) {
            try store.undo(recordID: UUID(), trash: FolderTrash(folder: home.trashFolder))
        }
    }

    @Test func clearRemovesEverything() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = HistoryStore(directory: home.path("support"))
        try store.append(record(entries: []))

        try store.clear()

        #expect(store.load().isEmpty)
    }
}
```

Run: `swift test --filter HistoryStoreTests` → FAIL.

- [ ] **Step 2: Implement the stores**

`Sources/SpareCore/History/JSONFileStore.swift`:

```swift
import Foundation

/// Small JSON file with atomic writes. A corrupt file is renamed, never deleted.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public func save(_ value: Value) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
```

`Sources/SpareCore/History/HistoryStore.swift`:

```swift
import Foundation

public struct UndoResult: Codable, Sendable, Equatable {
    public let restored: Int
    public let failed: [String]
}

public enum HistoryError: Error, Equatable {
    case recordNotFound
}

public struct HistoryStore: Sendable {
    let file: JSONFileStore<[CleanupRecord]>
    public let limit: Int

    public init(directory: URL, limit: Int = 100) {
        file = JSONFileStore(url: directory.appendingPathComponent("history.json"))
        self.limit = limit
    }

    /// Newest first.
    public func load() -> [CleanupRecord] {
        (file.load() ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    public func append(_ record: CleanupRecord) throws {
        var records = load()
        records.insert(record, at: 0)
        try file.save(Array(records.sorted { $0.startedAt > $1.startedAt }.prefix(limit)))
    }

    public func undo(recordID: UUID, trash: any TrashService) throws -> UndoResult {
        try mutate(recordID) { record in
            var restored = 0
            var failed: [String] = []
            for index in record.entries.indices {
                let entry = record.entries[index]
                guard entry.status == .done, entry.action == .trash, let trashPath = entry.trashPath else { continue }
                do {
                    try trash.restore(URL(fileURLWithPath: trashPath), to: URL(fileURLWithPath: entry.originalPath))
                    record.entries[index].status = .restored
                    restored += 1
                } catch {
                    failed.append(entry.originalPath)
                }
            }
            return UndoResult(restored: restored, failed: failed)
        }
    }

    /// Permanently deletes this record's items that are still in the Trash. Returns bytes freed.
    public func purge(recordID: UUID) throws -> Int64 {
        try mutate(recordID) { record in
            var freed: Int64 = 0
            for index in record.entries.indices {
                let entry = record.entries[index]
                guard entry.status == .done, entry.action == .trash, let trashPath = entry.trashPath,
                      FileManager.default.fileExists(atPath: trashPath)
                else { continue }
                if (try? FileManager.default.removeItem(atPath: trashPath)) != nil {
                    record.entries[index].status = .purged
                    freed += entry.sizeBytes
                }
            }
            return freed
        }
    }

    public func clear() throws {
        try file.delete()
    }

    func mutate<T>(_ id: UUID, _ change: (inout CleanupRecord) throws -> T) throws -> T {
        var records = load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw HistoryError.recordNotFound }
        let result = try change(&records[index])
        try file.save(records)
        return result
    }
}
```

`SpareEnvironment`: add

```swift
    public var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/Spare", isDirectory: true)
    }
```

Run: `swift test --filter HistoryStoreTests` → PASS.

- [ ] **Step 3: Write the failing CLI tests**

`Tests/SpareCLITests/CleanCommandTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct CleanCommandTests {
    func cli(_ home: TempHome, _ output: OutputCapture) -> SpareCLI {
        SpareCLI(environment: .test(home: home.url), write: output.write)
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
    }

    @Test func withYesItCleansAndRecordsHistory() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Library/Logs/App/a.log", bytes: 5_000)
        let output = OutputCapture()

        let code = await cli(home, output).run(["clean", "--rule", "apps.logs", "--yes"])

        #expect(code == 0)
        #expect(!home.exists("Library/Logs/App"))
        let history = HistoryStore(directory: SpareEnvironment.test(home: home.url).supportDirectory).load()
        #expect(history.count == 1)
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

    @Test func purgeFreesTrashedItems() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Downloads/old.dmg", bytes: 5_000, modified: daysAgo(60))
        let output = OutputCapture()
        _ = await cli(home, output).run(["clean", "--rule", "downloads.installers", "--yes"])

        let code = await cli(home, output).run(["purge"])

        #expect(code == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.trashFolder.path).isEmpty)
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

    @Test func cleanRequiresKnownRules() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()

        #expect(await cli(home, output).run(["clean"]) == 64)
        #expect(await cli(home, output).run(["clean", "--rule", "nope"]) == 64)
    }

    @Test func undoWithEmptyHistoryFailsGracefully() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()

        #expect(await cli(home, output).run(["undo"]) == 1)
        #expect(output.text.contains("No cleanup"))
    }
}
```

Run: `swift test --filter CleanCommandTests` → FAIL.

- [ ] **Step 4: Implement the CLI commands**

In `SpareCLI.run`, add cases:

```swift
        case "clean": return await clean(Array(args.dropFirst()), json: json)
        case "undo": return undo(Array(args.dropFirst()))
        case "purge": return purge(Array(args.dropFirst()))
        case "history": return history(json: json)
```

Usage additions:

```
  spare clean --rule ID [--rule ID] [--yes]   Clean items of these rules (preview without --yes)
  spare undo [RECORD_ID]                      Restore trashed items of the last (or given) cleanup
  spare purge [RECORD_ID]                     Permanently delete Spare's items from the Trash
  spare history [--json]                      Past cleanups
  spare rules                                 List rule IDs
```

Add `case "rules"`: print `id  category  safety` per rule of `RuleCatalog.standard`, return 0.

Implementation (add to `SpareCLI`):

```swift
    var historyStore: HistoryStore { HistoryStore(directory: environment.supportDirectory) }

    func clean(_ args: [String], json: Bool) async -> Int32 {
        let ruleIDs = Self.option("--rule", in: args)
        let rules = ruleIDs.compactMap { RuleCatalog.standard.rule(id: $0) }
        guard !ruleIDs.isEmpty, rules.count == ruleIDs.count else {
            write("Pass one or more valid --rule IDs (see: spare rules)")
            return 64
        }
        let report = await Scanner(environment: environment).scan(categories: Set(rules.map(\.category)))
        let items = report.items.filter { item in ruleIDs.contains(item.ruleID) && item.inUseBy == nil }
        let total = items.reduce(Int64(0)) { $0 + $1.sizeBytes }

        guard args.contains("--yes") else {
            write("Would clean \(items.count) item(s), \(ByteFormat.string(total)):")
            items.forEach { write("  \(ByteFormat.string($0.sizeBytes))  \($0.url.path)") }
            write("Run again with --yes to clean.")
            return 0
        }

        let record = await Cleaner(environment: environment).clean(items)
        do {
            try historyStore.append(record)
        } catch {
            write("Warning: could not save history: \(error.localizedDescription)")
        }
        if json {
            write(Self.encode(record))
        } else {
            write("Cleaned \(ByteFormat.string(record.cleanedBytes)) in \(record.entries.filter { $0.status == .done }.count) item(s).")
            for entry in record.entries where entry.status != .done {
                write("  \(entry.status.rawValue) (\(entry.skipReason?.rawValue ?? entry.detail ?? "")): \(entry.originalPath)")
            }
            if record.trashedBytes > 0 {
                write("\(ByteFormat.string(record.trashedBytes)) went to the Trash. Undo: spare undo \(record.id). Free it now: spare purge \(record.id)")
            }
        }
        return record.entries.contains { $0.status == .failed } ? 1 : 0
    }

    func targetRecordID(_ args: [String]) -> UUID? {
        if let given = args.first { return UUID(uuidString: given) }
        return historyStore.load().first?.id
    }

    func undo(_ args: [String]) -> Int32 {
        guard let id = targetRecordID(args) else {
            write("No cleanup to undo.")
            return 1
        }
        do {
            let result = try historyStore.undo(recordID: id, trash: environment.trash)
            write("Restored \(result.restored) item(s).")
            result.failed.forEach { write("  Kept in Trash (original path exists or item missing): \($0)") }
            return result.failed.isEmpty ? 0 : 1
        } catch {
            write("No cleanup with id \(id).")
            return 1
        }
    }

    func purge(_ args: [String]) -> Int32 {
        guard let id = targetRecordID(args) else {
            write("No cleanup to purge.")
            return 1
        }
        do {
            write("Freed \(ByteFormat.string(try historyStore.purge(recordID: id))) from the Trash.")
            return 0
        } catch {
            write("No cleanup with id \(id).")
            return 1
        }
    }

    func history(json: Bool) -> Int32 {
        let records = historyStore.load()
        if json {
            write(Self.encode(records))
            return 0
        }
        if records.isEmpty { write("No cleanups yet.") }
        for record in records {
            write("\(record.id)  \(record.startedAt.formatted())  \(ByteFormat.string(record.cleanedBytes))  \(record.entries.count) item(s)")
        }
        return 0
    }
```

Run: `swift test` → PASS.

- [ ] **Step 5: End to end QA script on a fake home**

`scripts/qa-fake-home.sh` (make executable): builds the CLI, creates a fake home under `mktemp -d`, fills it with junk (npm cache folder, Library/Caches/com.example.app, an old `.dmg` in Downloads with `touch -t` 60 days back, a project in `Projetos/old` with `package.json` and `node_modules`, and `Documents/keep.txt`), then runs with `SPARE_HOME` set: `spare scan`, `spare clean --rule apps.caches --rule downloads.installers --rule project.nodeModules --yes`, asserts with `test -e`/`test ! -e` that the caches and node_modules are gone, the dmg is in `~/.Trash` of the fake home, `Documents/keep.txt` still exists, then `spare undo` and asserts the dmg is back. Prints `QA OK` and removes the fake home. Uses `set -euo pipefail` and a `trap` for cleanup.

Important: `SystemTrash` moves fake-home files into the Trash of the volume owner (the real user Trash) because `FileManager.trashItem` ignores `SPARE_HOME`. Therefore the script must set `SPARE_TRASH_DIR` and the CLI must honor it: in `Sources/spare/main.swift`, when `SPARE_TRASH_DIR` is set, build the environment with a `DirectoryTrash` (add `public struct DirectoryTrash: TrashService` to `SpareCore/Clean/TrashService.swift`, same behavior as the test `FolderTrash`; then make `FolderTrash` in test support a thin wrapper or remove it in favor of `DirectoryTrash`). The QA script sets `SPARE_TRASH_DIR="$FAKE_HOME/.Trash"`.

Run: `scripts/qa-fake-home.sh` → `QA OK`.

- [ ] **Step 6: Docs, gates, commit**

README CLI section with all commands and a "safe first run" example (`spare scan`, then `spare clean --rule dev.npm` without `--yes`). CHANGELOG `Added: history, undo and purge; spare clean/undo/purge/history/rules`. STATUS. `scripts/check.sh` green, plus `scripts/qa-fake-home.sh` green (record both outputs in the PR).

```bash
git add -A
git commit -m "feat(cli): add clean, undo, purge and history

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
