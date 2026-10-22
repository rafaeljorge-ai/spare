import Foundation

public enum Recommendation: Equatable, Sendable {
    case lowDisk(freeBytes: Int64)
    case reclaimable(bytes: Int64)
    case highMemory
    case allGood

    public static let reclaimableThreshold: Int64 = 10_000_000_000

    public static func compute(
        disk: DiskSpace?, thresholdGB: Int, lastScan: ScanReport?, memory: MemorySnapshot?
    ) -> Recommendation {
        if let disk, disk.freeBytes < Int64(thresholdGB) * 1_000_000_000 {
            return .lowDisk(freeBytes: disk.freeBytes)
        }
        if let bytes = lastScan?.safeReclaimableBytes, bytes > reclaimableThreshold {
            return .reclaimable(bytes: bytes)
        }
        if let memory, memory.level != .normal {
            return .highMemory
        }
        return .allGood
    }
}
