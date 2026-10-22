# Task 5: The cleaner

Executes a cleanup over selected `ScanItem`s with every guard re-checked at clean time: catalog containment, protected folders, existence, in-use, cancellation. Four actions: `delete` (regenerable data, frees space now), `trash` (undoable), `command` (official tool cleanup, run once per rule) and `emptyTrash`. Returns a `CleanupRecord`. Persistence and undo come in Task 6.

**Files:**
- Create: `Sources/SpareCore/Clean/TrashService.swift`, `Sources/SpareCore/Clean/CommandRunner.swift`, `Sources/SpareCore/Clean/CleanupRecord.swift`, `Sources/SpareCore/Clean/Cleaner.swift`
- Create: `Sources/SpareTestSupport/Fakes.swift`
- Modify: `Sources/SpareCore/Support/SpareEnvironment.swift` (add `trash`, `commandRunner`), `Sources/SpareTestSupport/TestEnvironment.swift`
- Test: `Tests/SpareCoreTests/CleanerTests.swift`, `Tests/SpareCoreTests/CommandRunnerTests.swift`
- Modify: `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `ScanItem`, `RuleCatalog`, `Rule`, `CleanAction`, `SkipReason`, `SafetyGuard`, `InUseGuard`, `SpareEnvironment` (`home`, `projectRoots`, `now`, `diskSpace`, `processes`).
- Produces:
  - `protocol TrashService: Sendable { func moveToTrash(_ url: URL) throws -> URL; func restore(_ trashed: URL, to original: URL) throws }`, `SystemTrash`.
  - `struct CommandResult: Sendable { exitCode: Int32; output: String }`, `protocol CommandRunning: Sendable { func run(_ executable: String, _ arguments: [String]) throws -> CommandResult }`, `enum CommandError: Error { case notFound(String) }`, `SystemCommandRunner(home: URL, searchPaths: [String]? = nil)`.
  - `enum ActionKind: String, Codable, Sendable { delete, trash, command, emptyTrash }` with `init(_ action: CleanAction)`.
  - `enum EntryStatus: String, Codable, Sendable { done, skipped, failed, restored, purged }`.
  - `struct CleanupEntry: Codable, Sendable, Identifiable, Hashable { ruleID; category; originalPath; trashPath: String?; action: ActionKind; sizeBytes; status; skipReason: SkipReason?; detail: String? }`.
  - `struct CleanupRecord: Codable, Sendable, Identifiable { id: UUID; startedAt; finishedAt; freeBytesBefore: Int64?; freeBytesAfter: Int64?; entries; cancelled; cleanedBytes; trashedBytes; undoableEntries }`.
  - `struct CleanProgress: Sendable { index: Int; total: Int; entry: CleanupEntry }`.
  - `Cleaner(environment:catalog:)` with `clean(_ items: [ScanItem], progress:) async -> CleanupRecord`.
  - `SpareEnvironment.trash: any TrashService` (default `SystemTrash()`), `SpareEnvironment.commandRunner: any CommandRunning` (default `SystemCommandRunner(home:)`).
  - Test support: `FolderTrash(folder:)`, `RecordingCommandRunner`, and `SpareEnvironment.test(...)` now injects both (trash folder `<home>/../<home name>-trash`).

- [ ] **Step 1: Fakes for tests**

`Sources/SpareTestSupport/Fakes.swift`:

```swift
import Foundation
import SpareCore

/// Trash that moves items into a plain folder (never the user's real Trash).
public struct FolderTrash: TrashService {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public func moveToTrash(_ url: URL) throws -> URL {
        let destination = folder.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    public func restore(_ trashed: URL, to original: URL) throws {
        try SystemTrash().restore(trashed, to: original)
    }
}

/// Records commands instead of running them.
public final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    public var missing: Set<String>
    public var exitCode: Int32

    public init(missing: Set<String> = [], exitCode: Int32 = 0) {
        self.missing = missing
        self.exitCode = exitCode
    }

    public var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        if missing.contains(executable) { throw CommandError.notFound(executable) }
        lock.lock()
        recorded.append(([executable] + arguments).joined(separator: " "))
        lock.unlock()
        return CommandResult(exitCode: exitCode, output: exitCode == 0 ? "ok" : "boom")
    }
}
```

`SpareEnvironment.test(...)` becomes:

```swift
    public static func test(
        home: URL,
        projectRoots: [URL] = [],
        disk: DiskSpace? = DiskSpace(freeBytes: 10_000_000_000, totalBytes: 100_000_000_000),
        processes: [RunningProcess] = [],
        commandRunner: any CommandRunning = RecordingCommandRunner()
    ) -> SpareEnvironment {
        let trashFolder = home.deletingLastPathComponent()
            .appendingPathComponent(home.lastPathComponent + "-trash", isDirectory: true)
        return SpareEnvironment(
            home: home,
            projectRoots: projectRoots,
            diskSpace: { _ in disk },
            processes: { processes },
            trash: FolderTrash(folder: trashFolder),
            commandRunner: commandRunner
        )
    }
```

`TempHome.remove()` must also remove the sibling `-trash` folder:

```swift
    public var trashFolder: URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-trash", isDirectory: true)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: trashFolder)
    }
```

- [ ] **Step 2: Write the failing cleaner tests**

`Tests/SpareCoreTests/CleanerTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct CleanerTests {
    let catalog = RuleCatalog.standard

    func item(_ ruleID: String, _ url: URL, size: Int64 = 1_000) -> ScanItem {
        let rule = catalog.rule(id: ruleID)!
        return ScanItem(ruleID: ruleID, category: rule.category, url: url, sizeBytes: size, safety: rule.safety)
    }

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
        let claude = RunningProcess(pid: 1, uid: 501, rssBytes: 1, executablePath: "/Applications/Claude.app/Contents/MacOS/Claude",
                                    commandLine: "/Applications/Claude.app/Contents/MacOS/Claude",
                                    appBundlePath: "/Applications/Claude.app", appBundleID: "com.anthropic.claudefordesktop", name: "Claude")

        let record = await Cleaner(environment: .test(home: home.url, processes: [claude])).clean([item("ai.claudeVM", vm)])

        #expect(record.entries.first?.skipReason == .inUse)
        #expect(record.entries.first?.detail == "Claude")
        #expect(home.exists("Library/Application Support/Claude/vm_bundles/disk.img"))
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
```

Run: `swift test --filter CleanerTests` → FAIL.

- [ ] **Step 3: Implement trash and command runner**

`Sources/SpareCore/Clean/TrashService.swift`:

```swift
import Foundation

public protocol TrashService: Sendable {
    /// Moves to the Trash; returns where the item ended up.
    func moveToTrash(_ url: URL) throws -> URL
    /// Moves an item back. Throws if something already exists at `original`.
    func restore(_ trashed: URL, to original: URL) throws
}

public struct SystemTrash: TrashService {
    public init() {}

    public func moveToTrash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let result = resulting as URL? else { throw CocoaError(.fileWriteUnknown) }
        return result
    }

    public func restore(_ trashed: URL, to original: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: original.path) else { throw CocoaError(.fileWriteFileExists) }
        guard fm.fileExists(atPath: trashed.path) else { throw CocoaError(.fileNoSuchFile) }
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: trashed, to: original)
    }
}
```

`Sources/SpareCore/Clean/CommandRunner.swift`:

```swift
import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public enum CommandError: Error, Equatable {
    case notFound(String)
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult
}

/// Runs developer tools even from a GUI app, whose PATH is minimal.
public struct SystemCommandRunner: CommandRunning {
    public let searchPaths: [String]

    public init(home: URL, searchPaths: [String]? = nil) {
        self.searchPaths = searchPaths ?? [
            "/opt/homebrew/bin", "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            "/usr/bin", "/bin",
        ]
    }

    public func resolve(_ executable: String) -> String? {
        let fm = FileManager.default
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(executable)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return loginShellLookup(executable)
    }

    /// Falls back to the user's login shell PATH (nvm, asdf, mise...).
    func loginShellLookup(_ executable: String) -> String? {
        guard executable.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(executable)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        guard let path = resolve(executable) else { throw CommandError.notFound(executable) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var variables = ProcessInfo.processInfo.environment
        let toolDir = (path as NSString).deletingLastPathComponent
        variables["PATH"] = ([toolDir] + searchPaths).joined(separator: ":")
        process.environment = variables
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
```

`Tests/SpareCoreTests/CommandRunnerTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct CommandRunnerTests {
    @Test func findsToolsInExtraSearchPathsAndPassesPATH() throws {
        let home = try TempHome()
        defer { home.remove() }
        let tool = try home.file("bin/fake-tool", bytes: 0)
        try "#!/bin/sh\necho \"args:$1 path-has-bin:$(echo $PATH | grep -c \(home.path("bin").path))\"\n"
            .write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let runner = SystemCommandRunner(home: home.url, searchPaths: [home.path("bin").path, "/usr/bin", "/bin"])

        let result = try runner.run("fake-tool", ["hello"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("args:hello"))
        #expect(result.output.contains("path-has-bin:1"))
    }

    @Test func missingToolThrowsNotFound() throws {
        let home = try TempHome()
        defer { home.remove() }
        let runner = SystemCommandRunner(home: home.url, searchPaths: [home.path("bin").path])

        #expect(throws: CommandError.notFound("surely-not-a-real-tool-xyz")) {
            try runner.run("surely-not-a-real-tool-xyz", [])
        }
    }
}
```

- [ ] **Step 4: Implement the record types and the cleaner**

`Sources/SpareCore/Clean/CleanupRecord.swift`:

```swift
import Foundation

public enum ActionKind: String, Codable, Sendable, Hashable {
    case delete, trash, command, emptyTrash

    public init(_ action: CleanAction) {
        switch action {
        case .delete: self = .delete
        case .trash: self = .trash
        case .command: self = .command
        case .emptyTrash: self = .emptyTrash
        }
    }
}

public enum EntryStatus: String, Codable, Sendable, Hashable {
    case done, skipped, failed, restored, purged
}

public struct CleanupEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: String { originalPath }
    public let ruleID: String
    public let category: CategoryID
    public let originalPath: String
    public var trashPath: String?
    public var action: ActionKind
    public let sizeBytes: Int64
    public var status: EntryStatus
    public var skipReason: SkipReason?
    /// Process name when in use, or an error message when failed.
    public var detail: String?

    public init(ruleID: String, category: CategoryID, originalPath: String, trashPath: String? = nil,
                action: ActionKind, sizeBytes: Int64, status: EntryStatus,
                skipReason: SkipReason? = nil, detail: String? = nil) {
        self.ruleID = ruleID
        self.category = category
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.action = action
        self.sizeBytes = sizeBytes
        self.status = status
        self.skipReason = skipReason
        self.detail = detail
    }
}

public struct CleanupRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public var finishedAt: Date
    public let freeBytesBefore: Int64?
    public var freeBytesAfter: Int64?
    public var entries: [CleanupEntry]
    public var cancelled: Bool

    public init(id: UUID = UUID(), startedAt: Date, finishedAt: Date, freeBytesBefore: Int64?,
                freeBytesAfter: Int64?, entries: [CleanupEntry], cancelled: Bool) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.freeBytesBefore = freeBytesBefore
        self.freeBytesAfter = freeBytesAfter
        self.entries = entries
        self.cancelled = cancelled
    }

    public var cleanedBytes: Int64 {
        entries.filter { $0.status == .done }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Bytes sitting in the Trash: only freed after the Trash is emptied (or purged).
    public var trashedBytes: Int64 {
        undoableEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    public var undoableEntries: [CleanupEntry] {
        entries.filter { $0.status == .done && $0.action == .trash && $0.trashPath != nil }
    }
}

public struct CleanProgress: Sendable {
    public let index: Int
    public let total: Int
    public let entry: CleanupEntry
}
```

`Sources/SpareCore/Clean/Cleaner.swift`:

```swift
import Foundation

public struct Cleaner: Sendable {
    public let environment: SpareEnvironment
    public let catalog: RuleCatalog

    public init(environment: SpareEnvironment, catalog: RuleCatalog = .standard) {
        self.environment = environment
        self.catalog = catalog
    }

    public func clean(
        _ items: [ScanItem],
        progress: @escaping @Sendable (CleanProgress) -> Void = { _ in }
    ) async -> CleanupRecord {
        let startedAt = environment.now()
        let freeBefore = environment.diskSpace(environment.home)?.freeBytes
        let guardian = SafetyGuard(home: environment.home, projectRoots: environment.projectRoots)
        let inUse = InUseGuard(processes: environment.processes())
        var completedCommands: [String: CleanupEntry] = [:]
        var entries: [CleanupEntry] = []

        for (index, item) in items.enumerated() {
            var entry = CleanupEntry(ruleID: item.ruleID, category: item.category, originalPath: item.url.path,
                                     action: .delete, sizeBytes: item.sizeBytes, status: .skipped)
            if let rule = catalog.rule(id: item.ruleID) {
                entry.action = ActionKind(rule.action)
                if Task.isCancelled {
                    entry.skipReason = .cancelled
                } else if let violation = guardian.violation(for: item.url, rule: rule) {
                    entry.skipReason = violation
                } else if !Self.exists(item.url) {
                    entry.skipReason = .notFound
                } else if let user = inUse.reason(rule: rule, url: item.url) {
                    entry.skipReason = .inUse
                    entry.detail = user
                } else if case .command = rule.action, let previous = completedCommands[rule.id] {
                    entry.status = previous.status
                    entry.skipReason = previous.skipReason
                    entry.detail = previous.detail
                } else {
                    perform(rule.action, on: item.url, entry: &entry)
                    if case .command = rule.action { completedCommands[rule.id] = entry }
                }
            } else {
                entry.skipReason = .outsideCatalog
            }
            entries.append(entry)
            progress(CleanProgress(index: index, total: items.count, entry: entry))
        }

        return CleanupRecord(
            startedAt: startedAt, finishedAt: environment.now(), freeBytesBefore: freeBefore,
            freeBytesAfter: environment.diskSpace(environment.home)?.freeBytes,
            entries: entries, cancelled: Task.isCancelled)
    }

    func perform(_ action: CleanAction, on url: URL, entry: inout CleanupEntry) {
        do {
            switch action {
            case .delete:
                try FileManager.default.removeItem(at: url)
            case .trash:
                entry.trashPath = try environment.trash.moveToTrash(url).path
            case .command(let executable, let arguments):
                let result = try environment.commandRunner.run(executable, arguments)
                guard result.exitCode == 0 else {
                    entry.status = .failed
                    entry.detail = String(result.output.suffix(300))
                    return
                }
            case .emptyTrash:
                let fm = FileManager.default
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) {
                    try fm.removeItem(at: child)
                }
            }
            entry.status = .done
        } catch CommandError.notFound {
            entry.status = .skipped
            entry.skipReason = .toolNotFound
        } catch {
            entry.status = .failed
            entry.detail = error.localizedDescription
        }
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
```

`SpareEnvironment`: add `public var trash: any TrashService` and `public var commandRunner: any CommandRunning`, init parameters `trash: any TrashService = SystemTrash()` and `commandRunner: (any CommandRunning)? = nil` (resolved to `SystemCommandRunner(home: home)` inside `init` when nil).

- [ ] **Step 5: Run the tests**

Run: `swift test` → all PASS.

- [ ] **Step 6: Docs, gates, commit**

CHANGELOG `Added: cleaner with delete, trash, official tool command and empty Trash, guarded at clean time`; STATUS. `scripts/check.sh` green.

```bash
git add -A
git commit -m "feat(core): add guarded cleaner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```

> **Note (from the T03 review):** before every `delete` of a project artifact, the Cleaner must re-check `ProjectScanner.isIdle` for the project (measured at the repository root when there is one). If the project was used again between the scan and the cleanup, skip the item and report the reason.
