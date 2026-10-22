import Foundation

public enum UndoFailureReason: String, Codable, Sendable, Hashable {
    /// Something already lives at the original path; Spare never overwrites.
    case destinationExists
    /// The item is no longer in the Trash (emptied or moved by the user).
    case missingInTrash
    /// The Trash path now holds a different item, or is not inside the Trash.
    case changedInTrash
    case invalidPath
    case moveFailed

    public var message: String {
        switch self {
        case .destinationExists: "something already exists at the original path"
        case .missingInTrash: "it is no longer in the Trash"
        case .changedInTrash: "the Trash entry is not the item Spare moved"
        case .invalidPath: "the recorded path is not valid"
        case .moveFailed: "the move failed"
        }
    }
}

public struct UndoFailure: Codable, Sendable, Hashable {
    public let path: String
    public let reason: UndoFailureReason
}

public struct UndoResult: Codable, Sendable, Equatable {
    public let restored: Int
    /// Original paths of items that stayed in the Trash.
    public let failed: [String]
    /// Same items as `failed`, with the reason each one stayed.
    public let failures: [UndoFailure]

    public init(restored: Int, failures: [UndoFailure]) {
        self.restored = restored
        self.failures = failures
        self.failed = failures.map(\.path)
    }
}

public enum HistoryError: Error, Equatable {
    case recordNotFound
}

public struct HistoryStore: Sendable {
    let file: JSONFileStore<[CleanupRecord]>
    public let limit: Int

    public init(directory: URL, limit: Int = 100) {
        file = JSONFileStore(url: directory.appendingPathComponent("history.json"))
        self.limit = limit
    }

    /// Newest first.
    public func load() -> [CleanupRecord] {
        (file.load() ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    /// Saves a cleanup. Items in the Trash get their identity stamped, which is what later lets
    /// undo and purge tell the item Spare moved from anything else that ends up at that path.
    public func append(_ record: CleanupRecord) throws {
        var stamped = record
        for index in stamped.entries.indices {
            let entry = stamped.entries[index]
            guard entry.trashIdentity == nil, entry.status == .done, entry.action == .trash,
                  let trashPath = entry.trashPath else { continue }
            stamped.entries[index].trashIdentity = Self.identity(of: trashPath)
        }
        var records = load()
        records.insert(stamped, at: 0)
        try file.save(Array(records.sorted { $0.startedAt > $1.startedAt }.prefix(limit)))
    }

    /// Moves the record's trashed items back to where they came from. An item whose original path is taken
    /// stays in the Trash and the result says why. Matching is by recorded path and identity, never by index.
    public func undo(recordID: UUID, trash: any TrashService) throws -> UndoResult {
        try mutate(recordID) { record in
            var restored = 0
            var failures: [UndoFailure] = []
            for index in record.entries.indices {
                let entry = record.entries[index]
                guard entry.status == .done, entry.action == .trash, let trashPath = entry.trashPath else { continue }
                let original = URL(fileURLWithPath: entry.originalPath)
                if Cleaner.isNotNormalized(original) {
                    failures.append(UndoFailure(path: entry.originalPath, reason: .invalidPath))
                    continue
                }
                if !TrashFiles.exists(trashPath) {
                    failures.append(UndoFailure(path: entry.originalPath, reason: .missingInTrash))
                    continue
                }
                guard Self.isStillTheTrashedItem(entry, trash: trash) else {
                    failures.append(UndoFailure(path: entry.originalPath, reason: .changedInTrash))
                    continue
                }
                if TrashFiles.exists(entry.originalPath) {
                    failures.append(UndoFailure(path: entry.originalPath, reason: .destinationExists))
                    continue
                }
                do {
                    try trash.restore(URL(fileURLWithPath: trashPath), to: original)
                    record.entries[index].status = .restored
                    restored += 1
                } catch {
                    let reason: UndoFailureReason = TrashFiles.exists(entry.originalPath) ? .destinationExists : .moveFailed
                    failures.append(UndoFailure(path: entry.originalPath, reason: reason))
                }
            }
            return UndoResult(restored: restored, failures: failures)
        }
    }

    /// What `purge` would delete: this record's items that are still exactly where Spare put them.
    public func pendingPurge(recordID: UUID, trash: any TrashService) throws -> [CleanupEntry] {
        guard let record = load().first(where: { $0.id == recordID }) else { throw HistoryError.recordNotFound }
        return record.entries.filter { Self.canPurge($0, trash: trash) }
    }

    /// Permanently deletes this record's items that are still in the Trash at the recorded path and are still
    /// the same item. Never empties the Trash, never follows a symlink. Returns bytes freed.
    public func purge(recordID: UUID, trash: any TrashService) throws -> Int64 {
        try mutate(recordID) { record in
            var freed: Int64 = 0
            for index in record.entries.indices {
                let entry = record.entries[index]
                // The path is checked again right before deleting.
                guard Self.canPurge(entry, trash: trash), let trashPath = entry.trashPath else { continue }
                if (try? trash.purge(URL(fileURLWithPath: trashPath))) != nil {
                    record.entries[index].status = .purged
                    freed += entry.sizeBytes
                }
            }
            return freed
        }
    }

    public func clear() throws {
        try file.delete()
    }

    func mutate<T>(_ id: UUID, _ change: (inout CleanupRecord) throws -> T) throws -> T {
        var records = load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw HistoryError.recordNotFound }
        let result = try change(&records[index])
        try file.save(records)
        return result
    }

    static func canPurge(_ entry: CleanupEntry, trash: any TrashService) -> Bool {
        entry.status == .done && entry.action == .trash && entry.trashPath != nil
            && isStillTheTrashedItem(entry, trash: trash)
    }

    /// In the Trash (a direct child, not a symlink out of it) and the same device and inode as when saved.
    static func isStillTheTrashedItem(_ entry: CleanupEntry, trash: any TrashService) -> Bool {
        guard let trashPath = entry.trashPath, let saved = entry.trashIdentity else { return false }
        let url = URL(fileURLWithPath: trashPath)
        return !Cleaner.isNotNormalized(url) && trash.isInTrash(url) && identity(of: trashPath) == saved
    }

    /// `device:inode` of the path itself (a symlink is not followed), nil when it does not exist.
    static func identity(of path: String) -> String? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return "\(info.st_dev):\(info.st_ino)"
    }
}
