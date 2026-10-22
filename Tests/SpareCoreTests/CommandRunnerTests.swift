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
