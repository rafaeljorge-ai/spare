import Foundation

public struct DiskSpace: Codable, Sendable, Equatable {
    public let freeBytes: Int64
    public let totalBytes: Int64

    public init(freeBytes: Int64, totalBytes: Int64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - freeBytes) / Double(totalBytes)
    }
}

public enum DiskMonitor {
    /// Free space as the system reports it for "important" usage (what Finder shows).
    public static func space(at url: URL) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity
        else { return nil }
        return DiskSpace(freeBytes: free, totalBytes: Int64(total))
    }
}
