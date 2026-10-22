import Foundation
import SpareCore

extension SpareEnvironment {
    /// Environment for tests: fake home, fixed disk numbers, a folder instead of the Trash and a
    /// recording command runner. No real side effects.
    public static func test(
        home: URL,
        projectRoots: [URL] = [],
        disk: DiskSpace? = DiskSpace(freeBytes: 10_000_000_000, totalBytes: 100_000_000_000),
        processes: [RunningProcess] = [],
        memory: MemorySnapshot? = MemorySnapshot(
            totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, compressedBytes: 1_000_000_000, level: .normal),
        signals: SignalRecorder = SignalRecorder(),
        commandRunner: any CommandRunning = RecordingCommandRunner(),
        processListingFails: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> SpareEnvironment {
        let trashFolder = home.deletingLastPathComponent()
            .appendingPathComponent(home.lastPathComponent + "-trash", isDirectory: true)
        return SpareEnvironment(
            home: home,
            projectRoots: projectRoots,
            now: now,
            diskSpace: { _ in disk },
            processes: {
                if processListingFails { throw ProcessListingError(message: "test") }
                return processes
            },
            memory: { memory },
            executablePath: { pid in processes.first { $0.pid == pid }?.executablePath },
            sendSignal: { signals.send($0, $1) },
            trash: FolderTrash(folder: trashFolder),
            commandRunner: commandRunner
        )
    }
}
