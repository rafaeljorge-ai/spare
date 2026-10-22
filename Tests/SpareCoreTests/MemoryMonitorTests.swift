import Foundation
import Testing
@testable import SpareCore

@Suite struct MemoryMonitorTests {
    func proc(_ pid: Int32, uid: UInt32 = 501, mb: Int64, path: String, app: String? = nil, name: String) -> RunningProcess {
        RunningProcess(pid: pid, uid: uid, rssBytes: mb * 1_000_000, executablePath: path, commandLine: path,
                       appBundlePath: app, appBundleID: app.map { _ in "com.example.\(name)" }, name: name)
    }

    @Test func snapshotIsSane() {
        let snapshot = MemoryMonitor.snapshot()

        #expect(snapshot.totalBytes == Int64(ProcessInfo.processInfo.physicalMemory))
        #expect(snapshot.usedBytes > 0)
        #expect(snapshot.usedBytes <= snapshot.totalBytes)
        #expect((0...1).contains(snapshot.usedFraction))
    }

    @Test func kernelLevelsMap() {
        #expect(MemoryMonitor.level(fromKernelValue: 1) == .normal)
        #expect(MemoryMonitor.level(fromKernelValue: 2) == .warning)
        #expect(MemoryMonitor.level(fromKernelValue: 4) == .critical)
        #expect(MemoryMonitor.level(fromKernelValue: 0) == .normal)
    }

    @Test func groupsHelpersUnderTheirAppAndSortsBySize() {
        let processes = [
            proc(11, mb: 300, path: "/Applications/Chrome.app/Contents/MacOS/Chrome", app: "/Applications/Chrome.app", name: "Chrome"),
            proc(12, mb: 500, path: "/Applications/Chrome.app/Contents/Frameworks/H.app/Contents/MacOS/H", app: "/Applications/Chrome.app", name: "Chrome"),
            proc(3, mb: 600, path: "/opt/homebrew/bin/node", name: "node"),
            proc(4, mb: 50, path: "/opt/homebrew/bin/python3", name: "python3"),
        ]

        let top = MemoryMonitor.topConsumers(processes: processes, currentUID: 501, ownPID: 999, limit: 15)

        #expect(top.map(\.name) == ["Chrome", "node", "python3"])
        #expect(top[0].bytes == 800_000_000)
        #expect(Set(top[0].pids) == [11, 12])
        #expect(top[0].isApp)
        #expect(!top[1].isApp)
    }

    @Test func excludesOtherUsersSystemBinariesAndItself() {
        let processes = [
            proc(1, uid: 0, mb: 900, path: "/usr/sbin/mds", name: "mds"),
            proc(2, mb: 900, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                 app: "/System/Library/CoreServices/Finder.app", name: "Finder"),
            proc(3, mb: 900, path: "/usr/libexec/trustd", name: "trustd"),
            proc(999, mb: 900, path: "/Applications/Spare.app/Contents/MacOS/Spare", app: "/Applications/Spare.app", name: "Spare"),
            proc(5, mb: 10, path: "/opt/homebrew/bin/node", name: "node"),
        ]

        let top = MemoryMonitor.topConsumers(processes: processes, currentUID: 501, ownPID: 999, limit: 15)

        #expect(top.map(\.name) == ["node"])
    }

    @Test func respectsTheLimit() {
        let processes = (1...20).map { proc(Int32($0), mb: Int64($0), path: "/opt/bin/p\($0)", name: "p\($0)") }

        #expect(MemoryMonitor.topConsumers(processes: processes, currentUID: 501, ownPID: 999, limit: 15).count == 15)
    }

    @Test func neverListsLaunchdOrThePIDOne() {
        let processes = [proc(1, mb: 900, path: "/opt/odd/launchd-clone", name: "odd"),
                         proc(7, mb: 1, path: "/opt/bin/ok", name: "ok")]

        let top = MemoryMonitor.topConsumers(processes: processes, currentUID: 501, ownPID: 999, limit: 15)

        #expect(top.map(\.name) == ["ok"])
    }

    @Test func ownBundleHelpersAreExcludedToo() {
        let processes = [
            proc(998, mb: 100, path: "/Applications/Spare.app/Contents/Helpers/h", app: "/Applications/Spare.app", name: "Spare"),
            proc(999, mb: 100, path: "/Applications/Spare.app/Contents/MacOS/Spare", app: "/Applications/Spare.app", name: "Spare"),
        ]

        #expect(MemoryMonitor.topConsumers(processes: processes, currentUID: 501, ownPID: 999, limit: 15).isEmpty)
    }

    @Test func readsTheBundleIDOnlyForTheLargestConsumers() {
        let processes = (1...5).map {
            proc(Int32($0 + 10), mb: Int64($0) * 10, path: "/Applications/A\($0).app/Contents/MacOS/a", app: "/Applications/A\($0).app", name: "A\($0)")
        }.map { p -> RunningProcess in var q = p; q.appBundleID = nil; return q }
        final class Asked: @unchecked Sendable { var paths: [String] = [] }
        let asked = Asked()

        let top = MemoryMonitor.topConsumers(processes: processes, currentUID: 501, ownPID: 999, limit: 2) { path in
            asked.paths.append(path)
            return "id." + (path as NSString).lastPathComponent
        }

        #expect(top.map(\.name) == ["A5", "A4"])
        #expect(top.map(\.appBundleID) == ["id.A5.app", "id.A4.app"])
        #expect(asked.paths.count == 2)
    }
}
