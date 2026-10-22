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
