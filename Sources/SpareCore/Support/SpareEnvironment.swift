import Foundation

/// Everything the engine needs from the outside world. Tests replace each piece.
public struct SpareEnvironment: Sendable {
    public var home: URL
    public var projectRoots: [URL]
    public var projectIdleDays: Int
    public var now: @Sendable () -> Date
    public var diskSpace: @Sendable (URL) -> DiskSpace?
    public var processes: @Sendable () -> [RunningProcess]

    public init(
        home: URL,
        projectRoots: [URL] = [],
        projectIdleDays: Int = 30,
        now: @escaping @Sendable () -> Date = { Date() },
        diskSpace: @escaping @Sendable (URL) -> DiskSpace? = { DiskMonitor.space(at: $0) },
        processes: @escaping @Sendable () -> [RunningProcess] = { [] }
    ) {
        self.home = home
        self.projectRoots = projectRoots
        self.projectIdleDays = projectIdleDays
        self.now = now
        self.diskSpace = diskSpace
        self.processes = processes
    }

    /// Real environment for the CLI and the app.
    public static func live(home: URL) -> SpareEnvironment {
        let resolved = home.resolvingSymlinksInPath()
        return SpareEnvironment(home: resolved, projectRoots: ProjectScanner.defaultRoots(home: resolved),
                          processes: { ProcessLister.live() })
    }
}
