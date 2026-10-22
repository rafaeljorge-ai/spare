import Foundation
import Testing
@testable import SpareCore

@Suite struct ProcessListerTests {
    let comm = """
      101   501  204800 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      102   501   51200 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper (Renderer)
      200   501   10240 /opt/homebrew/bin/node
      300     0    4096 /usr/sbin/syslogd
    """
    let args = """
      101   /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      102   /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
      200   node /Users/x/.npm/_npx/abc123/node_modules/.bin/mcp-server --stdio
      300   /usr/sbin/syslogd
    """
    // `lsof -a -d cwd -Fpn` output: one `p<pid>` line, then `fcwd`, then `n<path>`.
    let cwd = """
    p200
    fcwd
    n/Users/x/.npm/_npx/abc123
    p300
    fcwd
    n/
    pnotanumber
    n/ignored
    """

    @Test func parsesPidUidMemoryAndPaths() {
        let list = ProcessLister.parse(comm: comm, args: args)

        #expect(list.count == 4)
        let chrome = list.first { $0.pid == 101 }!
        #expect(chrome.uid == 501)
        #expect(chrome.rssBytes == 204_800 * 1024)
        #expect(chrome.executablePath == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        #expect(chrome.appBundlePath == "/Applications/Google Chrome.app")
        #expect(chrome.name == "Google Chrome")
    }

    @Test func helpersBelongToTheOutermostApp() {
        let helper = ProcessLister.parse(comm: comm, args: args).first { $0.pid == 102 }!

        #expect(helper.appBundlePath == "/Applications/Google Chrome.app")
        #expect(helper.name == "Google Chrome")
    }

    @Test func plainExecutablesUseTheirFileName() {
        let node = ProcessLister.parse(comm: comm, args: args).first { $0.pid == 200 }!

        #expect(node.name == "node")
        #expect(node.appBundlePath == nil)
        #expect(node.commandLine.contains(".npm/_npx/abc123"))
    }

    @Test func attachesWorkingDirectories() {
        let list = ProcessLister.parse(comm: comm, args: args, cwd: cwd)

        #expect(list.first { $0.pid == 200 }?.cwd == "/Users/x/.npm/_npx/abc123")
        #expect(list.first { $0.pid == 300 }?.cwd == "/")
        #expect(list.first { $0.pid == 101 }?.cwd == nil)
    }

    @Test func ignoresLinesWithoutAPid() {
        #expect(ProcessLister.parse(comm: "garbage\n\n  abc 501 10 node\n  12 x y\n", args: "").isEmpty)
    }

    @Test func keepsProcessesLaunchedByNameAndResolvesTheirPath() {
        let comm = "  400   501   2048 node\n  401   501   1024 cargo\n  402   501   512 Google Chrome Helper\n"
        let args = "  400   node /Users/x/.npm/_npx/abc123/node_modules/.bin/x\n  401   cargo build\n"

        let list = ProcessLister.parse(comm: comm, args: args) { pid in
            pid == 400 ? "/opt/homebrew/Cellar/node/25.0/bin/node" : nil
        }

        #expect(list.count == 3)
        let node = list.first { $0.pid == 400 }!
        #expect(node.executablePath == "/opt/homebrew/Cellar/node/25.0/bin/node")
        #expect(node.name == "node")
        #expect(node.commandLine.contains(".npm/_npx/abc123"))
        let cargo = list.first { $0.pid == 401 }!
        #expect(cargo.executablePath == "cargo")  // unresolved: falls back to the comm name
        #expect(cargo.executableName == "cargo")
        #expect(cargo.name == "cargo")
        #expect(list.first { $0.pid == 402 }?.name == "Google Chrome Helper")
    }

    @Test func absoluteCommNeverAsksTheResolver() {
        let list = ProcessLister.parse(comm: comm, args: args) { _ in "/wrong" }

        #expect(list.first { $0.pid == 200 }?.executablePath == "/opt/homebrew/bin/node")
    }

    @Test func resolvesThePathOfARunningPid() {
        let path = ProcessLister.executablePath(ofPid: ProcessInfo.processInfo.processIdentifier)

        #expect(path?.hasPrefix("/") == true)
    }

    @Test func runReturnsOutput() {
        #expect(ProcessLister.run("/bin/echo", ["hi"], timeout: 5) == "hi\n")
    }

    @Test func runGivesUpOnAStuckCommand() {
        let started = Date()

        #expect(ProcessLister.run("/bin/sleep", ["30"], timeout: 0.3) == nil)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func runReportsMissingExecutables() {
        #expect(ProcessLister.run("/nonexistent/tool", [], timeout: 1) == nil)
    }

    @Test func liveListingFailsWhenPsFails() {
        #expect(throws: ProcessListingError.self) {
            _ = try ProcessLister.live(psPath: "/nonexistent/ps")
        }
    }

    @Test func liveListingSurvivesAFailingLsof() throws {
        let list = try ProcessLister.live(lsofPath: "/nonexistent/lsof")

        #expect(list.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
        #expect(list.allSatisfy { $0.cwd == nil })
    }

    @Test func scriptNameSkipsInterpreterFlags() {
        func script(_ line: String) -> String? {
            RunningProcess(pid: 1, uid: 1, rssBytes: 1, executablePath: "/x/node", commandLine: line,
                           appBundlePath: nil, appBundleID: nil, name: "node").scriptName
        }

        #expect(script("node --max-old-space-size=4096 /opt/homebrew/bin/yarn install") == "yarn")
        #expect(script("node /opt/homebrew/bin/npm install") == "npm")
        #expect(script("node") == nil)
        #expect(script("node --version") == nil)
    }

    @Test func liveListingContainsThisProcess() {
        let list = (try? ProcessLister.live()) ?? []
        #expect(list.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
    }

    @Test func liveListingReportsTheWorkingDirectoryOfThisProcess() {
        let mine = (try? ProcessLister.live())?.first { $0.pid == ProcessInfo.processInfo.processIdentifier }

        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path
        #expect(mine?.cwd.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == expected)
    }
}
