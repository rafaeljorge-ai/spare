# Task 8: Memory

Memory pressure and used memory, the apps and processes using the most (helpers grouped under their app), and a safe terminator. `spare memory` and `spare status` show it.

**Files:**
- Create: `Sources/SpareCore/Memory/MemoryMonitor.swift`, `Sources/SpareCore/Processes/ProcessTerminator.swift`
- Modify: `Sources/SpareCLI/SpareCLI.swift` (`memory`, `status` gains memory)
- Test: `Tests/SpareCoreTests/MemoryMonitorTests.swift`, `Tests/SpareCoreTests/ProcessTerminatorTests.swift`, `Tests/SpareCLITests/MemoryCommandTests.swift`, update `StatusCommandTests.swift`
- Modify: `Sources/SpareCore/Support/SpareEnvironment.swift` (add `memory`), `Sources/SpareTestSupport/TestEnvironment.swift`
- Modify: `README.md`, `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `RunningProcess`, `ProcessLister`, `SpareEnvironment.processes`.
- Produces:
  - `public enum MemoryPressureLevel: String, Codable, Sendable { case normal, warning, critical }`
  - `public struct MemorySnapshot: Codable, Sendable, Equatable { totalBytes: Int64; usedBytes: Int64; compressedBytes: Int64; level: MemoryPressureLevel; usedFraction: Double }`
  - `public struct MemoryConsumer: Codable, Sendable, Identifiable, Hashable { id: String; name: String; bytes: Int64; pids: [Int32]; appBundleID: String?; isApp: Bool }`
  - `MemoryMonitor.snapshot() -> MemorySnapshot`, `MemoryMonitor.level(fromKernelValue: Int32) -> MemoryPressureLevel`, `MemoryMonitor.topConsumers(processes:currentUID:ownPID:limit:) -> [MemoryConsumer]`
  - `ProcessTerminator.terminate(_ consumer: MemoryConsumer, processes: [RunningProcess], currentUID: UInt32, ownPID: Int32, send: (Int32, Int32) -> Int32 = kill) -> Int` (number of processes signaled with `SIGTERM`)
  - `SpareEnvironment.memory: @Sendable () -> MemorySnapshot?` (default `{ MemoryMonitor.snapshot() }`; test env returns a fixed snapshot)
  - CLI `spare memory [--json]`; `spare status --json` now `{ "disk": ..., "memory": ... }`

- [ ] **Step 1: Write the failing tests**

`Tests/SpareCoreTests/MemoryMonitorTests.swift`:

```swift
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
            proc(1, mb: 300, path: "/Applications/Chrome.app/Contents/MacOS/Chrome", app: "/Applications/Chrome.app", name: "Chrome"),
            proc(2, mb: 500, path: "/Applications/Chrome.app/Contents/Frameworks/H.app/Contents/MacOS/H", app: "/Applications/Chrome.app", name: "Chrome"),
            proc(3, mb: 600, path: "/opt/homebrew/bin/node", name: "node"),
            proc(4, mb: 50, path: "/opt/homebrew/bin/python3", name: "python3"),
        ]

        let top = MemoryMonitor.topConsumers(processes: processes, currentUID: 501, ownPID: 999, limit: 15)

        #expect(top.map(\.name) == ["Chrome", "node", "python3"])
        #expect(top[0].bytes == 800_000_000)
        #expect(Set(top[0].pids) == [1, 2])
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
}
```

`Tests/SpareCoreTests/ProcessTerminatorTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore

@Suite struct ProcessTerminatorTests {
    final class Signals: @unchecked Sendable {
        var sent: [(Int32, Int32)] = []
    }

    let processes = [
        RunningProcess(pid: 10, uid: 501, rssBytes: 1, executablePath: "/opt/homebrew/bin/node", commandLine: "node",
                       appBundlePath: nil, appBundleID: nil, name: "node"),
        RunningProcess(pid: 11, uid: 0, rssBytes: 1, executablePath: "/opt/homebrew/bin/node", commandLine: "node",
                       appBundlePath: nil, appBundleID: nil, name: "node"),
        RunningProcess(pid: 1, uid: 501, rssBytes: 1, executablePath: "/sbin/launchd", commandLine: "launchd",
                       appBundlePath: nil, appBundleID: nil, name: "launchd"),
    ]

    @Test func sendsSIGTERMOnlyToAllowedProcesses() {
        let signals = Signals()
        let consumer = MemoryConsumer(id: "/opt/homebrew/bin/node", name: "node", bytes: 2, pids: [10, 11, 1, 999],
                                      appBundleID: nil, isApp: false)

        let count = ProcessTerminator.terminate(consumer, processes: processes, currentUID: 501, ownPID: 999) { pid, signal in
            signals.sent.append((pid, signal))
            return 0
        }

        #expect(count == 1)
        #expect(signals.sent.map(\.0) == [10])
        #expect(signals.sent.map(\.1) == [SIGTERM])
    }
}
```

`Tests/SpareCLITests/MemoryCommandTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct MemoryCommandTests {
    @Test func memoryJSONHasSnapshotAndConsumers() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let node = RunningProcess(pid: 10, uid: getuid(), rssBytes: 5_000_000, executablePath: "/opt/homebrew/bin/node",
                                  commandLine: "node", appBundlePath: nil, appBundleID: nil, name: "node")
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url, processes: [node]), write: output.write)
            .run(["memory", "--json"])

        #expect(code == 0)
        struct Out: Decodable { let snapshot: MemorySnapshot; let consumers: [MemoryConsumer] }
        let decoded = try JSONDecoder().decode(Out.self, from: Data(output.text.utf8))
        #expect(decoded.consumers.map(\.name) == ["node"])
        #expect(decoded.snapshot.level == .normal)
    }
}
```

In `StatusCommandTests.statusJSONReportsDiskSpace`, decode `struct Status: Decodable { let disk: DiskSpace; let memory: MemorySnapshot? }` and expect `status.memory != nil`.

Run: `swift test` → FAIL.

- [ ] **Step 2: Implement**

`Sources/SpareCore/Memory/MemoryMonitor.swift`:

```swift
import Darwin
import Foundation

public enum MemoryPressureLevel: String, Codable, Sendable {
    case normal, warning, critical
}

public struct MemorySnapshot: Codable, Sendable, Equatable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let compressedBytes: Int64
    public let level: MemoryPressureLevel

    public init(totalBytes: Int64, usedBytes: Int64, compressedBytes: Int64, level: MemoryPressureLevel) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.level = level
    }

    public var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }
}

public struct MemoryConsumer: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let bytes: Int64
    public let pids: [Int32]
    public let appBundleID: String?
    public let isApp: Bool

    public init(id: String, name: String, bytes: Int64, pids: [Int32], appBundleID: String?, isApp: Bool) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.pids = pids
        self.appBundleID = appBundleID
        self.isApp = isApp
    }
}

public enum MemoryMonitor {
    static let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"]

    /// Used = app memory + wired + compressed (what Activity Monitor calls "Memory Used").
    public static func snapshot() -> MemorySnapshot {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = Int64(getpagesize())
        var used: Int64 = 0
        var compressed: Int64 = 0
        if result == KERN_SUCCESS {
            let appPages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            compressed = Int64(stats.compressor_page_count) * page
            used = (appPages + Int64(stats.wire_count)) * page + compressed
        }
        return MemorySnapshot(totalBytes: total, usedBytes: min(max(used, 0), total),
                              compressedBytes: compressed, level: kernelLevel())
    }

    static func kernelLevel() -> MemoryPressureLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return .normal }
        return level(fromKernelValue: value)
    }

    public static func level(fromKernelValue value: Int32) -> MemoryPressureLevel {
        switch value {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
    }

    public static func topConsumers(
        processes: [RunningProcess], currentUID: UInt32, ownPID: Int32, limit: Int = 15
    ) -> [MemoryConsumer] {
        let eligible = processes.filter { process in
            process.uid == currentUID && process.pid != ownPID
                && !systemPrefixes.contains { process.executablePath.hasPrefix($0) }
        }
        let groups = Dictionary(grouping: eligible) { $0.appBundlePath ?? $0.executablePath }
        return groups.map { key, members in
            MemoryConsumer(
                id: key, name: members[0].name, bytes: members.reduce(0) { $0 + $1.rssBytes },
                pids: members.map(\.pid).sorted(), appBundleID: members.first { $0.appBundleID != nil }?.appBundleID,
                isApp: members[0].appBundlePath != nil)
        }
        .sorted { $0.bytes > $1.bytes }
        .prefix(limit)
        .map { $0 }
    }
}
```

`Sources/SpareCore/Processes/ProcessTerminator.swift`:

```swift
import Darwin
import Foundation

public enum ProcessTerminator {
    /// Sends SIGTERM (never SIGKILL) to the consumer's processes that belong to the user,
    /// are not system binaries, not launchd and not Spare itself.
    @discardableResult
    public static func terminate(
        _ consumer: MemoryConsumer, processes: [RunningProcess], currentUID: UInt32, ownPID: Int32,
        send: (Int32, Int32) -> Int32 = { kill($0, $1) }
    ) -> Int {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var signaled = 0
        for pid in consumer.pids {
            guard pid > 1, pid != ownPID, let process = byPID[pid], process.uid == currentUID,
                  !MemoryMonitor.systemPrefixes.contains(where: { process.executablePath.hasPrefix($0) })
            else { continue }
            if send(pid, SIGTERM) == 0 { signaled += 1 }
        }
        return signaled
    }
}
```

`SpareEnvironment`: add `public var memory: @Sendable () -> MemorySnapshot?` (init default `{ MemoryMonitor.snapshot() }`). Test environment passes `memory: { MemorySnapshot(totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, compressedBytes: 1_000_000_000, level: .normal) }`.

CLI: `StatusOutput` gains `let memory: MemorySnapshot?` (text mode adds `Memory: <used> of <total> (<level>)`). New command:

```swift
    func memory(json: Bool) -> Int32 {
        let snapshot = environment.memory()
        let consumers = MemoryMonitor.topConsumers(
            processes: environment.processes(), currentUID: getuid(),
            ownPID: ProcessInfo.processInfo.processIdentifier)
        if json {
            write(Self.encode(MemoryOutput(snapshot: snapshot, consumers: consumers)))
            return 0
        }
        if let snapshot {
            write("Memory: \(ByteFormat.string(snapshot.usedBytes)) of \(ByteFormat.string(snapshot.totalBytes)) (\(snapshot.level.rawValue))")
        }
        consumers.forEach { write("\(ByteFormat.string($0.bytes))  \($0.name)  pids: \($0.pids.map(String.init).joined(separator: ","))") }
        return 0
    }
```

with `struct MemoryOutput: Codable { let snapshot: MemorySnapshot?; let consumers: [MemoryConsumer] }`. Usage line: `spare memory [--json]   Memory pressure and top consumers (approximate, shared memory counted per process)`.

- [ ] **Step 3: Run, docs, gates, commit**

`swift test` → PASS. Smoke: `swift run spare memory`. README, CHANGELOG `Added: memory snapshot and top consumers (spare memory)`, STATUS. `scripts/check.sh` green.

```bash
git add -A
git commit -m "feat(core): add memory monitor and consumers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
