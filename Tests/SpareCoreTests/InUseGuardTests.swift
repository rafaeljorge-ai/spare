import Foundation
import Testing
@testable import SpareCore

@Suite struct InUseGuardTests {
    func process(_ name: String, path: String, args: String? = nil, cwd: String? = nil,
                 app: String? = nil, bundleID: String? = nil) -> RunningProcess {
        RunningProcess(pid: 10, uid: 501, rssBytes: 1, executablePath: path, commandLine: args ?? path,
                       appBundlePath: app, appBundleID: bundleID, name: name, cwd: cwd)
    }
    let catalog = RuleCatalog.standard

    @Test func blocksByExecutableName() {
        let guardian = InUseGuard(processes: [process("Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude",
                                                       app: "/Applications/Claude.app")])
        let rule = catalog.rule(id: "ai.claudeVM")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Library/Application Support/Claude/vm_bundles")) == "Claude")
    }

    @Test func blocksByScriptNameForInterpreterTools() {
        let guardian = InUseGuard(processes: [process("node", path: "/opt/homebrew/bin/node",
                                                       args: "node /opt/homebrew/bin/yarn install")])

        #expect(guardian.reason(rule: catalog.rule(id: "dev.yarn")!, url: URL(fileURLWithPath: "/Users/x/Library/Caches/Yarn")) == "node")
    }

    @Test func blocksWhenACommandLineUsesThePath() {
        let guardian = InUseGuard(processes: [process("node", path: "/opt/homebrew/bin/node",
                                                       args: "node /Users/x/.npm/_npx/abc123/node_modules/.bin/mcp")])
        let rule = catalog.rule(id: "dev.npx")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc123")) == "node")
        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc1")) == nil)
    }

    @Test func npxPackageInUseWhenAProcessRunsFromItsFolder() {
        // An MCP server started through npx often has a bare command line; only its cwd points at the package.
        let guardian = InUseGuard(processes: [
            process("node", path: "/opt/homebrew/bin/node", args: "node server.js", cwd: "/Users/x/.npm/_npx/abc123/node_modules/mcp"),
        ])
        let rule = catalog.rule(id: "dev.npx")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc123")) == "node")
        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc1")) == nil)
    }

    @Test func workingDirectoryMustBeInsideNotMerelyPrefixed() {
        let guardian = InUseGuard(processes: [
            process("node", path: "/opt/homebrew/bin/node", args: "node server.js", cwd: "/Users/x/.npm/_npx/abc123456"),
        ])

        #expect(guardian.reason(rule: catalog.rule(id: "dev.npx")!, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc123")) == nil)
    }

    @Test func workingDirectoryOfTheFolderItselfCounts() {
        let guardian = InUseGuard(processes: [
            process("node", path: "/opt/homebrew/bin/node", args: "node server.js", cwd: "/Users/x/.npm/_npx/abc123"),
        ])

        #expect(guardian.reason(rule: catalog.rule(id: "dev.npx")!, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc123")) == "node")
    }

    @Test func matchesAcrossPrivateSymlinkSpelling() {
        let guardian = InUseGuard(processes: [
            process("node", path: "/opt/homebrew/bin/node", args: "node /var/folders/t/.npm/_npx/abc123/bin/mcp"),
        ])
        let rule = catalog.rule(id: "dev.npx")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/private/var/folders/t/.npm/_npx/abc123")) == "node")
    }

    @Test func projectArtifactsCheckTheProjectFolder() {
        let guardian = InUseGuard(processes: [process("node", path: "/opt/homebrew/bin/node",
                                                       args: "node /Users/x/Projetos/app/server.js")])
        let rule = catalog.rule(id: "project.nodeModules")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Projetos/app/node_modules")) == "node")
        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Projetos/app2/node_modules")) == nil)
    }

    @Test func projectArtifactsIgnoreAShellParkedInTheProject() {
        let guardian = InUseGuard(processes: [process("zsh", path: "/bin/zsh", args: "-zsh", cwd: "/Users/x/Projetos/app")])
        let rule = catalog.rule(id: "project.nodeModules")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Projetos/app/node_modules")) == nil)
    }

    @Test func blocksAppCachesOfRunningApps() {
        let guardian = InUseGuard(processes: [process("Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack",
                                                       app: "/Applications/Slack.app", bundleID: "com.tinyspeck.slackmacgap")])
        let rule = catalog.rule(id: "apps.caches")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Library/Caches/com.tinyspeck.slackmacgap")) == "Slack")
        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Library/Caches/com.other.app")) == nil)
    }

    @Test func officialCommandRulesAreNeverBlocked() {
        let guardian = InUseGuard(processes: [process("uv", path: "/opt/homebrew/bin/uv", args: "uv run server.py")])

        #expect(guardian.reason(rule: catalog.rule(id: "dev.uv")!, url: URL(fileURLWithPath: "/Users/x/.cache/uv")) == nil)
    }
}
