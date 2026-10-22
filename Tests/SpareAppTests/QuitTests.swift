import Foundation
import Testing
import SpareCore
@testable import SpareApp

@Suite struct QuitPromptTests {
    func process(_ pid: Int32, rss: Int64 = 1_000_000, command: String = "node server.js") -> RunningProcess {
        RunningProcess(pid: pid, uid: 501, rssBytes: rss, executablePath: "/usr/local/bin/node", commandLine: command,
                       appBundlePath: nil, appBundleID: nil, name: "node")
    }

    func consumer(_ pids: [Int32], isApp: Bool = false) -> MemoryConsumer {
        MemoryConsumer(id: "/usr/local/bin/node", name: "node", bytes: 5, pids: pids, appBundleID: nil, isApp: isApp)
    }

    @Test func aSingleProcessNeedsNoList() {
        let prompt = QuitPrompt.make(consumer: consumer([10]), processes: [10: process(10)])
        #expect(!prompt.isGrouped)
        #expect(prompt.lines.isEmpty)
        #expect(prompt.hiddenCount == 0)
    }

    @Test func aGroupedRowListsPidsAndCommandsBiggestFirst() {
        let processes: [Int32: RunningProcess] = [
            11: process(11, rss: 5_000_000, command: "node a.js"),
            12: process(12, rss: 9_000_000, command: "node b.js"),
            13: process(13, rss: 1_000_000, command: "node c.js"),
        ]
        let prompt = QuitPrompt.make(consumer: consumer([11, 12, 13]), processes: processes)
        #expect(prompt.isGrouped)
        #expect(prompt.lines.map(\.pid) == [12, 11, 13])
        #expect(prompt.lines.map(\.command) == ["node b.js", "node a.js", "node c.js"])
        #expect(prompt.hiddenCount == 0)
    }

    @Test func longGroupsAreCappedAndCommandsShortened() {
        let pids = Array(Int32(100)..<Int32(112))
        let processes = Dictionary(uniqueKeysWithValues: pids.map {
            ($0, process($0, command: "node " + String(repeating: "x", count: 300)))
        })
        let prompt = QuitPrompt.make(consumer: consumer(pids), processes: processes)
        #expect(prompt.lines.count == QuitPrompt.maxLines)
        #expect(prompt.hiddenCount == pids.count - QuitPrompt.maxLines)
        #expect(prompt.lines.allSatisfy { $0.command.count <= QuitPrompt.maxCommandLength })
        #expect(prompt.lines[0].command.hasSuffix("..."))
    }

    @Test func showsOnlyTheExecutableAndTheFirstArgument() {
        let command = "/opt/homebrew/bin/node server.js --port 3000 --api-key=EXAMPLE_NOT_A_SECRET --token EXAMPLE_NOT_A_TOKEN"
        #expect(QuitPrompt.display(command) == "/opt/homebrew/bin/node server.js")
        #expect(QuitPrompt.display("node --inspect app.js --flag") == "node app.js")
        #expect(QuitPrompt.display("tool") == "tool")
        // A masked value is never the "first argument".
        #expect(QuitPrompt.display("cli --token EXAMPLE_NOT_A_TOKEN") == "cli")
        #expect(!QuitPrompt.display("cli -secret EXAMPLE_NOT_A_SECRET run").contains("EXAMPLE_NOT_A_SECRET"))
    }

    @Test func aSecretInTheFirstArgumentIsMasked() {
        #expect(QuitPrompt.display("psql postgres://user:hunter2@db.local/app") == "psql postgres://***@db.local/app")
        let prompt = QuitPrompt.make(
            consumer: consumer([30, 31]),
            processes: [30: process(30, command: "node worker.js --token EXAMPLE_NOT_A_TOKEN"), 31: process(31, command: "node --x")])
        #expect(prompt.lines.allSatisfy { !$0.command.contains("EXAMPLE_NOT_A_TOKEN") })
    }

    @Test func redactMasksKeyValueFlagsAndCredentialUrls() {
        #expect(QuitPrompt.redact("run --api-key=EXAMPLE_NOT_A_SECRET") == "run --api-key=***")
        #expect(QuitPrompt.redact("run --token EXAMPLE_NOT_A_TOKEN --port 80") == "run --token *** --port 80")
        #expect(QuitPrompt.redact("run -p abc") == "run -p abc")
        #expect(QuitPrompt.redact("run -secret abc") == "run -secret ***")
        #expect(QuitPrompt.redact("run --PASSWORD=x --client-cred y") == "run --PASSWORD=*** --client-cred ***")
        #expect(QuitPrompt.redact("conn postgres://u:p@h") == "conn postgres://***@h")
        #expect(QuitPrompt.redact("conn https://host/path") == "conn https://host/path")
        #expect(QuitPrompt.redact("run --port=80") == "run --port=80")
    }

    @Test func aPidMissingFromTheListingStillShows() {
        let prompt = QuitPrompt.make(consumer: consumer([20, 21]), processes: [20: process(20)])
        #expect(prompt.lines.map(\.pid).sorted() == [20, 21])
    }
}

@Suite struct AppQuitterTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var graceful: [Int32] = []
        private var signaled: [Int32] = []
        var gracefulPIDs: [Int32] { lock.withLock { graceful } }
        var signaledPIDs: [Int32] { lock.withLock { signaled } }
        func gracefulCall(_ pid: Int32) { lock.withLock { graceful.append(pid) } }
        func signalCall(_ pid: Int32) { lock.withLock { signaled.append(pid) } }
    }

    func quitter(_ calls: Calls, registered: Set<Int32>) -> AppQuitter {
        AppQuitter(
            graceful: { pid in
                calls.gracefulCall(pid)
                return registered.contains(pid) ? true : nil
            },
            signal: SignalQuitter(send: { pid, _ in
                calls.signalCall(pid)
                return 0
            }))
    }

    func process(_ pid: Int32, bundle: String?) -> RunningProcess {
        RunningProcess(pid: pid, uid: 501, rssBytes: 1, executablePath: "/x/\(pid)", commandLine: "x",
                       appBundlePath: bundle, appBundleID: nil, name: "x")
    }

    @Test func anAppWithABundleIsAskedGracefullyNeverSignaled() {
        let calls = Calls()
        let quitter = quitter(calls, registered: [7])
        #expect(quitter.quit(process(7, bundle: "/Applications/Notes.app")))
        #expect(calls.gracefulPIDs == [7])
        #expect(calls.signaledPIDs.isEmpty)
    }

    @Test func aHelperOfABundledAppIsNotSignaled() {
        let calls = Calls()
        let quitter = quitter(calls, registered: [])
        #expect(!quitter.quit(process(8, bundle: "/Applications/Chrome.app")))
        #expect(calls.signaledPIDs.isEmpty)
    }

    @Test func aProcessWithoutABundleGetsSIGTERM() {
        let calls = Calls()
        let quitter = quitter(calls, registered: [])
        #expect(quitter.quit(process(9, bundle: nil)))
        #expect(calls.signaledPIDs == [9])
        #expect(calls.gracefulPIDs.isEmpty)
    }
}
