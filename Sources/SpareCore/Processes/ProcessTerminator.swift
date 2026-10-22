import Darwin
import Foundation

public enum ProcessTerminator {
    /// Asks the consumer's processes to quit with SIGTERM (never SIGKILL). Only the user's own processes
    /// qualify: never system binaries, the PID 1 or Spare itself. Right before signaling, the live
    /// executable path must still match the listing (guards against a recycled pid). Returns how many
    /// signals were delivered.
    @discardableResult
    public static func terminate(
        _ consumer: MemoryConsumer, processes: [RunningProcess], currentUID: UInt32, ownPID: Int32,
        currentPath: (Int32) -> String? = { ProcessLister.executablePath(ofPid: $0) },
        send: (Int32, Int32) -> Int32 = { kill($0, $1) }
    ) -> Int {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let ownBundle = byPID[ownPID]?.appBundlePath
        var signaled = 0
        for pid in consumer.pids {
            guard pid > 1, pid != ownPID, let process = byPID[pid], process.uid == currentUID,
                  !MemoryMonitor.isSystemPath(process.executablePath),
                  ownBundle == nil || process.appBundlePath != ownBundle,
                  let live = currentPath(pid), live == process.executablePath
            else { continue }
            if send(pid, SIGTERM) == 0 { signaled += 1 }
        }
        return signaled
    }
}
