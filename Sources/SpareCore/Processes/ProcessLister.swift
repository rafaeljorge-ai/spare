import Foundation

public enum ProcessLister {
    /// Parses `ps -axww -o pid=,uid=,rss=,comm=` and `ps -axww -o pid=,args=` output.
    /// `cwd` is optional `lsof -Fpn -d cwd` output (`p<pid>` lines followed by `n<path>` lines).
    public static func parse(comm: String, args: String, cwd: String = "") -> [RunningProcess] {
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
            let path = String(fields[3])
            guard path.hasPrefix("/") else { continue }
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

    public static func live() -> [RunningProcess] {
        let comm = run("/bin/ps", ["-axww", "-o", "pid=,uid=,rss=,comm="])
        let args = run("/bin/ps", ["-axww", "-o", "pid=,args="])
        // Working directories only for the user's own processes: that is all a cache can belong to.
        let cwd = run("/usr/sbin/lsof", ["-n", "-P", "-a", "-u", String(getuid()), "-d", "cwd", "-Fpn"])
        var bundleIDs: [String: String] = [:]
        return parse(comm: comm, args: args, cwd: cwd).map { process in
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

    static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
