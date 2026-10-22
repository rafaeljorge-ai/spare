import Foundation

public enum ActionKind: String, Codable, Sendable, Hashable {
    case delete, trash, command, emptyTrash

    public init(_ action: CleanAction) {
        switch action {
        case .delete: self = .delete
        case .trash: self = .trash
        case .command: self = .command
        case .emptyTrash: self = .emptyTrash
        }
    }
}

public enum EntryStatus: String, Codable, Sendable, Hashable {
    case done, skipped, failed, restored, purged
}

public struct CleanupEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: String { originalPath }
    public let ruleID: String
    public let category: CategoryID
    public let originalPath: String
    public var trashPath: String?
    /// Device and inode of the item in the Trash, stamped when the cleanup is saved. Undo and purge only
    /// touch the item if it is still this exact one (a later item with the same name does not match).
    public var trashIdentity: String?
    public var action: ActionKind
    public let sizeBytes: Int64
    public var status: EntryStatus
    public var skipReason: SkipReason?
    /// Process name when in use, "unknown" when it could not be checked, or an error message when failed.
    public var detail: String?

    public init(ruleID: String, category: CategoryID, originalPath: String, trashPath: String? = nil,
                trashIdentity: String? = nil, action: ActionKind, sizeBytes: Int64, status: EntryStatus,
                skipReason: SkipReason? = nil, detail: String? = nil) {
        self.ruleID = ruleID
        self.category = category
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.trashIdentity = trashIdentity
        self.action = action
        self.sizeBytes = sizeBytes
        self.status = status
        self.skipReason = skipReason
        self.detail = detail
    }
}

public struct CleanupRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public var finishedAt: Date
    public let freeBytesBefore: Int64?
    public var freeBytesAfter: Int64?
    public var entries: [CleanupEntry]
    public var cancelled: Bool

    public init(id: UUID = UUID(), startedAt: Date, finishedAt: Date, freeBytesBefore: Int64?,
                freeBytesAfter: Int64?, entries: [CleanupEntry], cancelled: Bool) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.freeBytesBefore = freeBytesBefore
        self.freeBytesAfter = freeBytesAfter
        self.entries = entries
        self.cancelled = cancelled
    }

    public var cleanedBytes: Int64 {
        entries.filter { $0.status == .done }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Bytes sitting in the Trash: only freed after the Trash is emptied (or purged).
    public var trashedBytes: Int64 {
        undoableEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    public var undoableEntries: [CleanupEntry] {
        entries.filter { $0.status == .done && $0.action == .trash && $0.trashPath != nil }
    }
}

public struct CleanProgress: Sendable {
    public let index: Int
    public let total: Int
    public let entry: CleanupEntry
}
