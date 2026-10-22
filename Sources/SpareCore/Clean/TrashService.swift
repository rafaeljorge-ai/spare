import Foundation

public protocol TrashService: Sendable {
    /// Moves to the Trash; returns where the item ended up.
    func moveToTrash(_ url: URL) throws -> URL
    /// Moves an item back. Throws if anything (even a dangling symlink) already exists at `original`.
    func restore(_ trashed: URL, to original: URL) throws
    /// True when `url` is a direct child of this Trash (not a symlink to somewhere else).
    func isInTrash(_ url: URL) -> Bool
    /// Permanently deletes one item that is directly inside this Trash. Never follows a symlink and
    /// throws for anything that is not a direct child of the Trash.
    func purge(_ trashed: URL) throws
}

/// Shared file operations for the Trash implementations.
enum TrashFiles {
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// `device:inode` of the path itself (a symlink is not followed), nil when it does not exist.
    static func identity(of path: String) -> String? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return "\(info.st_dev):\(info.st_ino)"
    }

    static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    static func restore(_ trashed: URL, to original: URL) throws {
        let fm = FileManager.default
        guard !exists(original.path) else { throw CocoaError(.fileWriteFileExists) }
        guard exists(trashed.path) else { throw CocoaError(.fileNoSuchFile) }
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: trashed, to: original)
    }

    /// `removeItem` unlinks a symlink instead of following it, and never follows links inside folders.
    static func purge(_ trashed: URL, in trash: some TrashService) throws {
        guard trash.isInTrash(trashed), exists(trashed.path) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.removeItem(at: trashed)
    }
}

public struct SystemTrash: TrashService {
    public init() {}

    public func moveToTrash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let result = resulting as URL? else { throw CocoaError(.fileWriteUnknown) }
        return result
    }

    public func restore(_ trashed: URL, to original: URL) throws {
        try TrashFiles.restore(trashed, to: original)
    }

    /// The user's `~/.Trash` or a volume's `.Trashes/<uid>`, as a real folder (not a symlink).
    public func isInTrash(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"),
              !url.pathComponents.contains(where: { $0 == ".." || $0 == "." })
        else { return false }
        let parent = url.deletingLastPathComponent()
        guard url.lastPathComponent != "/", TrashFiles.isDirectory(parent.path) else { return false }
        let ownTrash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        return parent.path == ownTrash || Self.isVolumeTrashChild(url, uid: getuid())
    }

    /// `<volume root>/.Trashes/<uid>/<item>`, where the volume root is `/` or `/Volumes/<name>`.
    static func isVolumeTrashChild(_ url: URL, uid: uid_t) -> Bool {
        let parts = url.pathComponents
        guard parts.first == "/" else { return false }
        let rest = Array(parts.dropFirst())
        let prefix: Int
        switch rest.first {
        case ".Trashes": prefix = 0
        case "Volumes": prefix = 2
        default: return false
        }
        guard rest.count == prefix + 3, prefix == 0 || !rest[1].isEmpty else { return false }
        return rest[prefix] == ".Trashes" && rest[prefix + 1] == String(uid) && !rest[prefix + 2].isEmpty
    }

    public func purge(_ trashed: URL) throws {
        try TrashFiles.purge(trashed, in: self)
    }
}

/// Trash that is a plain folder (tests and the fake-home QA, via `SPARE_TRASH_DIR`). Never the real Trash.
public struct DirectoryTrash: TrashService {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public func moveToTrash(_ url: URL) throws -> URL {
        let destination = folder.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    public func restore(_ trashed: URL, to original: URL) throws {
        try TrashFiles.restore(trashed, to: original)
    }

    public func isInTrash(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"),
              !url.pathComponents.contains(where: { $0 == ".." || $0 == "." })
        else { return false }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        return parent == folder.resolvingSymlinksInPath().path && url.lastPathComponent != "/"
    }

    public func purge(_ trashed: URL) throws {
        try TrashFiles.purge(trashed, in: self)
    }
}

public enum TrashFolder {
    /// The folder that stands in for the real Trash on a throwaway home: `SPARE_TRASH_DIR`, or
    /// `<home>/.Trash` when only `SPARE_HOME` is set. Nil on a real run (the system Trash).
    public static func override(variables: [String: String], home: URL) -> URL? {
        if let folder = variables["SPARE_TRASH_DIR"] { return URL(fileURLWithPath: folder, isDirectory: true) }
        if variables["SPARE_HOME"] != nil { return home.appendingPathComponent(".Trash", isDirectory: true) }
        return nil
    }
}
