import Foundation

public protocol TrashService: Sendable {
    /// Moves to the Trash; returns where the item ended up.
    func moveToTrash(_ url: URL) throws -> URL
    /// Moves an item back. Throws if something already exists at `original`.
    func restore(_ trashed: URL, to original: URL) throws
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
        let fm = FileManager.default
        guard !fm.fileExists(atPath: original.path) else { throw CocoaError(.fileWriteFileExists) }
        guard fm.fileExists(atPath: trashed.path) else { throw CocoaError(.fileNoSuchFile) }
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: trashed, to: original)
    }
}
