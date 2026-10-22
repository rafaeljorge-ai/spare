import Foundation

/// A throwaway home folder under the system temp dir. Paths are symlink-resolved
/// (`/var` becomes `/private/var`) so comparisons with resolved paths match.
public struct TempHome: Sendable {
    public let url: URL

    public init() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        url = base.appendingPathComponent("spare-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func path(_ relativePath: String) -> URL {
        url.appendingPathComponent(relativePath)
    }

    @discardableResult
    public func file(_ relativePath: String, bytes: Int = 4096, modified: Date? = nil) throws -> URL {
        let file = path(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: file)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        return file
    }

    @discardableResult
    public func directory(_ relativePath: String, modified: Date? = nil) throws -> URL {
        let dir = path(relativePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: dir.path)
        }
        return dir
    }

    public func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relativePath).path)
    }

    /// Fake Trash used by `SpareEnvironment.test`, next to the home so it never touches the real one.
    public var trashFolder: URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-trash", isDirectory: true)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: trashFolder)
    }
}

public func daysAgo(_ days: Double) -> Date {
    Date().addingTimeInterval(-days * 86_400)
}
