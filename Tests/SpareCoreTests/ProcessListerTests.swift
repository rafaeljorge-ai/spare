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

    @Test func ignoresMalformedLines() {
        #expect(ProcessLister.parse(comm: "garbage\n\n  12 x y\n", args: "").isEmpty)
    }

    @Test func liveListingContainsThisProcess() {
        let list = ProcessLister.live()
        #expect(list.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
    }

    @Test func liveListingReportsTheWorkingDirectoryOfThisProcess() {
        let mine = ProcessLister.live().first { $0.pid == ProcessInfo.processInfo.processIdentifier }

        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path
        #expect(mine?.cwd.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == expected)
    }
}
