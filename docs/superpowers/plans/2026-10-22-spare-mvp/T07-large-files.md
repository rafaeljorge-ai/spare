# Task 7: Large files

Finds the biggest files under a folder the user picks and moves chosen ones to the Trash, recorded in history so Undo works.

**Files:**
- Create: `Sources/SpareCore/Scan/LargeFileFinder.swift`, `Sources/SpareCore/Clean/LargeFileCleaner.swift`
- Modify: `Sources/SpareCore/Rules/Rule.swift` (add `CategoryID.largeFiles`), `Sources/SpareCLI/SpareCLI.swift` (add `large`)
- Test: `Tests/SpareCoreTests/LargeFileFinderTests.swift`, `Tests/SpareCLITests/LargeCommandTests.swift`
- Modify: `README.md`, `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `SafetyGuard.canTrashUserFile`, `TrashService`, `CleanupRecord`, `CleanupEntry`, `HistoryStore`, `SpareEnvironment`.
- Produces:
  - `CategoryID.largeFiles` (appended last in the enum; no catalog rule uses it).
  - `public struct LargeFile: Codable, Sendable, Identifiable, Hashable { id: String (path); url: URL; sizeBytes: Int64; lastOpened: Date? }`
  - `LargeFileFinder.find(in: URL, minBytes: Int64, limit: Int = 20, progress: (@Sendable (String) -> Void)? = nil) -> [LargeFile]` (sorted by size, descending; never follows symlinks; checks cancellation every 1,000 entries)
  - `LargeFileCleaner(environment:)` with `trash(_ files: [LargeFile]) -> CleanupRecord` (rule id `user.largeFile`, action `.trash`, refuses files `canTrashUserFile` rejects with `.protected`)
  - CLI `spare large [PATH] [--min-mb N] [--limit N] [--json]`

- [ ] **Step 1: Write the failing tests**

`Tests/SpareCoreTests/LargeFileFinderTests.swift`:

```swift
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
}
```

`Tests/SpareCLITests/LargeCommandTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct LargeCommandTests {
    @Test func largeJSONListsFiles() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Movies/a.mov", bytes: 2_000_000)
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: output.write)
            .run(["large", "--min-mb", "1", "--json"])

        #expect(code == 0)
        let files = try JSONDecoder().decode([LargeFile].self, from: Data(output.text.utf8))
        #expect(files.map(\.url.lastPathComponent) == ["a.mov"])
    }

    @Test func invalidMinimumIsRejected() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()

        #expect(await SpareCLI(environment: .test(home: home.url), write: output.write)
            .run(["large", "--min-mb", "lots"]) == 64)
    }
}
```

Note: `LargeFile` dates use default `JSONDecoder` here because `lastOpened` is nil-tolerant; the CLI encodes with `.iso8601`, so decode with `.iso8601` if `lastOpened` is present. Use a decoder with `dateDecodingStrategy = .iso8601` in the test to be safe.

Run: `swift test --filter LargeFile` → FAIL.

- [ ] **Step 2: Implement**

Add `case largeFiles` at the end of `CategoryID`.

`Sources/SpareCore/Scan/LargeFileFinder.swift`:

```swift
import Foundation

public struct LargeFile: Codable, Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let sizeBytes: Int64
    public let lastOpened: Date?

    public init(url: URL, sizeBytes: Int64, lastOpened: Date?) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastOpened = lastOpened
    }
}

public enum LargeFileFinder {
    public static func find(
        in root: URL, minBytes: Int64, limit: Int = 20,
        progress: (@Sendable (String) -> Void)? = nil
    ) -> [LargeFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .contentAccessDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return [] }

        var found: [LargeFile] = []
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 1_000 == 0 {
                if Task.isCancelled { break }
                progress?(url.path)
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true,
                  let size = values.totalFileAllocatedSize, Int64(size) >= minBytes
            else { continue }
            found.append(LargeFile(url: url, sizeBytes: Int64(size), lastOpened: values.contentAccessDate))
        }
        return Array(found.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }
}
```

`Sources/SpareCore/Clean/LargeFileCleaner.swift`:

```swift
import Foundation

public struct LargeFileCleaner: Sendable {
    public static let ruleID = "user.largeFile"
    public let environment: SpareEnvironment

    public init(environment: SpareEnvironment) {
        self.environment = environment
    }

    public func trash(_ files: [LargeFile]) -> CleanupRecord {
        let startedAt = environment.now()
        let before = environment.diskSpace(environment.home)?.freeBytes
        let guardian = SafetyGuard(home: environment.home, projectRoots: environment.projectRoots)
        let entries = files.map { file -> CleanupEntry in
            var entry = CleanupEntry(ruleID: Self.ruleID, category: .largeFiles, originalPath: file.url.path,
                                     action: .trash, sizeBytes: file.sizeBytes, status: .skipped)
            guard guardian.canTrashUserFile(file.url) else {
                entry.skipReason = .protected
                return entry
            }
            guard FileManager.default.fileExists(atPath: file.url.path) else {
                entry.skipReason = .notFound
                return entry
            }
            do {
                entry.trashPath = try environment.trash.moveToTrash(file.url).path
                entry.status = .done
            } catch {
                entry.status = .failed
                entry.detail = error.localizedDescription
            }
            return entry
        }
        return CleanupRecord(startedAt: startedAt, finishedAt: environment.now(), freeBytesBefore: before,
                             freeBytesAfter: environment.diskSpace(environment.home)?.freeBytes,
                             entries: entries, cancelled: false)
    }
}
```

CLI (`SpareCLI.run`: `case "large": return large(Array(args.dropFirst()), json: json)`; usage line `spare large [PATH] [--min-mb 500] [--limit 20] [--json]   Biggest files under PATH (default: home)`):

```swift
    func large(_ args: [String], json: Bool) -> Int32 {
        let minText = Self.option("--min-mb", in: args).last ?? "500"
        let limitText = Self.option("--limit", in: args).last ?? "20"
        guard let minMB = Int64(minText), minMB > 0, let limit = Int(limitText), limit > 0 else {
            write("--min-mb and --limit must be positive numbers")
            return 64
        }
        let valueFlags: Set<String> = ["--min-mb", "--limit"]
        var positional: [String] = []
        var index = 0
        while index < args.count {
            if valueFlags.contains(args[index]) { index += 2; continue }
            positional.append(args[index])
            index += 1
        }
        let root = positional.first.map { URL(fileURLWithPath: $0) } ?? environment.home
        let files = LargeFileFinder.find(in: root, minBytes: minMB * 1_000_000, limit: limit)
        if json {
            write(Self.encode(files))
        } else {
            if files.isEmpty { write("No files above \(minMB) MB.") }
            files.forEach { write("\(ByteFormat.string($0.sizeBytes))  \($0.url.path)") }
        }
        return 0
    }
```

- [ ] **Step 3: Run, docs, gates, commit**

`swift test` → PASS. Smoke: `swift run spare large --min-mb 1000`. README, CHANGELOG `Added: large files finder (spare large)`, STATUS. `scripts/check.sh` green.

```bash
git add -A
git commit -m "feat(core): add large file finder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
