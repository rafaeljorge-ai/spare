import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct DiskMonitorTests {
    @Test func readsFreeAndTotalSpaceOfTheVolume() throws {
        let home = try TempHome()
        defer { home.remove() }

        let space = try #require(DiskMonitor.space(at: home.url))

        #expect(space.totalBytes > 0)
        #expect(space.freeBytes > 0)
        #expect(space.freeBytes <= space.totalBytes)
        #expect(space.usedFraction >= 0 && space.usedFraction <= 1)
    }

    @Test func returnsNilForMissingPath() {
        #expect(DiskMonitor.space(at: URL(fileURLWithPath: "/definitely/not/here")) == nil)
    }
}
