import Foundation

public struct RunningProcess: Codable, Sendable, Hashable {
    public let pid: Int32
    public let uid: UInt32
    public let rssBytes: Int64
    public let executablePath: String
    public let commandLine: String
    /// Outermost `.app` bundle containing the executable, if any.
    public let appBundlePath: String?
    public var appBundleID: String?
    /// App name for app processes (helpers included), else the executable file name.
    public let name: String
    /// Current working directory, when it could be read.
    public var cwd: String?

    public init(pid: Int32, uid: UInt32, rssBytes: Int64, executablePath: String, commandLine: String,
                appBundlePath: String?, appBundleID: String?, name: String, cwd: String? = nil) {
        self.pid = pid
        self.uid = uid
        self.rssBytes = rssBytes
        self.executablePath = executablePath
        self.commandLine = commandLine
        self.appBundlePath = appBundlePath
        self.appBundleID = appBundleID
        self.name = name
        self.cwd = cwd
    }

    /// Name of the script for interpreter-run tools: `node /x/bin/npm install` -> "npm".
    public var scriptName: String? {
        let tokens = commandLine.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count > 1 else { return nil }
        return (String(tokens[1]) as NSString).lastPathComponent
    }

    public var executableName: String {
        (executablePath as NSString).lastPathComponent
    }
}
