import Foundation

/// Collects CLI output lines in tests.
public final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    public init() {}

    public var write: @Sendable (String) -> Void {
        { [self] line in
            lock.lock()
            lines.append(line)
            lock.unlock()
        }
    }

    public var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
