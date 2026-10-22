import Foundation
import Testing
@testable import SpareCore

@Suite struct ProcessTerminatorTests {
    final class Signals: @unchecked Sendable {
        var sent: [(Int32, Int32)] = []
    }

    func proc(_ pid: Int32, uid: UInt32 = 501, path: String = "/opt/homebrew/bin/node", app: String? = nil) -> RunningProcess {
        RunningProcess(pid: pid, uid: uid, rssBytes: 1, executablePath: path, commandLine: path,
                       appBundlePath: app, appBundleID: nil, name: "x")
    }

    func consumer(_ pids: [Int32]) -> MemoryConsumer {
        MemoryConsumer(id: "x", name: "x", bytes: 2, pids: pids, appBundleID: nil, isApp: false)
    }

    @Test func sendsSIGTERMOnlyToAllowedProcesses() {
        let signals = Signals()
        let processes = [proc(10), proc(11, uid: 0), proc(1, path: "/sbin/launchd")]

        let count = ProcessTerminator.terminate(
            consumer([10, 11, 1, 999]), processes: processes, currentUID: 501, ownPID: 999,
            currentPath: { pid in processes.first { $0.pid == pid }?.executablePath }
        ) { pid, signal in
            signals.sent.append((pid, signal))
            return 0
        }

        #expect(count == 1)
        #expect(signals.sent.map(\.0) == [10])
        #expect(signals.sent.map(\.1) == [SIGTERM])
    }

    @Test func refusesSystemPathsAndSpareItself() {
        let signals = Signals()
        let processes = [
            proc(20, path: "/usr/libexec/trustd"),
            proc(21, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
            proc(999, path: "/Applications/Spare.app/Contents/MacOS/Spare"),
            proc(22, path: "/opt/homebrew/bin/node"),
        ]

        let count = ProcessTerminator.terminate(
            consumer([20, 21, 999, 22]), processes: processes, currentUID: 501, ownPID: 999,
            currentPath: { pid in processes.first { $0.pid == pid }?.executablePath }
        ) { pid, signal in
            signals.sent.append((pid, signal))
            return 0
        }

        #expect(count == 1)
        #expect(signals.sent.map(\.0) == [22])
    }

    @Test func skipsAProcessWhoseExecutableChangedSinceTheListing() {
        let signals = Signals()
        let processes = [proc(30), proc(31)]

        // Pid 30 was recycled by another program; pid 31 is gone.
        let count = ProcessTerminator.terminate(
            consumer([30, 31]), processes: processes, currentUID: 501, ownPID: 999,
            currentPath: { $0 == 30 ? "/opt/other/thing" : nil }
        ) { pid, signal in
            signals.sent.append((pid, signal))
            return 0
        }

        #expect(count == 0)
        #expect(signals.sent.isEmpty)
    }

    @Test func doesNotCountFailedSignals() {
        let processes = [proc(40)]

        let count = ProcessTerminator.terminate(
            consumer([40]), processes: processes, currentUID: 501, ownPID: 999,
            currentPath: { _ in "/opt/homebrew/bin/node" }
        ) { _, _ in -1 }

        #expect(count == 0)
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
