import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct CommandRunnerTests {
    /// Runner for tests: never starts the real login shell.
    func runner(_ home: TempHome, commandTimeout: TimeInterval = 10,
                fallback: @escaping @Sendable (String) -> String? = { _ in nil }) -> SystemCommandRunner {
        SystemCommandRunner(home: home.url, searchPaths: [home.path("bin").path, "/usr/bin", "/bin"],
                            lookupTimeout: 5, commandTimeout: commandTimeout, fallbackLookup: fallback)
    }

    @discardableResult
    func script(_ home: TempHome, _ name: String, _ body: String) throws -> URL {
        let tool = try home.file("bin/\(name)", bytes: 0)
        try "#!/bin/sh\n\(body)\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    @Test func findsToolsInExtraSearchPathsAndPassesPATH() throws {
        let home = try TempHome()
        defer { home.remove() }
        try script(home, "fake-tool", "echo \"args:$1 path-has-bin:$(echo $PATH | grep -c \(home.path("bin").path))\"")

        let result = try runner(home).run("fake-tool", ["hello"])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("args:hello"))
        #expect(result.output.contains("path-has-bin:1"))
    }

    @Test func missingToolThrowsNotFound() throws {
        let home = try TempHome()
        defer { home.remove() }

        #expect(throws: CommandError.notFound("surely-not-a-real-tool-xyz")) {
            try runner(home).run("surely-not-a-real-tool-xyz", [])
        }
    }

    @Test func injectedFallbackLookupFindsToolsOutsideTheSearchPaths() throws {
        let home = try TempHome()
        defer { home.remove() }
        let tool = try script(home, "hidden-tool", "echo found")
        let moved = try home.file("elsewhere/hidden-tool", bytes: 0)
        try FileManager.default.removeItem(at: moved)
        try FileManager.default.moveItem(at: tool, to: moved)

        let result = try runner(home, fallback: { $0 == "hidden-tool" ? moved.path : nil }).run("hidden-tool", [])

        #expect(result.output.contains("found"))
    }

    @Test func commandDoesNotInheritStandardInput() throws {
        let home = try TempHome()
        defer { home.remove() }
        // With an inherited terminal or pipe, `read` would wait for input.
        try script(home, "reader", "read line; echo \"got:[$line]\"")

        let result = try runner(home, commandTimeout: 10).run("reader", [])

        #expect(result.output.contains("got:[]"))
    }

    @Test func commandThatRunsTooLongIsTerminated() throws {
        let home = try TempHome()
        defer { home.remove() }
        try script(home, "sleepy", "exec sleep 30")
        let started = Date()

        #expect(throws: CommandError.timedOut("sleepy")) {
            try runner(home, commandTimeout: 0.3).run("sleepy", [])
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func fallbackOutputTakesTheLastAbsolutePathLine() {
        let noisy = "Welcome back!\nnvm: using node 20\n/Users/x/.volta/bin/uv\n\n"

        #expect(SystemCommandRunner.lastAbsolutePath(in: noisy) == "/Users/x/.volta/bin/uv")
        #expect(SystemCommandRunner.lastAbsolutePath(in: "/first/uv\n/second/uv\n") == "/second/uv")
        #expect(SystemCommandRunner.lastAbsolutePath(in: "uv not found\n") == nil)
        #expect(SystemCommandRunner.lastAbsolutePath(in: "") == nil)
    }
}

@Suite struct TestHomeIsolationTests {
    @Test func toolsRunWithTheEnvironmentHome() throws {
        let home = try TempHome()
        defer { home.remove() }
        let tool = try home.file("bin/show-home", bytes: 0)
        try "#!/bin/sh\necho \"HOME=$HOME\"\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let runner = SystemCommandRunner(home: home.url, searchPaths: [home.path("bin").path], fallbackLookup: { _ in nil })

        let result = try runner.run("show-home", [])

        #expect(result.output.contains("HOME=\(home.url.path)"))
    }

    @Test func aDisabledRunnerRefusesEveryTool() throws {
        let home = try TempHome()
        defer { home.remove() }
        let runner = SystemCommandRunner(home: home.url, searchPaths: ["/usr/bin", "/bin"], disabled: true, fallbackLookup: { _ in nil })

        #expect(throws: CommandError.disabled("true")) { try runner.run("true", []) }
    }

    @Test func spareHomeTurnsToolCommandsOffUnlessAllowed() {
        #expect(SystemCommandRunner.toolCommandsDisabled(["SPARE_HOME": "/tmp/x"]))
        #expect(!SystemCommandRunner.toolCommandsDisabled([:]))
        #expect(!SystemCommandRunner.toolCommandsDisabled(["SPARE_HOME": "/tmp/x", "SPARE_ALLOW_TOOL_COMMANDS": "1"]))
    }

    @Test func aDisabledCommandItemIsSkippedWithAReason() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let cache = try home.directory(".npm/_cacache")
        let runner = SystemCommandRunner(home: home.url, searchPaths: ["/usr/bin", "/bin"], disabled: true, fallbackLookup: { _ in nil })
        let item = ScanItem(ruleID: "dev.npm", category: .devCaches, url: cache, sizeBytes: 1_000, safety: .safe)

        let record = await Cleaner(environment: .test(home: home.url, commandRunner: runner)).clean([item])

        #expect(record.entries.first?.status == .skipped)
        #expect(record.entries.first?.skipReason == .toolsDisabled)
    }

    @Test func aFakeHomeAloneUsesItsOwnTrashFolder() {
        let home = URL(fileURLWithPath: "/tmp/fake", isDirectory: true)
        #expect(TrashFolder.override(variables: ["SPARE_HOME": "/tmp/fake"], home: home)?.path == "/tmp/fake/.Trash")
        #expect(TrashFolder.override(variables: ["SPARE_HOME": "/tmp/fake", "SPARE_TRASH_DIR": "/tmp/t"], home: home)?.path == "/tmp/t")
        #expect(TrashFolder.override(variables: [:], home: home) == nil)
    }
}
