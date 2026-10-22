import Foundation
import Testing
@testable import SpareCore

@Suite struct ProcessTerminatorTests {
    /// Records the quit requests instead of signaling anything.
    final class Recorder: ProcessQuitter, @unchecked Sendable {
        var quit: [Int32] = []
        var succeeds = true
        func quit(_ process: RunningProcess) -> Bool {
            quit.append(process.pid)
            return succeeds
        }
    }

    func proc(_ pid: Int32, uid: UInt32 = 501, path: String = "/opt/homebrew/bin/node", app: String? = nil, name: String = "x", bundleID: String? = nil) -> RunningProcess {
        RunningProcess(pid: pid, uid: uid, rssBytes: 1, executablePath: path, commandLine: path,
                       appBundlePath: app, appBundleID: bundleID, name: name)
    }

    func consumer(_ pids: [Int32]) -> MemoryConsumer {
        MemoryConsumer(id: "x", name: "x", bytes: 2, pids: pids, appBundleID: nil, isApp: false)
    }

    func run(_ pids: [Int32], _ processes: [RunningProcess], ancestors: Set<Int32> = [], recorder: Recorder = Recorder(),
             live: ((Int32) -> String?)? = nil) -> (Int, Recorder) {
        let count = ProcessTerminator.terminate(
            consumer(pids), processes: processes, currentUID: 501, ownPID: 999, ancestors: ancestors,
            currentPath: live ?? { pid in processes.first { $0.pid == pid }?.executablePath },
            bundleID: { _ in nil }, quitter: recorder)
        return (count, recorder)
    }

    @Test func quitsOnlyAllowedProcessesByPID() {
        let processes = [proc(10), proc(11, uid: 0), proc(1, path: "/sbin/launchd")]

        let (count, recorder) = run([10, 11, 1, 999, 12345], processes)

        #expect(count == 1)
        #expect(recorder.quit == [10])
    }

    @Test func refusesSystemPathsAndTheOwnPID() {
        let processes = [
            proc(20, path: "/usr/libexec/trustd"),
            proc(21, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
            proc(999, path: "/opt/x/self"),
            proc(22),
        ]

        let (count, recorder) = run([20, 21, 999, 22], processes)

        #expect(count == 1)
        #expect(recorder.quit == [22])
    }

    @Test func refusesSpareByBundleIDOrName() {
        let processes = [
            proc(30, path: "/Applications/Other.app/Contents/MacOS/o", app: "/Applications/Other.app", name: "Other",
                 bundleID: "ai.rafaeljorge.spare"),
            proc(31, path: "/opt/bin/spare", name: "spare"),
            proc(32, path: "/Applications/Spare.app/Contents/MacOS/Spare", app: "/Applications/Spare.app", name: "Spare"),
            proc(33, path: "/Applications/Renamed.app/Contents/MacOS/r", app: "/Applications/Renamed.app", name: "Renamed"),
        ]

        let recorder = Recorder()
        let count = ProcessTerminator.terminate(
            consumer([30, 31, 32, 33]), processes: processes, currentUID: 501, ownPID: 999, ancestors: [],
            currentPath: { pid in processes.first { $0.pid == pid }?.executablePath },
            bundleID: { $0 == "/Applications/Renamed.app" ? "ai.rafaeljorge.spare" : nil }, quitter: recorder)

        #expect(count == 0)
        #expect(recorder.quit.isEmpty)
    }

    @Test func refusesTheAncestorsOfTheCurrentProcess() {
        let processes = [proc(40, path: "/opt/term/shell"), proc(41, path: "/opt/term/terminal"), proc(42)]

        let (count, recorder) = run([40, 41, 42], processes, ancestors: [40, 41])

        #expect(count == 1)
        #expect(recorder.quit == [42])
    }

    @Test func ancestorChainFollowsParents() {
        let parents: [Int32: Int32] = [500: 400, 400: 300, 300: 1]

        #expect(ProcessTerminator.ancestors(of: 500, parent: { parents[$0] }) == [400, 300])
        #expect(ProcessTerminator.ancestors(of: 500, parent: { _ in 500 }).isEmpty)
    }

    @Test func usesTheLivePathNotTheListedOne() {
        // The listing says harmless, the live path says system: refuse. Gone or recycled pids are refused too.
        let processes = [proc(50, path: "/opt/bin/fake"), proc(51), proc(52)]

        let (count, recorder) = run([50, 51, 52], processes, live: { pid in
            switch pid {
            case 50: "/usr/libexec/real-system-thing"
            case 51: "/opt/other/recycled"
            default: nil
            }
        })

        #expect(count == 0)
        #expect(recorder.quit.isEmpty)
    }

    @Test func doesNotCountFailedQuits() {
        let recorder = Recorder()
        recorder.succeeds = false

        let (count, _) = run([60], [proc(60)], recorder: recorder)

        #expect(count == 0)
    }

    @Test func theDefaultQuitterSendsSIGTERM() {
        final class Sent: @unchecked Sendable { var calls: [(Int32, Int32)] = [] }
        let sent = Sent()
        let quitter = SignalQuitter { pid, signal in
            sent.calls.append((pid, signal))
            return 0
        }

        #expect(quitter.quit(proc(70)))
        #expect(sent.calls.map(\.0) == [70])
        #expect(sent.calls.map(\.1) == [SIGTERM])
    }

    /// A real child started by the test itself (a copy of `sleep` outside the system folders).
    @Test func terminatesARealChildOfTheTest() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("spare-term-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("spare-test-sleep")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: copy.path)
        // A moved system binary loses its valid signature and the kernel would kill it: sign the copy ad hoc.
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", copy.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        try #require(sign.terminationStatus == 0, "codesign failed with status \(sign.terminationStatus): the test cannot prepare its child")

        let child = Process()
        child.executableURL = copy
        child.arguments = ["60"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }

        let pid = child.processIdentifier
        let real = ProcessLister.executablePath(ofPid: pid) ?? copy.path
        let listed = RunningProcess(pid: pid, uid: getuid(), rssBytes: 1, executablePath: real, commandLine: real,
                                    appBundlePath: nil, appBundleID: nil, name: "spare-test-sleep")

        let count = ProcessTerminator.terminate(
            consumer([pid]), processes: [listed], currentUID: getuid(), ownPID: ProcessInfo.processInfo.processIdentifier)

        #expect(count == 1)
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGTERM)
    }
}
