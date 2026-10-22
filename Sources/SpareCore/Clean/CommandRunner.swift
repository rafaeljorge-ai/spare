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
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult
}

/// Runs developer tools even from a GUI app, whose PATH is minimal.
public struct SystemCommandRunner: CommandRunning {
    public let searchPaths: [String]

    public init(home: URL, searchPaths: [String]? = nil) {
        self.searchPaths = searchPaths ?? [
            "/opt/homebrew/bin", "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            "/usr/bin", "/bin",
        ]
    }

    public func resolve(_ executable: String) -> String? {
        let fm = FileManager.default
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(executable)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return loginShellLookup(executable)
    }

    /// Falls back to the user's login shell PATH (nvm, asdf, mise...).
    func loginShellLookup(_ executable: String) -> String? {
        guard executable.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(executable)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        guard let path = resolve(executable) else { throw CommandError.notFound(executable) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var variables = ProcessInfo.processInfo.environment
        let toolDir = (path as NSString).deletingLastPathComponent
        variables["PATH"] = ([toolDir] + searchPaths).joined(separator: ":")
        process.environment = variables
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
