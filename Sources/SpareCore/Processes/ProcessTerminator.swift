import Darwin
import Foundation

/// How one process is asked to quit. The default sends SIGTERM; the app layer can inject a graceful quit
/// for apps with a bundle (`NSRunningApplication.terminate()`, which lets "Save changes?" appear).
public protocol ProcessQuitter: Sendable {
    /// True when the request was delivered.
    func quit(_ process: RunningProcess) -> Bool
}

/// SIGTERM (never SIGKILL) to the process pid.
public struct SignalQuitter: ProcessQuitter {
    private let send: @Sendable (Int32, Int32) -> Int32

    public init(send: @escaping @Sendable (Int32, Int32) -> Int32 = { kill($0, $1) }) {
        self.send = send
    }

    public func quit(_ process: RunningProcess) -> Bool {
        send(process.pid, SIGTERM) == 0
    }
}

public enum ProcessTerminator {
    public static let spareBundleID = "ai.rafaeljorge.spare"

    /// Asks the processes of one Memory-screen row to quit, by pid, never by name. Only the user's own
    /// processes qualify. Refused: system binaries (judged by the live `proc_pidpath`, not the listing),
    /// pid 1, Spare itself (pid, bundle id or name) and every ancestor of the current process (terminal and
    /// shell). A pid whose live executable differs from the listing (recycled) or that is gone is skipped.
    /// Returns how many requests were delivered.
    @discardableResult
    public static func terminate(
        _ consumer: MemoryConsumer, processes: [RunningProcess], currentUID: UInt32, ownPID: Int32,
        ancestors: Set<Int32>? = nil,
        currentPath: (Int32) -> String? = { ProcessLister.executablePath(ofPid: $0) },
        bundleID: (String) -> String? = { Bundle(path: $0)?.bundleIdentifier },
        quitter: any ProcessQuitter = SignalQuitter()
    ) -> Int {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let blocked = ancestors ?? Self.ancestors(of: ownPID)
        let ownBundle = byPID[ownPID]?.appBundlePath
        var delivered = 0
        for pid in consumer.pids {
            guard pid > 1, pid != ownPID, !blocked.contains(pid), let process = byPID[pid],
                  process.uid == currentUID, let live = currentPath(pid),
                  !MemoryMonitor.isSystemPath(live), !MemoryMonitor.isSystemPath(process.executablePath),
                  !process.executablePath.hasPrefix("/") || live == process.executablePath,
                  !isSpare(process, livePath: live, ownBundle: ownBundle, bundleID: bundleID)
            else { continue }
            if quitter.quit(process) { delivered += 1 }
        }
        return delivered
    }

    static func isSpare(
        _ process: RunningProcess, livePath: String, ownBundle: String?, bundleID: (String) -> String?
    ) -> Bool {
        let liveApp = ProcessLister.outermostAppPath(in: livePath)
        let appPath = process.appBundlePath ?? liveApp
        if let appPath, appPath == ownBundle { return true }
        if process.appBundleID == spareBundleID { return true }
        if let appPath, bundleID(appPath) == spareBundleID { return true }
        let names = [process.name, liveApp.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension },
                     (livePath as NSString).lastPathComponent]
        return names.contains { $0?.lowercased() == "spare" }
    }

    /// Parent chain of `pid` (parent, grandparent, ... up to but excluding launchd).
    public static func ancestors(
        of pid: Int32, parent: (Int32) -> Int32? = { parentPID(of: $0) }
    ) -> Set<Int32> {
        var result: Set<Int32> = []
        var current = pid
        while let next = parent(current), next > 1, next != current, !result.contains(next) {
            result.insert(next)
            current = next
        }
        return result
    }

    public static func parentPID(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(bitPattern: info.pbi_ppid)
    }
}
