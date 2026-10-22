import Darwin
import Foundation

/// Everything the engine needs from the outside world. Tests replace each piece.
public struct SpareEnvironment: Sendable {
    public var home: URL
    public var projectRoots: [URL]
    public var projectIdleDays: Int
    public var now: @Sendable () -> Date
    public var diskSpace: @Sendable (URL) -> DiskSpace?
    /// Throws when the running processes could not be listed.
    public var processes: @Sendable () throws -> [RunningProcess]
    /// Memory totals and pressure; nil when they cannot be read.
    public var memory: @Sendable () -> MemorySnapshot?
    /// Light listing for the Memory screen: `ps` only, no `lsof`, no bundle lookups. Throws when `ps` fails.
    public var memoryProcesses: @Sendable () throws -> [RunningProcess]
    /// Where `trash` actions send items (tests inject a plain folder, never the real Trash).
    public var trash: any TrashService
    public var commandRunner: any CommandRunning

    public init(
        home: URL,
        projectRoots: [URL] = [],
        projectIdleDays: Int = 30,
        now: @escaping @Sendable () -> Date = { Date() },
        diskSpace: @escaping @Sendable (URL) -> DiskSpace? = { DiskMonitor.space(at: $0) },
        processes: @escaping @Sendable () throws -> [RunningProcess] = { [] },
        memory: @escaping @Sendable () -> MemorySnapshot? = { MemoryMonitor.snapshot() },
        memoryProcesses: @escaping @Sendable () throws -> [RunningProcess] = { try ProcessLister.liveLight() },
        trash: any TrashService = SystemTrash(),
        commandRunner: (any CommandRunning)? = nil
    ) {
        self.home = home
        self.projectRoots = projectRoots
        self.projectIdleDays = projectIdleDays
        self.now = now
        self.diskSpace = diskSpace
        self.processes = processes
        self.memory = memory
        self.memoryProcesses = memoryProcesses
        self.trash = trash
        self.commandRunner = commandRunner ?? SystemCommandRunner(home: home)
    }

    /// Where Spare keeps its own files (history, settings): `<home>/Library/Application Support/Spare`.
    public var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/Spare", isDirectory: true)
    }

    /// Real environment for the CLI and the app.
    public static func live(home: URL) -> SpareEnvironment {
        let resolved = home.resolvingSymlinksInPath()
        let runner = SystemCommandRunner(
            home: resolved, disabled: SystemCommandRunner.toolCommandsDisabled(ProcessInfo.processInfo.environment))
        return SpareEnvironment(home: resolved, projectRoots: ProjectScanner.defaultRoots(home: resolved),
                          processes: { try ProcessLister.live() }, commandRunner: runner)
    }

    /// Real environment honoring the user's settings (project folders and idle days).
    public static func live(home: URL, settings: SpareSettings) -> SpareEnvironment {
        var environment = live(home: home)
        environment.projectRoots = settings.projectRootPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        environment.projectIdleDays = settings.projectIdleDays
        return environment
    }
}
