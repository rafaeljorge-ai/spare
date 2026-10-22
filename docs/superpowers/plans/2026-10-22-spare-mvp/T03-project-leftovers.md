# Task 3: Idle project leftovers

Finds `node_modules`, `.venv`, `.next` and Rust `target` folders inside the configured project roots, only for projects untouched for N days, and feeds them into the scanner. This is where most of the space is on a vibecoder's Mac (14 GB in 111 folders on the author's machine).

**Files:**
- Create: `Sources/SpareCore/Scan/ProjectScanner.swift`
- Modify: `Sources/SpareCore/Scan/Scanner.swift` (`candidates` for `.projectArtifact`), `Sources/SpareCore/Support/SpareEnvironment.swift` (`live(home:)` uses default roots)
- Test: `Tests/SpareCoreTests/ProjectScannerTests.swift`, add cases to `Tests/SpareCoreTests/ScannerTests.swift`
- Modify: `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `Rule`, `RuleKind.projectArtifact(directoryName:manifests:)`, `RuleCatalog.standard`, `Scanner.candidates(for:)`, `SpareEnvironment.projectRoots`, `projectIdleDays`, `now`.
- Produces:
  - `ProjectScanner(roots: [URL], idleDays: Int, now: Date)` with `artifacts(named: [String: [String]]) -> [String: [URL]]` (key = directory name, value = artifact folder URLs) and `isIdle(project: URL, skipping: Set<String>) -> Bool`.
  - `ProjectScanner.defaultRoots(home: URL) -> [URL]`: the existing folders among `Projetos`, `Projects`, `dev`, `Developer`, `code`.
  - `ProjectScanner.maxDepth = 6`.

- [ ] **Step 1: Write the failing tests**

`Tests/SpareCoreTests/ProjectScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct ProjectScannerTests {
    let artifacts = [
        "node_modules": ["package.json"],
        ".venv": ["pyproject.toml", "requirements.txt", "setup.py"],
        "target": ["Cargo.toml"],
    ]

    func makeProject(_ home: TempHome, _ name: String, touchedDaysAgo: Double) throws {
        let date = daysAgo(touchedDaysAgo)
        try home.file("Projetos/\(name)/package.json", bytes: 200, modified: date)
        try home.file("Projetos/\(name)/src/index.js", bytes: 200, modified: date)
        try home.file("Projetos/\(name)/node_modules/lib/index.js", bytes: 20_000)
    }

    @Test func findsArtifactsOfIdleProjectsOnly() throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeProject(home, "old-app", touchedDaysAgo: 60)
        try makeProject(home, "active-app", touchedDaysAgo: 1)
        let scanner = ProjectScanner(roots: [home.path("Projetos")], idleDays: 30, now: Date())

        let found = scanner.artifacts(named: artifacts)

        #expect(found["node_modules"]?.map { $0.deletingLastPathComponent().lastPathComponent } == ["old-app"])
    }

    @Test func requiresTheManifestNextToTheArtifact() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Projetos/loose/node_modules/x.js", bytes: 1_000)
        try home.file("Projetos/loose/readme.md", bytes: 10, modified: daysAgo(90))
        let scanner = ProjectScanner(roots: [home.path("Projetos")], idleDays: 30, now: Date())

        #expect(scanner.artifacts(named: artifacts)["node_modules"] ?? [] == [])
    }

    @Test func doesNotDescendIntoArtifactsOrGit() throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeProject(home, "app", touchedDaysAgo: 60)
        try home.file("Projetos/app/node_modules/dep/package.json", bytes: 100, modified: daysAgo(60))
        try home.file("Projetos/app/node_modules/dep/node_modules/inner/x.js", bytes: 100)
        try home.file("Projetos/app/.git/objects/ab", bytes: 100)
        let scanner = ProjectScanner(roots: [home.path("Projetos")], idleDays: 30, now: Date())

        let found = scanner.artifacts(named: artifacts)["node_modules"] ?? []

        #expect(found.count == 1)
        #expect(found.first?.path.hasSuffix("Projetos/app/node_modules") == true)
    }

    @Test func gitActivityDoesNotCountButSourceEditsDo() throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeProject(home, "app", touchedDaysAgo: 60)
        try home.file("Projetos/app/.git/FETCH_HEAD", bytes: 10)
        let scanner = ProjectScanner(roots: [home.path("Projetos")], idleDays: 30, now: Date())
        #expect(scanner.artifacts(named: artifacts)["node_modules"]?.count == 1)

        try home.file("Projetos/app/src/new.js", bytes: 10)
        #expect(scanner.artifacts(named: artifacts)["node_modules"] ?? [] == [])
    }

    @Test func findsPythonAndRustArtifacts() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Projetos/py/pyproject.toml", bytes: 10, modified: daysAgo(40))
        try home.file("Projetos/py/.venv/lib/site.py", bytes: 5_000)
        try home.file("Projetos/rs/Cargo.toml", bytes: 10, modified: daysAgo(40))
        try home.file("Projetos/rs/target/debug/app", bytes: 5_000)
        let scanner = ProjectScanner(roots: [home.path("Projetos")], idleDays: 30, now: Date())

        let found = scanner.artifacts(named: artifacts)

        #expect(found[".venv"]?.count == 1)
        #expect(found["target"]?.count == 1)
    }

    @Test func respectsMaxDepth() throws {
        let home = try TempHome()
        defer { home.remove() }
        let deep = "Projetos/a/b/c/d/e/f/g/app"
        try home.file("\(deep)/package.json", bytes: 10, modified: daysAgo(60))
        try home.file("\(deep)/node_modules/x.js", bytes: 1_000)
        let scanner = ProjectScanner(roots: [home.path("Projetos")], idleDays: 30, now: Date())

        #expect(scanner.artifacts(named: artifacts)["node_modules"] ?? [] == [])
    }

    @Test func defaultRootsAreTheExistingConventionalFolders() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.directory("Projetos")
        try home.directory("dev")

        let roots = ProjectScanner.defaultRoots(home: home.url).map(\.lastPathComponent)

        #expect(roots == ["Projetos", "dev"])
    }
}
```

Add to `ScannerTests.swift`:

```swift
    @Test func scannerIncludesIdleProjectLeftovers() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Projetos/old/package.json", bytes: 10, modified: daysAgo(60))
        try home.file("Projetos/old/node_modules/lib.js", bytes: 30_000)
        let environment = SpareEnvironment.test(home: home.url, projectRoots: [home.path("Projetos")])

        let report = await Scanner(environment: environment).scan(categories: [.projectLeftovers])

        #expect(report.items.map(\.ruleID) == ["project.nodeModules"])
        #expect(report.items.first?.safety == .safe)
    }
```

Run: `swift test --filter ProjectScannerTests` → FAIL (`ProjectScanner` missing).

- [ ] **Step 2: Implement `ProjectScanner`**

`Sources/SpareCore/Scan/ProjectScanner.swift`:

```swift
import Foundation

public struct ProjectScanner: Sendable {
    public static let maxDepth = 6
    public static let conventionalRoots = ["Projetos", "Projects", "dev", "Developer", "code"]
    /// Folders that never count as "recent activity" and are never descended into.
    static let ignoredForActivity: Set<String> = [".git", "dist", "build", ".turbo", ".cache"]

    public let roots: [URL]
    public let idleDays: Int
    public let now: Date

    public init(roots: [URL], idleDays: Int, now: Date) {
        self.roots = roots
        self.idleDays = idleDays
        self.now = now
    }

    public static func defaultRoots(home: URL) -> [URL] {
        conventionalRoots
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
    }

    /// - Parameter named: artifact directory name -> manifest file names (any one is enough).
    /// - Returns: artifact directory name -> artifact URLs of idle projects.
    public func artifacts(named: [String: [String]]) -> [String: [URL]] {
        let fm = FileManager.default
        let artifactNames = Set(named.keys)
        var found: [String: [URL]] = [:]
        var idleCache: [String: Bool] = [:]

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [], errorHandler: { _, _ in true })
            else { continue }

            while let url = enumerator.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                let name = url.lastPathComponent
                if enumerator.level > Self.maxDepth || Self.ignoredForActivity.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                guard artifactNames.contains(name) else { continue }
                enumerator.skipDescendants()

                let project = url.deletingLastPathComponent()
                let manifests = named[name] ?? []
                let hasManifest = manifests.contains {
                    fm.fileExists(atPath: project.appendingPathComponent($0).path)
                }
                guard hasManifest else { continue }

                let idle = idleCache[project.path] ?? isIdle(project: project, skipping: artifactNames)
                idleCache[project.path] = idle
                if idle { found[name, default: []].append(url) }
            }
        }
        return found
    }

    /// True when no file outside artifacts and ignored folders changed within `idleDays`.
    public func isIdle(project: URL, skipping artifactNames: Set<String>) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(idleDays) * 86_400)
        guard let enumerator = FileManager.default.enumerator(
            at: project,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey],
            options: [], errorHandler: { _, _ in true })
        else { return false }

        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey])
            if values?.isDirectory == true {
                let name = url.lastPathComponent
                if artifactNames.contains(name) || Self.ignoredForActivity.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isSymbolicLink == true { continue }
            if let modified = values?.contentModificationDate, modified > cutoff { return false }
        }
        return true
    }
}
```

`enumerator.level` is 1 for direct children of the root. Depth test: the artifact sits at level 9, beyond `maxDepth`.

- [ ] **Step 3: Wire into the scanner**

In `Scanner.swift`, replace `case .projectArtifact: return []` with:

```swift
        case .projectArtifact(let directoryName, _):
            return projectArtifacts()[directoryName] ?? []
```

so `candidates(for:)` works for a single project rule (used by tests and the CLI). Inside `scan`, the four project rules must not walk the roots four times, so compute their artifacts once: change the candidates loop in `scan(categories:progress:)` to

```swift
        let projectRules = rules.filter { if case .projectArtifact = $0.kind { true } else { false } }
        let projectFound = projectRules.isEmpty ? [:] : projectArtifacts(for: projectRules)
        var candidates: [(Rule, URL)] = []
        for rule in rules where !Task.isCancelled {
            if case .projectArtifact(let name, _) = rule.kind {
                candidates += (projectFound[name] ?? []).map { (rule, $0) }
            } else {
                candidates += self.candidates(for: rule).map { (rule, $0) }
            }
        }
```

with

```swift
    func projectArtifacts(for rules: [Rule]) -> [String: [URL]] {
        var named: [String: [String]] = [:]
        for rule in rules {
            if case .projectArtifact(let name, let manifests) = rule.kind { named[name] = manifests }
        }
        return ProjectScanner(roots: environment.projectRoots, idleDays: environment.projectIdleDays,
                              now: environment.now()).artifacts(named: named)
    }

    func projectArtifacts() -> [String: [URL]] {
        projectArtifacts(for: catalog.rules)
    }
```

In `SpareEnvironment.live(home:)`:

```swift
    public static func live(home: URL) -> SpareEnvironment {
        let resolved = home.resolvingSymlinksInPath()
        return SpareEnvironment(home: resolved, projectRoots: ProjectScanner.defaultRoots(home: resolved))
    }
```

- [ ] **Step 4: Run the tests**

Run: `swift test` → all PASS. Manual read-only smoke: `swift run spare scan --category projectLeftovers` lists idle projects in `~/Projetos` and `~/dev`, and the run takes under 60 s. Record the elapsed time in the PR description (`time swift run -c release spare scan --category projectLeftovers > /dev/null`).

- [ ] **Step 5: Docs, gates, commit**

CHANGELOG `Added: idle project leftovers (node_modules, .venv, .next, target)`; STATUS (Task 3 done). `scripts/check.sh` green.

```bash
git add -A
git commit -m "feat(core): detect idle project leftovers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
