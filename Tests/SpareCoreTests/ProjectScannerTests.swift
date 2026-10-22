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

    @Test func skipsSymlinkedArtifactsAndRootsInsideGit() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Projetos/app/package.json", bytes: 10, modified: daysAgo(60))
        try home.file("elsewhere/lib.js", bytes: 1_000)
        try FileManager.default.createSymbolicLink(
            at: home.path("Projetos/app/node_modules"), withDestinationURL: home.path("elsewhere"))
        try home.file("Projetos/.git/pkg/package.json", bytes: 10, modified: daysAgo(60))
        try home.file("Projetos/.git/pkg/node_modules/x.js", bytes: 1_000)

        let inProjects = ProjectScanner(roots: [home.path("Projetos")], idleDays: 30, now: Date())
        let insideGit = ProjectScanner(roots: [home.path("Projetos/.git")], idleDays: 30, now: Date())

        #expect(inProjects.artifacts(named: artifacts)["node_modules"] ?? [] == [])
        #expect(insideGit.artifacts(named: artifacts)["node_modules"] ?? [] == [])
    }

    @Test func everythingFoundIsAcceptedBySafetyGuard() throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeProject(home, "old-app", touchedDaysAgo: 60)
        try home.file("Projetos/rs/Cargo.toml", bytes: 10, modified: daysAgo(40))
        try home.file("Projetos/rs/target/debug/app", bytes: 5_000)
        let roots = [home.path("Projetos")]
        let scanner = ProjectScanner(roots: roots, idleDays: 30, now: Date())
        let guardrail = SafetyGuard(home: home.url, projectRoots: roots)

        let found = scanner.artifacts(named: artifacts)

        #expect(found.values.joined().count == 2)
        for rule in RuleCatalog.standard.rules {
            guard case .projectArtifact(let name, _) = rule.kind else { continue }
            for url in found[name] ?? [] {
                #expect(guardrail.violation(for: url, rule: rule) == nil)
            }
        }
    }
}
