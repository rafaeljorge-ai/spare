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

/// What `undo` would do, without doing it.
public struct UndoPreview: Sendable, Equatable {
    public let wouldRestore: [CleanupEntry]
    public let failures: [UndoFailure]
}

public struct PurgeFailure: Codable, Sendable, Hashable {
    public let path: String
    public let message: String
}

public struct PurgeResult: Codable, Sendable, Equatable {
    public let freedBytes: Int64
    public let purged: Int
    /// Items that stayed in the Trash: a failed removal or an entry that is no longer the item Spare moved.
    /// Items that already left the Trash are not failures.
    public let failures: [PurgeFailure]
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

    /// Newest first. Throws when the file exists but cannot be read; a missing file is an empty history.
    public func load() throws -> [CleanupRecord] {
        (try file.load() ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    /// Saves a cleanup. The Cleaner already stamped each trashed item's identity when it moved it; this does
    /// not stamp anything, so a later swap in the Trash can never be mistaken for the item Spare moved.
    public func append(_ record: CleanupRecord) throws {
        try file.withLock {
            var records = try load()
            records.insert(record, at: 0)
            try file.save(Array(records.sorted { $0.startedAt > $1.startedAt }.prefix(limit)))
        }
    }

    /// Why this entry cannot be restored right now, nil when it can.
    static func undoBlocker(_ entry: CleanupEntry, trash: any TrashService) -> UndoFailureReason? {
        guard let trashPath = entry.trashPath else { return .missingInTrash }
        if Cleaner.isNotNormalized(URL(fileURLWithPath: entry.originalPath)) { return .invalidPath }
        if !TrashFiles.exists(trashPath) { return .missingInTrash }
        if !isStillTheTrashedItem(entry, trash: trash) { return .changedInTrash }
        if TrashFiles.exists(entry.originalPath) { return .destinationExists }
        return nil
    }

    static func isUndoable(_ entry: CleanupEntry) -> Bool {
        entry.status == .done && entry.action == .trash && entry.trashPath != nil
    }

    /// What `undo` would restore and what would stay in the Trash. Changes nothing.
    public func previewUndo(recordID: UUID, trash: any TrashService) throws -> UndoPreview {
        guard let record = try load().first(where: { $0.id == recordID }) else { throw HistoryError.recordNotFound }
        var restorable: [CleanupEntry] = []
        var failures: [UndoFailure] = []
        for entry in record.entries where Self.isUndoable(entry) {
            if let reason = Self.undoBlocker(entry, trash: trash) {
                failures.append(UndoFailure(path: entry.originalPath, reason: reason))
            } else {
                restorable.append(entry)
            }
        }
        return UndoPreview(wouldRestore: restorable, failures: failures)
    }

    /// Moves the record's trashed items back to where they came from. An item whose original path is taken
    /// stays in the Trash and the result says why. Matching is by recorded path and identity, never by index.
    public func undo(recordID: UUID, trash: any TrashService) throws -> UndoResult {
        try mutate(recordID) { record in
            var restored = 0
            var failures: [UndoFailure] = []
            for index in record.entries.indices where Self.isUndoable(record.entries[index]) {
                let entry = record.entries[index]
                if let reason = Self.undoBlocker(entry, trash: trash) {
                    failures.append(UndoFailure(path: entry.originalPath, reason: reason))
                    continue
                }
                do {
                    try trash.restore(URL(fileURLWithPath: entry.trashPath!), to: URL(fileURLWithPath: entry.originalPath))
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
        guard let record = try load().first(where: { $0.id == recordID }) else { throw HistoryError.recordNotFound }
        return record.entries.filter { Self.purgeState($0, trash: trash) == .eligible }
    }

    /// Permanently deletes this record's items that are still in the Trash at the recorded path and are still
    /// the same item. Never empties the Trash, never follows a symlink. Failures are returned, not swallowed.
    public func purge(recordID: UUID, trash: any TrashService) throws -> PurgeResult {
        try mutate(recordID) { record in
            var freed: Int64 = 0
            var purged = 0
            var failures: [PurgeFailure] = []
            for index in record.entries.indices {
                let entry = record.entries[index]
                // The location and identity are checked again right before deleting.
                switch Self.purgeState(entry, trash: trash) {
                case .notApplicable, .gone:
                    continue
                case .changed:
                    failures.append(PurgeFailure(
                        path: entry.originalPath, message: "the Trash entry is not the item Spare moved, left untouched"))
                case .eligible:
                    do {
                        try trash.purge(URL(fileURLWithPath: entry.trashPath!))
                        record.entries[index].status = .purged
                        freed += entry.sizeBytes
                        purged += 1
                    } catch {
                        failures.append(PurgeFailure(path: entry.originalPath, message: error.localizedDescription))
                    }
                }
            }
            return PurgeResult(freedBytes: freed, purged: purged, failures: failures)
        }
    }

    public func clear() throws {
        try file.withLock { try file.delete() }
    }

    /// Reads, changes and writes under the lock, so concurrent runs cannot lose each other's changes.
    func mutate<T>(_ id: UUID, _ change: (inout CleanupRecord) throws -> T) throws -> T {
        try file.withLock {
            var records = try load()
            guard let index = records.firstIndex(where: { $0.id == id }) else { throw HistoryError.recordNotFound }
            let result = try change(&records[index])
            try file.save(records)
            return result
        }
    }

    enum PurgeState { case notApplicable, gone, changed, eligible }

    static func purgeState(_ entry: CleanupEntry, trash: any TrashService) -> PurgeState {
        guard isUndoable(entry), let trashPath = entry.trashPath else { return .notApplicable }
        if !TrashFiles.exists(trashPath) { return .gone }
        return isStillTheTrashedItem(entry, trash: trash) ? .eligible : .changed
    }

    /// In the Trash (a direct child, not a symlink out of it) and the same device and inode as when moved.
    static func isStillTheTrashedItem(_ entry: CleanupEntry, trash: any TrashService) -> Bool {
        guard let trashPath = entry.trashPath, let saved = entry.trashIdentity else { return false }
        let url = URL(fileURLWithPath: trashPath)
        return !Cleaner.isNotNormalized(url) && trash.isInTrash(url) && identity(of: trashPath) == saved
    }

    /// `device:inode` of the path itself (a symlink is not followed), nil when it does not exist.
    static func identity(of path: String) -> String? {
        TrashFiles.identity(of: path)
    }
}
