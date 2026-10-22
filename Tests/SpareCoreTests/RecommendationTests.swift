import Foundation
import Testing
@testable import SpareCore

@Suite struct RecommendationTests {
    let roomy = DiskSpace(freeBytes: 80_000_000_000, totalBytes: 228_000_000_000)
    let tight = DiskSpace(freeBytes: 9_000_000_000, totalBytes: 228_000_000_000)
    let calm = MemorySnapshot(totalBytes: 16, usedBytes: 8, compressedBytes: 0, level: .normal)
    let busy = MemorySnapshot(totalBytes: 16, usedBytes: 15, compressedBytes: 4, level: .warning)

    func report(safeBytes: Int64) -> ScanReport {
        let item = ScanItem(ruleID: "dev.npm", category: .devCaches, url: URL(fileURLWithPath: "/x"),
                            sizeBytes: safeBytes, safety: .safe)
        return ScanReport(items: [item], startedAt: Date(), finishedAt: Date(), freeBytesBefore: nil, cancelled: false)
    }

    @Test func lowDiskWinsOverEverything() {
        #expect(Recommendation.compute(disk: tight, thresholdGB: 15, lastScan: report(safeBytes: 20_000_000_000), memory: busy)
                == .lowDisk(freeBytes: 9_000_000_000))
    }

    @Test func reclaimableWhenLastScanFoundMoreThanTenGB() {
        #expect(Recommendation.compute(disk: roomy, thresholdGB: 15, lastScan: report(safeBytes: 23_000_000_000), memory: busy)
                == .reclaimable(bytes: 23_000_000_000))
    }

    @Test func highMemoryNext() {
        #expect(Recommendation.compute(disk: roomy, thresholdGB: 15, lastScan: report(safeBytes: 1), memory: busy) == .highMemory)
    }

    @Test func allGoodOtherwise() {
        #expect(Recommendation.compute(disk: roomy, thresholdGB: 15, lastScan: nil, memory: calm) == .allGood)
        #expect(Recommendation.compute(disk: nil, thresholdGB: 15, lastScan: nil, memory: nil) == .allGood)
    }
}
