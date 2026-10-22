import Foundation
import SpareCore

extension SpareEnvironment {
    /// Environment for tests: fake home, fixed disk numbers, no real side effects.
    /// Later tasks extend this with fake trash and command runner.
    public static func test(
        home: URL,
        projectRoots: [URL] = [],
        disk: DiskSpace? = DiskSpace(freeBytes: 10_000_000_000, totalBytes: 100_000_000_000),
        processes: [RunningProcess] = []
    ) -> SpareEnvironment {
        SpareEnvironment(
            home: home,
            projectRoots: projectRoots,
            diskSpace: { _ in disk },
            processes: { processes }
        )
    }
}
