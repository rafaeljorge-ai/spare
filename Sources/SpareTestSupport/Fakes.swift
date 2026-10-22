import Foundation
import SpareCore

/// Trash that is a plain folder (never the user's real Trash).
public typealias FolderTrash = DirectoryTrash

/// Records commands instead of running them.
public final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    public var missing: Set<String>
    public var exitCode: Int32

    public init(missing: Set<String> = [], exitCode: Int32 = 0) {
        self.missing = missing
        self.exitCode = exitCode
    }

    public var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        if missing.contains(executable) { throw CommandError.notFound(executable) }
        lock.lock()
        recorded.append(([executable] + arguments).joined(separator: " "))
        lock.unlock()
        return CommandResult(exitCode: exitCode, output: exitCode == 0 ? "ok" : "boom")
    }
}

/// Records signals instead of sending them (tests never signal a real process).
public final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(Int32, Int32)] = []

    public init() {}

    public var sent: [(Int32, Int32)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    public func send(_ pid: Int32, _ signal: Int32) -> Int32 {
        lock.lock()
        recorded.append((pid, signal))
        lock.unlock()
        return 0
    }
}
