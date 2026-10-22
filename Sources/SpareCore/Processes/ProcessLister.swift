import Darwin
import Foundation

public struct ProcessListingError: Error, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public enum ProcessLister {
    static let commandTimeout: TimeInterval = 5

    /// Parses `ps -axww -o pid=,uid=,rss=,comm=` and `ps -axww -o pid=,args=` output.
    /// `cwd` is optional `lsof -Fpn -d cwd` output (`p<pid>` lines followed by `n<path>` lines).
    /// Processes started through PATH report a bare `comm` (`node`, `cargo`); `resolvePath` finds their real
    /// executable, and when it cannot the bare name is kept. A process is never dropped for that.
    public static func parse(
        comm: String, args: String, cwd: String = "", resolvePath: (Int32) -> String? = { _ in nil }
    ) -> [RunningProcess] {
        var argsByPID: [Int32: String] = [:]
        for line in args.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            argsByPID[pid] = String(trimmed[space...].drop { $0 == " " })
        }
        let cwdByPID = parseWorkingDirectories(cwd)

        var result: [RunningProcess] = []
        for line in comm.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]), let uid = UInt32(fields[1]), let rssKB = Int64(fields[2])
            else { continue }
            var path = String(fields[3])
            if !path.hasPrefix("/"), let resolved = resolvePath(pid), resolved.hasPrefix("/") { path = resolved }
            let appPath = outermostAppPath(in: path)
            let name = appPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                ?? (path as NSString).lastPathComponent
            result.append(RunningProcess(
                pid: pid, uid: uid, rssBytes: rssKB * 1024, executablePath: path,
                commandLine: argsByPID[pid] ?? path, appBundlePath: appPath, appBundleID: nil, name: name,
                cwd: cwdByPID[pid]))
        }
        return result
    }

    static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var current: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    static func outermostAppPath(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// Real executable path of a pid (`proc_pidpath`), nil when it cannot be read.
    public static func executablePath(ofPid pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Throws when `ps` fails: an empty list must never be read as "nothing is running".
    /// A failing `lsof` only costs the working directories.
    public static func live(psPath: String = "/bin/ps", lsofPath: String = "/usr/sbin/lsof") throws -> [RunningProcess] {
        guard let comm = run(psPath, ["-axww", "-o", "pid=,uid=,rss=,comm="], timeout: commandTimeout),
              !comm.isEmpty,
              let args = run(psPath, ["-axww", "-o", "pid=,args="], timeout: commandTimeout)
        else { throw ProcessListingError(message: "Could not list running processes") }
        // Working directories only for the user's own processes: that is all a cache can belong to.
        // -b avoids blocking on stale network mounts, -w silences warnings.
        let cwd = run(lsofPath, ["-b", "-w", "-n", "-P", "-a", "-u", String(getuid()), "-d", "cwd", "-Fpn"],
                      timeout: commandTimeout) ?? ""
        var bundleIDs: [String: String] = [:]
        return parse(comm: comm, args: args, cwd: cwd, resolvePath: executablePath(ofPid:)).map { process in
            var copy = process
            if let appPath = process.appBundlePath {
                if bundleIDs[appPath] == nil {
                    bundleIDs[appPath] = Bundle(path: appPath)?.bundleIdentifier ?? ""
                }
                copy.appBundleID = bundleIDs[appPath].flatMap { $0.isEmpty ? nil : $0 }
            }
            return copy
        }
    }

    /// Light listing for the Memory screen: one `ps` call, no `lsof`, no bundle lookups (`appBundleID` and
    /// `cwd` stay nil). Throws when `ps` fails.
    public static func liveLight(psPath: String = "/bin/ps") throws -> [RunningProcess] {
        guard let comm = run(psPath, ["-axww", "-o", "pid=,uid=,rss=,comm="], timeout: commandTimeout), !comm.isEmpty
        else { throw ProcessListingError(message: "Could not list running processes") }
        return parse(comm: comm, args: "", resolvePath: executablePath(ofPid:))
    }

    /// Runs a tool and returns its standard output; nil when it cannot start or exceeds `timeout` seconds
    /// (it is then terminated). The exit status is ignored: `lsof` exits 1 on harmless warnings.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let watchdog = Watchdog(process)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { watchdog.fire() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return watchdog.finish() ? nil : String(decoding: data, as: UTF8.self)
    }
}

/// Terminates a process that overstays its welcome. `finish()` reports whether it had to.
private final class Watchdog: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var done = false
    private var fired = false

    init(_ process: Process) { self.process = process }

    func fire() {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        fired = true
        process.terminate()
    }

    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        done = true
        return fired
    }
}
