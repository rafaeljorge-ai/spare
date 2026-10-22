import Foundation

public struct ScanItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let ruleID: String
    public let category: CategoryID
    public let url: URL
    public let sizeBytes: Int64
    public let safety: Safety
    /// Name of the process or app using it; nil when free to clean.
    public var inUseBy: String?
    public let lastModified: Date?

    public init(
        ruleID: String, category: CategoryID, url: URL, sizeBytes: Int64,
        safety: Safety, inUseBy: String? = nil, lastModified: Date? = nil
    ) {
        self.ruleID = ruleID
        self.category = category
        self.url = url
        self.sizeBytes = sizeBytes
        self.safety = safety
        self.inUseBy = inUseBy
        self.lastModified = lastModified
    }
}

public struct ScanReport: Codable, Sendable {
    public var items: [ScanItem]
    public var startedAt: Date
    public var finishedAt: Date
    public var freeBytesBefore: Int64?
    public var cancelled: Bool

    public init(items: [ScanItem], startedAt: Date, finishedAt: Date, freeBytesBefore: Int64?, cancelled: Bool) {
        self.items = items
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.freeBytesBefore = freeBytesBefore
        self.cancelled = cancelled
    }

    public func items(in category: CategoryID) -> [ScanItem] {
        items.filter { $0.category == category }
    }

    public func totalBytes(in category: CategoryID) -> Int64 {
        items(in: category).reduce(0) { $0 + $1.sizeBytes }
    }

    /// Safe and not in use: what "Clean what's safe" will free.
    public var safeReclaimableBytes: Int64 {
        items.filter { $0.safety == .safe && $0.inUseBy == nil }.reduce(0) { $0 + $1.sizeBytes }
    }

    public var reviewBytes: Int64 {
        items.filter { $0.safety == .review && $0.inUseBy == nil }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Copy without the given item paths (after they were cleaned).
    public func removing(paths: Set<String>) -> ScanReport {
        var copy = self
        copy.items.removeAll { paths.contains($0.url.path) }
        return copy
    }
}

public struct ScanProgress: Sendable {
    public let currentPath: String
    public let completed: Int
    public let total: Int
    public let item: ScanItem?
    /// Set when the last pending item of a category finished.
    public let finishedCategory: CategoryID?
}
