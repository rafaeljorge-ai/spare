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
