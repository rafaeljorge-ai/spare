import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public enum CommandError: Error, Equatable {
    case notFound(String)
    /// The tool ran past its time limit and was terminated.
    case timedOut(String)
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult
}

/// Runs developer tools even from a GUI app, whose PATH is minimal.
/// Tools never read from the terminal (stdin is empty) and never run forever.
public struct SystemCommandRunner: CommandRunning {
    public static let defaultLookupTimeout: TimeInterval = 5
    public static let defaultCommandTimeout: TimeInterval = 300

    public let searchPaths: [String]
    public let lookupTimeout: TimeInterval
    public let commandTimeout: TimeInterval
    /// Used when the tool is not in `searchPaths`. Tests inject one that never starts a shell.
    let fallbackLookup: @Sendable (String) -> String?

    public init(home: URL, searchPaths: [String]? = nil,
                lookupTimeout: TimeInterval = SystemCommandRunner.defaultLookupTimeout,
                commandTimeout: TimeInterval = SystemCommandRunner.defaultCommandTimeout,
                fallbackLookup: (@Sendable (String) -> String?)? = nil) {
        self.searchPaths = searchPaths ?? [
            "/opt/homebrew/bin", "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            "/usr/bin", "/bin",
        ]
        self.lookupTimeout = lookupTimeout
        self.commandTimeout = commandTimeout
        self.fallbackLookup = fallbackLookup ?? { Self.loginShellLookup($0, timeout: lookupTimeout) }
    }

    public func resolve(_ executable: String) -> String? {
        let fm = FileManager.default
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(executable)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return fallbackLookup(executable)
    }

    /// Falls back to the user's login shell PATH (nvm, asdf, mise...).
    static func loginShellLookup(_ executable: String, timeout: TimeInterval) -> String? {
        guard executable.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else { return nil }
        guard let result = try? execute("/bin/zsh", ["-lc", "command -v \(executable)"], environment: nil,
                                        mergeErrors: false, timeout: timeout, name: executable),
              let path = lastAbsolutePath(in: result.output),
              FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return path
    }

    /// Login shells may print banners before `command -v`: the answer is the last line that is a path.
    static func lastAbsolutePath(in output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
    }

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        guard let path = resolve(executable) else { throw CommandError.notFound(executable) }
        var variables = ProcessInfo.processInfo.environment
        let toolDir = (path as NSString).deletingLastPathComponent
        variables["PATH"] = ([toolDir] + searchPaths).joined(separator: ":")
        return try Self.execute(path, arguments, environment: variables, mergeErrors: true,
                                timeout: commandTimeout, name: executable)
    }

    /// Runs a process with empty stdin; terminates it (then kills it) when `timeout` passes.
    static func execute(_ path: String, _ arguments: [String], environment: [String: String]?,
                        mergeErrors: Bool, timeout: TimeInterval, name: String) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = mergeErrors ? pipe : FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        // Read on a side thread so a chatty tool never fills the pipe. The thread holds the pipe, so it
        // is safe to abandon it when a grandchild keeps the pipe open after the tool is gone.
        let collected = Collected()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
            }
            drained.signal()
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
        }
        _ = drained.wait(timeout: .now() + (timedOut ? 0.5 : 5))
        if timedOut { throw CommandError.timedOut(name) }
        return CommandResult(exitCode: process.terminationStatus, output: String(decoding: collected.data, as: UTF8.self))
    }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
