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
        try home.file("Projetos/app/package.json")
        try home.file("Other/app/package.json")

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

    @Test func userFilesRefuseFoldersThatContainCriticalOrProtectedOnes() throws {
        let home = try TempHome()
        defer { home.remove() }
        let guardian = SafetyGuard(home: home.url, projectRoots: [])

        #expect(!guardian.canTrashUserFile(try home.directory("Library")))
        #expect(!guardian.canTrashUserFile(try home.directory("Documents")))
        #expect(!guardian.canTrashUserFile(try home.directory("Desktop")))
        #expect(!guardian.canTrashUserFile(try home.directory(".ssh")))
        #expect(!guardian.canTrashUserFile(try home.directory("Library/Keychains")))
        #expect(guardian.canTrashUserFile(try home.directory("Documents/old-project")))
    }

    @Test func dotDotComponentsAreResolvedBeforeJudging() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".ssh/id_ed25519")
        try home.directory("Other")
        let guardian = SafetyGuard(home: home.url, projectRoots: [])
        let sneaky = URL(fileURLWithPath: home.url.path + "/Other/../.ssh/id_ed25519")

        #expect(!guardian.canTrashUserFile(sneaky))
        #expect(guardian.violation(for: sneaky, rule: rule("dev.npm")) == .protected)
        let escape = URL(fileURLWithPath: home.url.path + "/.npm/_cacache/../../.ssh")
        try home.directory(".npm/_cacache")
        #expect(guardian.violation(for: escape, rule: rule("dev.npm")) == .protected)
    }

    @Test func pathRuleWhoseTargetIsASymlinkToAProjectIsRefused() throws {
        let home = try TempHome()
        defer { home.remove() }
        let projects = try home.directory("Projetos/app")
        try home.directory(".npm")
        try FileManager.default.createSymbolicLink(
            at: home.path(".npm/_cacache"), withDestinationURL: projects)
        let guardian = SafetyGuard(home: home.url, projectRoots: [home.path("Projetos")])

        #expect(guardian.violation(for: home.path(".npm/_cacache"), rule: rule("dev.npm")) != nil)
    }

    @Test func childrenRuleHonorsExtensionsAndMinimumAge() throws {
        let home = try TempHome()
        defer { home.remove() }
        let guardian = SafetyGuard(home: home.url, projectRoots: [])
        let installers = rule("downloads.installers")

        #expect(guardian.violation(for: try home.directory("Downloads/Trabalho"), rule: installers) == .outsideCatalog)
        #expect(guardian.violation(for: try home.file("Downloads/notes.txt", modified: daysAgo(90)), rule: installers) == .outsideCatalog)
        #expect(guardian.violation(for: try home.file("Downloads/new.dmg", modified: daysAgo(2)), rule: installers) == .outsideCatalog)
        #expect(guardian.violation(for: try home.file("Downloads/old.DMG", modified: daysAgo(90)), rule: installers) == nil)
    }

    @Test func projectArtifactNeedsItsManifestAndRefusesGit() throws {
        let home = try TempHome()
        defer { home.remove() }
        let root = try home.directory("Projetos")
        let guardian = SafetyGuard(home: home.url, projectRoots: [root])
        let target = rule("project.rustTarget")

        #expect(guardian.violation(for: try home.directory("Projetos/nomanifest/target"), rule: target) == .outsideCatalog)
        try home.file("Projetos/crate/package.json")
        #expect(guardian.violation(for: try home.directory("Projetos/crate/target"), rule: target) == .outsideCatalog)
        try home.file("Projetos/crate/Cargo.toml")
        #expect(guardian.violation(for: home.path("Projetos/crate/target"), rule: target) == nil)

        try home.file("Projetos/repo/.git/modules/x/package.json")
        #expect(guardian.violation(for: try home.directory("Projetos/repo/.git/modules/x/node_modules"),
                                   rule: rule("project.nodeModules")) != nil)
    }

    @Test func genericRuleRefusesPathsOwnedBySpecificRules() throws {
        let home = try TempHome()
        defer { home.remove() }
        let guardian = SafetyGuard(home: home.url, projectRoots: [])
        let caches = rule("apps.caches")

        #expect(guardian.violation(for: try home.directory("Library/Caches/ms-playwright"), rule: caches) == .outsideCatalog)
        #expect(guardian.violation(for: try home.directory("Library/Caches/Homebrew"), rule: caches) == .outsideCatalog)
        #expect(guardian.violation(for: try home.directory("Library/Caches/com.example.app"), rule: caches) == nil)
    }

    @Test func claimedPathsMatchEvenWhenHomeIsReachedThroughPrivateVar() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.directory("Library/Caches/ms-playwright")
        let guardian = SafetyGuard(home: home.url, projectRoots: [])
        // Same folder spelled through the /var symlink instead of /private/var.
        let viaVar = home.url.path.hasPrefix("/private/var")
            ? String(home.url.path.dropFirst("/private".count)) : home.url.path
        let item = URL(fileURLWithPath: viaVar + "/Library/Caches/ms-playwright")

        #expect(guardian.violation(for: item, rule: rule("apps.caches")) == .outsideCatalog)
    }
}
