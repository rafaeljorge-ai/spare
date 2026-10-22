import Foundation

/// What a confirmation dialog needs to tell the user before cleaning.
public struct CleanPlan: Sendable, Equatable, Identifiable {
    /// One entry per path: the Cleaner treats a path listed twice as one item.
    public let items: [ScanItem]
    public private(set) var trashCount = 0
    public private(set) var trashBytes: Int64 = 0
    public private(set) var deleteCount = 0
    public private(set) var deleteBytes: Int64 = 0
    public private(set) var commandCount = 0
    public private(set) var emptiesTrash = false

    public init(items: [ScanItem], catalog: RuleCatalog = .standard) {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.url.path).inserted }
        self.items = unique
        for item in unique {
            switch catalog.rule(id: item.ruleID)?.action {
            case .trash:
                trashCount += 1
                trashBytes += item.sizeBytes
            case .delete:
                deleteCount += 1
                deleteBytes += item.sizeBytes
            case .command:
                commandCount += 1
            case .emptyTrash:
                emptiesTrash = true
            case nil:
                break
            }
        }
        // Same order the Cleaner follows: emptying the Trash goes first.
        executionOrder = unique.filter { Cleaner.emptiesTrash($0, catalog) }
            + unique.filter { !Cleaner.emptiesTrash($0, catalog) }
    }

    /// The order items are cleaned in (progress events arrive in this order, not in the order asked).
    public let executionOrder: [ScanItem]

    public var id: String {
        items.map(\.id).joined(separator: "|")
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Safe and not in use (an item whose check failed carries "unknown" and is not free either).
    public static func defaultSelection(for items: [ScanItem]) -> Set<String> {
        Set(items.filter { $0.safety == .safe && $0.inUseBy == nil }.map(\.id))
    }
}

/// What a finished cleanup achieved, counted from its record.
public struct CleanOutcome: Sendable, Equatable {
    public let cleanedCount: Int
    public let cleanedBytes: Int64
    /// Bytes sitting in the Trash: only freed when they leave it.
    public let trashedBytes: Int64
    /// Bytes gone for good right now (deleted, tool command, emptied Trash).
    public let freedBytes: Int64
    public let skippedCount: Int
    public let failedCount: Int

    public init(_ record: CleanupRecord) {
        let done = record.entries.filter { $0.status == .done }
        cleanedCount = done.count
        cleanedBytes = record.cleanedBytes
        trashedBytes = record.trashedBytes
        freedBytes = cleanedBytes - trashedBytes
        skippedCount = record.entries.filter { $0.status == .skipped }.count
        failedCount = record.entries.filter { $0.status == .failed }.count
    }
}
