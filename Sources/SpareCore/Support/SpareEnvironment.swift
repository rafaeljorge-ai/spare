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
        trash: any TrashService = SystemTrash(),
        commandRunner: (any CommandRunning)? = nil
    ) {
        self.home = home
        self.projectRoots = projectRoots
        self.projectIdleDays = projectIdleDays
        self.now = now
        self.diskSpace = diskSpace
        self.processes = processes
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
        return SpareEnvironment(home: resolved, projectRoots: ProjectScanner.defaultRoots(home: resolved),
                          processes: { try ProcessLister.live() })
    }
}
