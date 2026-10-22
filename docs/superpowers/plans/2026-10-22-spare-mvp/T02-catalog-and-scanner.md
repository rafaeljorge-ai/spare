# Task 2: Rule catalog, safety guard, size calculator and scanner

The engine learns what it may touch (the closed catalog), how to measure it without being fooled by symlinks or hard links, and produces a `ScanReport`. Nothing is deleted yet. `spare scan` exposes it.

**Files:**
- Create: `Sources/SpareCore/Rules/Rule.swift`, `Sources/SpareCore/Rules/RuleCatalog.swift`, `Sources/SpareCore/Rules/SafetyGuard.swift`
- Create: `Sources/SpareCore/Scan/SizeCalculator.swift`, `Sources/SpareCore/Scan/ScanReport.swift`, `Sources/SpareCore/Scan/Scanner.swift`
- Modify: `Sources/SpareCLI/SpareCLI.swift` (add `scan`)
- Test: `Tests/SpareCoreTests/SizeCalculatorTests.swift`, `Tests/SpareCoreTests/SafetyGuardTests.swift`, `Tests/SpareCoreTests/ScannerTests.swift`, `Tests/SpareCLITests/ScanCommandTests.swift`
- Modify: `README.md` (CLI usage), `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `SpareEnvironment` (`home`, `projectRoots`, `now`, `diskSpace`), `TempHome`, `OutputCapture`, `SpareEnvironment.test(home:)`, `SpareCLI.encode`.
- Produces:
  - `CategoryID` (`devCaches, projectLeftovers, aiTools, appCaches, logs, installers, trash`), `Safety` (`safe, review`), `CleanAction` (`delete, trash, command(executable:arguments:), emptyTrash`), `InUseHint`, `RuleKind` (`path, children, projectArtifact`), `Rule`, `RuleCatalog` (`standard`, `rule(id:)`, `rules`).
  - `SkipReason` (`inUse, notFound, outsideCatalog, protected, cancelled, toolNotFound`).
  - `SafetyGuard(home:projectRoots:)` with `violation(for: URL, rule: Rule) -> SkipReason?` and `canTrashUserFile(_: URL) -> Bool`.
  - `SizeCalculator.allocatedSize(of: URL) -> Int64`.
  - `ScanItem`, `ScanReport`, `ScanProgress`, `Scanner(environment:catalog:)` with `scan(categories:progress:) async -> ScanReport` and `candidates(for: Rule) -> [URL]`.

- [ ] **Step 1: Write the failing size calculator tests**

`Tests/SpareCoreTests/SizeCalculatorTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct SizeCalculatorTests {
    @Test func sumsFilesInsideADirectory() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("cache/a.bin", bytes: 10_000)
        try home.file("cache/sub/b.bin", bytes: 5_000)

        let size = SizeCalculator.allocatedSize(of: home.path("cache"))

        #expect(size >= 15_000)
        #expect(size < 15_000 + 3 * 4096)
    }

    @Test func measuresASingleFile() throws {
        let home = try TempHome()
        defer { home.remove() }
        let file = try home.file("big.dmg", bytes: 50_000)

        #expect(SizeCalculator.allocatedSize(of: file) >= 50_000)
    }

    @Test func countsHardLinkedFilesOnce() throws {
        let home = try TempHome()
        defer { home.remove() }
        let original = try home.file("store/blob", bytes: 200_000)
        try FileManager.default.createDirectory(at: home.path("store/linked"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: home.path("store/linked/blob"))

        let size = SizeCalculator.allocatedSize(of: home.path("store"))

        #expect(size >= 200_000)
        #expect(size < 400_000)
    }

    @Test func doesNotFollowSymlinkedDirectories() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("elsewhere/huge.bin", bytes: 1_000_000)
        try home.directory("cache")
        try FileManager.default.createSymbolicLink(
            at: home.path("cache/link"), withDestinationURL: home.path("elsewhere"))

        #expect(SizeCalculator.allocatedSize(of: home.path("cache")) < 100_000)
    }

    @Test func missingPathIsZero() {
        #expect(SizeCalculator.allocatedSize(of: URL(fileURLWithPath: "/nope/nothing")) == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SizeCalculatorTests`
Expected: FAIL, `SizeCalculator` not found.

- [ ] **Step 3: Implement `SizeCalculator`**

`Sources/SpareCore/Scan/SizeCalculator.swift`:

```swift
import Darwin
import Foundation

public enum SizeCalculator {
    /// Bytes allocated on disk. Never follows symlinks. Hard-linked files count once.
    /// Checks for task cancellation every 1,000 files.
    public static func allocatedSize(of url: URL) -> Int64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { return Int64(info.st_blocks) * 512 }

        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true })
        else { return 0 }

        var seenInodes = Set<UInt64>()
        var total: Int64 = 0
        var visited = 0
        while let child = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 1_000 == 0, Task.isCancelled { break }
            var childInfo = stat()
            guard lstat(child.path, &childInfo) == 0 else { continue }
            if (childInfo.st_mode & S_IFMT) == S_IFDIR { continue }
            if childInfo.st_nlink > 1, !seenInodes.insert(UInt64(childInfo.st_ino)).inserted { continue }
            total += Int64(childInfo.st_blocks) * 512
        }
        return total
    }
}
```

Run: `swift test --filter SizeCalculatorTests` → PASS.

- [ ] **Step 4: Rules and catalog**

`Sources/SpareCore/Rules/Rule.swift`:

```swift
import Foundation

public enum CategoryID: String, Codable, Sendable, CaseIterable, Hashable {
    case devCaches, projectLeftovers, aiTools, appCaches, logs, installers, trash
}

public enum Safety: String, Codable, Sendable, Hashable {
    case safe, review
}

public enum CleanAction: Codable, Sendable, Hashable {
    /// Regenerable data: removed for good, frees space immediately.
    case delete
    /// Content that does not regenerate: moved to the Trash, can be undone.
    case trash
    /// The tool's own official cleanup command (it knows its locks).
    case command(executable: String, arguments: [String])
    /// Empties ~/.Trash. The only irreversible removal of user content.
    case emptyTrash
}

public struct InUseHint: Codable, Sendable, Hashable {
    /// Process executable names (or the script name for node/python tools) that block cleanup.
    public var processNames: [String]
    /// Block if any process command line contains the item path (project items: the project path).
    public var checkCommandLines: Bool
    /// Block if a running app's bundle identifier equals the item folder name (~/Library/Caches/<bundle id>).
    public var checkOwningApp: Bool

    public init(processNames: [String] = [], checkCommandLines: Bool = false, checkOwningApp: Bool = false) {
        self.processNames = processNames
        self.checkCommandLines = checkCommandLines
        self.checkOwningApp = checkOwningApp
    }

    public static let none = InUseHint()
}

public enum RuleKind: Codable, Sendable, Hashable {
    /// One item at `home/<path>`.
    case path(String)
    /// Each direct child of `home/<parent>` is an item (hidden entries are ignored).
    case children(parent: String, excludingPrefixes: [String], extensions: [String]?, minAgeDays: Int?)
    /// A folder named `directoryName` inside a configured project root whose parent holds one of `manifests`.
    case projectArtifact(directoryName: String, manifests: [String])
}

public enum SkipReason: String, Codable, Sendable, Hashable {
    case inUse, notFound, outsideCatalog, protected, cancelled, toolNotFound
}

public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let category: CategoryID
    public let kind: RuleKind
    public let safety: Safety
    public let action: CleanAction
    public let inUse: InUseHint

    public init(
        id: String, category: CategoryID, kind: RuleKind, safety: Safety,
        action: CleanAction, inUse: InUseHint = .none
    ) {
        self.id = id
        self.category = category
        self.kind = kind
        self.safety = safety
        self.action = action
        self.inUse = inUse
    }
}
```

`Sources/SpareCore/Rules/RuleCatalog.swift`:

```swift
import Foundation

public struct RuleCatalog: Sendable {
    public let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public func rule(id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    /// The closed list of everything Spare is allowed to clean.
    public static let standard = RuleCatalog(rules: [
        // Developer caches
        Rule(id: "dev.npm", category: .devCaches, kind: .path(".npm/_cacache"), safety: .safe,
             action: .command(executable: "npm", arguments: ["cache", "clean", "--force"])),
        Rule(id: "dev.npx", category: .devCaches,
             kind: .children(parent: ".npm/_npx", excludingPrefixes: [], extensions: nil, minAgeDays: nil),
             safety: .review, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "dev.pnpm", category: .devCaches, kind: .path("Library/pnpm/store"), safety: .safe,
             action: .command(executable: "pnpm", arguments: ["store", "prune"])),
        Rule(id: "dev.yarn", category: .devCaches, kind: .path("Library/Caches/Yarn"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["yarn"])),
        Rule(id: "dev.uv", category: .devCaches, kind: .path(".cache/uv"), safety: .safe,
             action: .command(executable: "uv", arguments: ["cache", "clean"])),
        Rule(id: "dev.pip", category: .devCaches, kind: .path("Library/Caches/pip"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["pip", "pip3"])),
        Rule(id: "dev.cargo", category: .devCaches, kind: .path(".cargo/registry/cache"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["cargo"])),
        Rule(id: "dev.homebrew", category: .devCaches, kind: .path("Library/Caches/Homebrew"), safety: .safe,
             action: .command(executable: "brew", arguments: ["cleanup", "--prune=all"])),
        Rule(id: "dev.xcodeDerivedData", category: .devCaches,
             kind: .path("Library/Developer/Xcode/DerivedData"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["Xcode", "xcodebuild"])),
        Rule(id: "dev.preCommit", category: .devCaches, kind: .path(".cache/pre-commit"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["pre-commit"])),
        Rule(id: "dev.playwright", category: .devCaches, kind: .path("Library/Caches/ms-playwright"),
             safety: .review, action: .delete, inUse: InUseHint(checkCommandLines: true)),

        // AI tools
        Rule(id: "ai.huggingface", category: .aiTools, kind: .path(".cache/huggingface"), safety: .review,
             action: .trash, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "ai.whisper", category: .aiTools, kind: .path(".cache/whisper"), safety: .review,
             action: .trash, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "ai.ollama", category: .aiTools, kind: .path(".ollama/models"), safety: .review,
             action: .trash, inUse: InUseHint(processNames: ["ollama", "Ollama"])),
        Rule(id: "ai.lmstudio", category: .aiTools, kind: .path(".lmstudio/models"), safety: .review,
             action: .trash, inUse: InUseHint(processNames: ["LM Studio", "lms"])),
        Rule(id: "ai.codexRuntimes", category: .aiTools,
             kind: .children(parent: ".cache/codex-runtimes", excludingPrefixes: [], extensions: nil, minAgeDays: nil),
             safety: .review, action: .trash, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "ai.claudeVM", category: .aiTools,
             kind: .path("Library/Application Support/Claude/vm_bundles"), safety: .review,
             action: .trash, inUse: InUseHint(processNames: ["Claude"])),

        // Project leftovers (found by ProjectScanner in Task 3)
        Rule(id: "project.nodeModules", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: "node_modules", manifests: ["package.json"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "project.venv", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: ".venv",
                                    manifests: ["pyproject.toml", "requirements.txt", "setup.py"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "project.next", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: ".next", manifests: ["package.json"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "project.rustTarget", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: "target", manifests: ["Cargo.toml"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),

        // Common junk
        Rule(id: "apps.caches", category: .appCaches,
             kind: .children(parent: "Library/Caches", excludingPrefixes: ["com.apple."], extensions: nil, minAgeDays: nil),
             safety: .safe, action: .delete, inUse: InUseHint(checkOwningApp: true)),
        Rule(id: "apps.logs", category: .logs,
             kind: .children(parent: "Library/Logs", excludingPrefixes: [], extensions: nil, minAgeDays: nil),
             safety: .safe, action: .delete),
        Rule(id: "downloads.installers", category: .installers,
             kind: .children(parent: "Downloads", excludingPrefixes: [], extensions: ["dmg", "pkg", "iso", "xip"], minAgeDays: 30),
             safety: .safe, action: .trash),
        Rule(id: "system.trash", category: .trash, kind: .path(".Trash"), safety: .review, action: .emptyTrash),
    ])
}
```

- [ ] **Step 5: Write the failing safety guard tests**

`Tests/SpareCoreTests/SafetyGuardTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct SafetyGuardTests {
    let catalog = RuleCatalog.standard

    func rule(_ id: String) -> Rule { catalog.rule(id: id)! }

    @Test func allowsExactPathRule() throws {
        let home = try TempHome()
        defer { home.remove() }
        let item = try home.directory(".npm/_cacache")
        let guardian = SafetyGuard(home: home.url, projectRoots: [])

        #expect(guardian.violation(for: item, rule: rule("dev.npm")) == nil)
    }

    @Test func refusesPathThatDoesNotMatchTheRule() throws {
        let home = try TempHome()
        defer { home.remove() }
        let item = try home.directory(".npm/other")
        let guardian = SafetyGuard(home: home.url, projectRoots: [])

        #expect(guardian.violation(for: item, rule: rule("dev.npm")) == .outsideCatalog)
    }

    @Test func refusesProtectedFoldersEvenWithAValidRule() throws {
        let home = try TempHome()
        defer { home.remove() }
        let guardian = SafetyGuard(home: home.url, projectRoots: [])

        #expect(guardian.violation(for: try home.directory("Documents/work"), rule: rule("dev.npm")) == .protected)
        #expect(guardian.violation(for: try home.directory(".ssh"), rule: rule("dev.npm")) == .protected)
        #expect(guardian.violation(for: home.url, rule: rule("dev.npm")) == .protected)
        #expect(guardian.violation(for: URL(fileURLWithPath: "/System/Library"), rule: rule("dev.npm")) == .protected)
        #expect(guardian.violation(for: URL(fileURLWithPath: "/Applications/Safari.app"), rule: rule("dev.npm")) == .protected)
    }

    @Test func refusesItemsOutsideHome() throws {
        let home = try TempHome()
        defer { home.remove() }
        let other = try TempHome()
        defer { other.remove() }
        let guardian = SafetyGuard(home: home.url, projectRoots: [])

        #expect(guardian.violation(for: try other.directory(".npm/_cacache"), rule: rule("dev.npm")) == .outsideCatalog)
    }

    @Test func refusesSymlinkThatResolvesOutsideTheRule() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.directory("Documents/precious")
        try home.directory("Library/Caches")
        try FileManager.default.createSymbolicLink(
            at: home.path("Library/Caches/com.evil.app"), withDestinationURL: home.path("Documents/precious"))
        let guardian = SafetyGuard(home: home.url, projectRoots: [])

        let verdict = guardian.violation(for: home.path("Library/Caches/com.evil.app"), rule: rule("apps.caches"))
        #expect(verdict != nil)
    }

    @Test func childrenRuleAllowsDirectChildrenOnlyAndHonorsExclusions() throws {
        let home = try TempHome()
        defer { home.remove() }
        let guardian = SafetyGuard(home: home.url, projectRoots: [])
        let caches = rule("apps.caches")

        #expect(guardian.violation(for: try home.directory("Library/Caches/com.example.app"), rule: caches) == nil)
        #expect(guardian.violation(for: try home.directory("Library/Caches/com.example.app/deep"), rule: caches) == .outsideCatalog)
        #expect(guardian.violation(for: try home.directory("Library/Caches/com.apple.Safari"), rule: caches) == .outsideCatalog)
        #expect(guardian.violation(for: try home.directory("Library/Caches"), rule: caches) == .outsideCatalog)
    }

    @Test func projectArtifactMustLiveInAProjectRoot() throws {
        let home = try TempHome()
        defer { home.remove() }
        let root = try home.directory("Projetos")
        let guardian = SafetyGuard(home: home.url, projectRoots: [root])
        let nodeModules = rule("project.nodeModules")

        #expect(guardian.violation(for: try home.directory("Projetos/app/node_modules"), rule: nodeModules) == nil)
        #expect(guardian.violation(for: try home.directory("Other/app/node_modules"), rule: nodeModules) == .outsideCatalog)
        #expect(guardian.violation(for: try home.directory("Projetos/app/src"), rule: nodeModules) == .outsideCatalog)
    }

    @Test func userFilesCanBeTrashedExceptCriticalOnes() throws {
        let home = try TempHome()
        defer { home.remove() }
        let guardian = SafetyGuard(home: home.url, projectRoots: [])

        #expect(guardian.canTrashUserFile(try home.file("Movies/big.mov")))
        #expect(guardian.canTrashUserFile(try home.file("Documents/old.zip")))
        #expect(!guardian.canTrashUserFile(try home.file(".ssh/id_ed25519")))
        #expect(!guardian.canTrashUserFile(try home.file("Library/Keychains/login.keychain-db")))
        #expect(!guardian.canTrashUserFile(home.url))
        #expect(!guardian.canTrashUserFile(URL(fileURLWithPath: "/Applications/Safari.app")))
    }
}
```

Run: `swift test --filter SafetyGuardTests` → FAIL (`SafetyGuard` missing).

- [ ] **Step 6: Implement `SafetyGuard`**

`Sources/SpareCore/Rules/SafetyGuard.swift`:

```swift
import Foundation

/// Last line of defense: decides if a path may be touched by a rule.
public struct SafetyGuard: Sendable {
    public let home: URL
    public let projectRoots: [URL]

    static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/Applications", "/Library", "/opt", "/cores"]
    static let protectedInHome = [
        ".ssh", ".gnupg", ".aws", ".kube", "Documents", "Desktop", "Pictures", "Movies", "Music",
        "Library", "Library/Keychains", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
    ]
    static let criticalInHome = [".ssh", ".gnupg", ".aws", ".kube", "Library/Keychains"]

    public init(home: URL, projectRoots: [URL]) {
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
        self.projectRoots = projectRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    public func violation(for url: URL, rule: Rule) -> SkipReason? {
        let path = Self.resolved(url)
        if Self.isSystemPath(path) { return .protected }
        let homePath = home.path
        if path == homePath { return .protected }
        guard path.hasPrefix(homePath + "/") else { return .outsideCatalog }
        let relative = String(path.dropFirst(homePath.count + 1))
        // Protected folders themselves are never items; their subfolders only via explicit rules below.
        if Self.protectedInHome.contains(relative) { return .protected }
        if Self.isInside(relative, any: ["Documents", "Desktop", "Pictures", "Movies", "Music"] + Self.criticalInHome) {
            return .protected
        }

        switch rule.kind {
        case .path(let rulePath):
            return relative == rulePath ? nil : .outsideCatalog
        case .children(let parent, let excluded, _, _):
            let name = (relative as NSString).lastPathComponent
            let itemParent = (relative as NSString).deletingLastPathComponent
            guard itemParent == parent, !name.hasPrefix(".") else { return .outsideCatalog }
            return excluded.contains(where: { name.hasPrefix($0) }) ? .outsideCatalog : nil
        case .projectArtifact(let directoryName, _):
            guard (path as NSString).lastPathComponent == directoryName else { return .outsideCatalog }
            let insideRoot = projectRoots.contains { path.hasPrefix($0.path + "/") }
            return insideRoot ? nil : .outsideCatalog
        }
    }

    /// For files the user picked explicitly (Large Files screen).
    public func canTrashUserFile(_ url: URL) -> Bool {
        let path = Self.resolved(url)
        guard !Self.isSystemPath(path), path.hasPrefix(home.path + "/") else { return false }
        let relative = String(path.dropFirst(home.path.count + 1))
        return !Self.isInside(relative, any: Self.criticalInHome) && !Self.criticalInHome.contains(relative)
    }

    static func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func isSystemPath(_ path: String) -> Bool {
        systemPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func isInside(_ relative: String, any folders: [String]) -> Bool {
        folders.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }
}
```

Note on the symlink test: `com.evil.app` resolves to `Documents/precious`, which is inside `Documents`, so it returns `.protected` (non-nil, as the test requires).

Run: `swift test --filter SafetyGuardTests` → PASS.

- [ ] **Step 7: Write the failing scanner tests**

`Tests/SpareCoreTests/ScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct ScannerTests {
    func makeJunk(_ home: TempHome) throws {
        try home.file(".npm/_cacache/index/a", bytes: 50_000)
        try home.file("Library/Caches/com.example.app/data", bytes: 30_000)
        try home.file("Library/Caches/com.apple.Safari/data", bytes: 30_000)
        try home.file("Library/Caches/Homebrew/bottle.tar.gz", bytes: 20_000)
        try home.file("Downloads/old.dmg", bytes: 10_000, modified: daysAgo(60))
        try home.file("Downloads/new.dmg", bytes: 10_000)
        try home.file("Downloads/photo.jpg", bytes: 10_000, modified: daysAgo(60))
        try home.file("Library/Logs/app.log", bytes: 8_000)
    }

    @Test func findsCatalogItemsAndNothingElse() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let scanner = Scanner(environment: .test(home: home.url))

        let report = await scanner.scan()
        let byRule = Dictionary(grouping: report.items, by: \.ruleID)

        #expect(byRule["dev.npm"]?.count == 1)
        #expect(byRule["dev.homebrew"]?.count == 1)
        #expect(byRule["apps.caches"]?.map(\.url.lastPathComponent) == ["com.example.app"])
        #expect(byRule["downloads.installers"]?.map(\.url.lastPathComponent) == ["old.dmg"])
        #expect(byRule["apps.logs"]?.count == 1)
        #expect(report.cancelled == false)
        #expect(report.freeBytesBefore == 10_000_000_000)
    }

    @Test func specificRulesWinOverTheGenericCachesRule() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)

        let report = await Scanner(environment: .test(home: home.url)).scan()

        let cacheChildren = report.items.filter { $0.ruleID == "apps.caches" }.map(\.url.lastPathComponent)
        #expect(!cacheChildren.contains("Homebrew"))
    }

    @Test func totalsAndSafetyBuckets() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        try home.file(".cache/huggingface/hub/model.bin", bytes: 40_000)

        let report = await Scanner(environment: .test(home: home.url)).scan()

        #expect(report.totalBytes(in: .devCaches) >= 70_000)
        #expect(report.reviewBytes >= 40_000)
        #expect(report.safeReclaimableBytes >= 70_000 + 30_000 + 10_000 + 8_000)
    }

    @Test func emptyFoldersAreNotReported() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.directory(".npm/_cacache")

        let report = await Scanner(environment: .test(home: home.url)).scan()

        #expect(report.items.isEmpty)
    }

    @Test func categoryFilterLimitsTheScan() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)

        let report = await Scanner(environment: .test(home: home.url)).scan(categories: [.logs])

        #expect(Set(report.items.map(\.category)) == [.logs])
    }

    @Test func reportsProgressForEveryItem() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let seen = OutputCapture()

        let report = await Scanner(environment: .test(home: home.url)).scan { progress in
            seen.write(progress.currentPath)
        }

        #expect(seen.text.split(separator: "\n").count == report.items.count)
    }

    @Test func cancellationReturnsAPartialReport() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        var environment = SpareEnvironment.test(home: home.url)
        environment.diskSpace = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return nil
        }
        let scanner = Scanner(environment: environment)

        let task = Task { await scanner.scan() }
        task.cancel()
        let report = await task.value

        #expect(report.cancelled)
    }

    @Test func reportRoundTripsThroughJSON() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let report = await Scanner(environment: .test(home: home.url)).scan()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanReport.self, from: encoder.encode(report))

        #expect(decoded.items.count == report.items.count)
        #expect(decoded.safeReclaimableBytes == report.safeReclaimableBytes)
    }
}
```

Run: `swift test --filter ScannerTests` → FAIL.

- [ ] **Step 8: Implement report types**

`Sources/SpareCore/Scan/ScanReport.swift`:

```swift
import Foundation

public struct ScanItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let ruleID: String
    public let category: CategoryID
    public let url: URL
    public let sizeBytes: Int64
    public let safety: Safety
    /// Name of the process or app using it; nil when free to clean.
    public var inUseBy: String?
    public let lastModified: Date?

    public init(
        ruleID: String, category: CategoryID, url: URL, sizeBytes: Int64,
        safety: Safety, inUseBy: String? = nil, lastModified: Date? = nil
    ) {
        self.ruleID = ruleID
        self.category = category
        self.url = url
        self.sizeBytes = sizeBytes
        self.safety = safety
        self.inUseBy = inUseBy
        self.lastModified = lastModified
    }
}

public struct ScanReport: Codable, Sendable {
    public var items: [ScanItem]
    public var startedAt: Date
    public var finishedAt: Date
    public var freeBytesBefore: Int64?
    public var cancelled: Bool

    public init(items: [ScanItem], startedAt: Date, finishedAt: Date, freeBytesBefore: Int64?, cancelled: Bool) {
        self.items = items
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.freeBytesBefore = freeBytesBefore
        self.cancelled = cancelled
    }

    public func items(in category: CategoryID) -> [ScanItem] {
        items.filter { $0.category == category }
    }

    public func totalBytes(in category: CategoryID) -> Int64 {
        items(in: category).reduce(0) { $0 + $1.sizeBytes }
    }

    /// Safe and not in use: what "Clean what's safe" will free.
    public var safeReclaimableBytes: Int64 {
        items.filter { $0.safety == .safe && $0.inUseBy == nil }.reduce(0) { $0 + $1.sizeBytes }
    }

    public var reviewBytes: Int64 {
        items.filter { $0.safety == .review && $0.inUseBy == nil }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Copy without the given item paths (after they were cleaned).
    public func removing(paths: Set<String>) -> ScanReport {
        var copy = self
        copy.items.removeAll { paths.contains($0.url.path) }
        return copy
    }
}

public struct ScanProgress: Sendable {
    public let currentPath: String
    public let completed: Int
    public let total: Int
    public let item: ScanItem?
    /// Set when the last pending item of a category finished.
    public let finishedCategory: CategoryID?
}
```

- [ ] **Step 9: Implement the scanner**

`Sources/SpareCore/Scan/Scanner.swift`:

```swift
import Foundation

public struct Scanner: Sendable {
    public let environment: SpareEnvironment
    public let catalog: RuleCatalog
    static let maxConcurrentMeasurements = 4

    public init(environment: SpareEnvironment, catalog: RuleCatalog = .standard) {
        self.environment = environment
        self.catalog = catalog
    }

    public func scan(
        categories: Set<CategoryID>? = nil,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async -> ScanReport {
        let startedAt = environment.now()
        let freeBefore = environment.diskSpace(environment.home)?.freeBytes
        let rules = catalog.rules.filter { categories?.contains($0.category) ?? true }

        var candidates: [(Rule, URL)] = []
        for rule in rules where !Task.isCancelled {
            candidates += self.candidates(for: rule).map { (rule, $0) }
        }

        var pendingPerCategory = Dictionary(grouping: candidates, by: { $0.0.category }).mapValues(\.count)
        var items: [ScanItem] = []
        var completed = 0
        let total = candidates.count

        await withTaskGroup(of: (CategoryID, String, ScanItem?).self) { group in
            var iterator = candidates.makeIterator()
            func addNext() {
                guard let (rule, url) = iterator.next() else { return }
                group.addTask { (rule.category, url.path, Self.measure(rule: rule, url: url)) }
            }
            for _ in 0..<Self.maxConcurrentMeasurements { addNext() }
            while let (category, path, item) = await group.next() {
                completed += 1
                if let item { items.append(item) }
                pendingPerCategory[category, default: 1] -= 1
                let finished = pendingPerCategory[category] == 0 ? category : nil
                if item != nil || finished != nil {
                    progress(ScanProgress(currentPath: path, completed: completed, total: total,
                                          item: item, finishedCategory: finished))
                }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                addNext()
            }
        }

        items.sort { $0.sizeBytes > $1.sizeBytes }
        return ScanReport(items: items, startedAt: startedAt, finishedAt: environment.now(),
                          freeBytesBefore: freeBefore, cancelled: Task.isCancelled)
    }

    static func measure(rule: Rule, url: URL) -> ScanItem? {
        let size = SizeCalculator.allocatedSize(of: url)
        guard size > 0 else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ScanItem(ruleID: rule.id, category: rule.category, url: url, sizeBytes: size,
                        safety: rule.safety, lastModified: modified)
    }

    /// Paths a rule points at right now. Project artifacts are added in Task 3.
    public func candidates(for rule: Rule) -> [URL] {
        let fm = FileManager.default
        switch rule.kind {
        case .path(let relative):
            let url = environment.home.appendingPathComponent(relative)
            return fm.fileExists(atPath: url.path) ? [url] : []
        case .children(let parent, let excluded, let extensions, let minAgeDays):
            let dir = environment.home.appendingPathComponent(parent)
            let claimed = claimedPaths()
            guard let children = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
            else { return [] }
            let cutoff = minAgeDays.map { environment.now().addingTimeInterval(-Double($0) * 86_400) }
            return children.filter { child in
                let name = child.lastPathComponent
                if name.hasPrefix(".") { return false }
                if excluded.contains(where: { name.hasPrefix($0) }) { return false }
                if claimed.contains(where: { $0 == child.path || $0.hasPrefix(child.path + "/") }) { return false }
                if let extensions, !extensions.contains(child.pathExtension.lowercased()) { return false }
                if let cutoff {
                    let date = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    guard let date, date < cutoff else { return false }
                }
                return true
            }
        case .projectArtifact:
            return []
        }
    }

    /// Paths owned by specific `.path` rules, so generic `.children` rules skip them.
    func claimedPaths() -> [String] {
        catalog.rules.compactMap { rule in
            if case .path(let relative) = rule.kind {
                return environment.home.appendingPathComponent(relative).path
            }
            return nil
        }
    }
}
```

Run: `swift test --filter ScannerTests` → PASS.

- [ ] **Step 10: CLI `scan`**

Test first, `Tests/SpareCLITests/ScanCommandTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct ScanCommandTests {
    @Test func scanJSONIsAScanReport() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".npm/_cacache/index/a", bytes: 50_000)
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: output.write).run(["scan", "--json"])

        #expect(code == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ScanReport.self, from: Data(output.text.utf8))
        #expect(report.items.map(\.ruleID) == ["dev.npm"])
    }

    @Test func scanTextListsCategoriesAndTotals() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".npm/_cacache/index/a", bytes: 50_000)
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: output.write).run(["scan"])

        #expect(code == 0)
        #expect(output.text.contains("devCaches"))
        #expect(output.text.contains("Safe to free:"))
    }

    @Test func scanRejectsUnknownCategory() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: output.write)
            .run(["scan", "--category", "nope"])

        #expect(code == 64)
    }
}
```

Implementation in `SpareCLI.swift`: add `case "scan": return await scan(Array(args.dropFirst()), json: json)` and a helper `option(_ name: String, in: [String]) -> [String]` returning every value after each occurrence of `name`. Add to the usage text: `spare scan [--json] [--category ID]   Preview what can be freed (changes nothing)`.

```swift
    func scan(_ args: [String], json: Bool) async -> Int32 {
        var categories: Set<CategoryID>?
        let names = Self.option("--category", in: args)
        if !names.isEmpty {
            let parsed = names.compactMap(CategoryID.init(rawValue:))
            guard parsed.count == names.count else {
                write("Unknown category. Valid: \(CategoryID.allCases.map(\.rawValue).joined(separator: ", "))")
                return 64
            }
            categories = Set(parsed)
        }
        let report = await Scanner(environment: environment).scan(categories: categories)
        if json {
            write(Self.encode(report))
            return 0
        }
        for category in CategoryID.allCases {
            let items = report.items(in: category)
            guard !items.isEmpty else { continue }
            write("\(category.rawValue): \(ByteFormat.string(report.totalBytes(in: category))) in \(items.count) item(s)")
            for item in items {
                let flag = item.inUseBy.map { " [in use: \($0)]" } ?? ""
                write("  \(item.safety.rawValue)  \(ByteFormat.string(item.sizeBytes))  \(item.url.path)\(flag)")
            }
        }
        write("Safe to free: \(ByteFormat.string(report.safeReclaimableBytes))")
        write("To review: \(ByteFormat.string(report.reviewBytes))")
        return 0
    }

    static func option(_ name: String, in args: [String]) -> [String] {
        var values: [String] = []
        var index = 0
        while index < args.count {
            if args[index] == name, index + 1 < args.count {
                values.append(args[index + 1])
                index += 2
            } else {
                index += 1
            }
        }
        return values
    }
```

Run: `swift test` → all PASS. Then manual smoke (read-only): `swift run spare scan` on the real home lists real categories.

- [ ] **Step 11: Docs, gates, commit**

Update README CLI block with `spare scan`, CHANGELOG `Added: rule catalog, safety guard and read-only scan (spare scan)`, STATUS (Task 2 done). Run `scripts/check.sh` → green.

```bash
git add -A
git commit -m "feat(core): add rule catalog and read-only scanner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
