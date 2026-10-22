import Testing
@testable import SpareCore

@Suite struct ByteFormatTests {
    @Test func roundsToWholeDecimalGigabytes() {
        #expect(ByteFormat.gigabytes(15_400_000_000) == 15)
        #expect(ByteFormat.gigabytes(15_600_000_000) == 16)
        #expect(ByteFormat.gigabytes(0) == 0)
    }

    @Test func formatsHumanReadableSizes() {
        #expect(ByteFormat.string(0).isEmpty == false)
        #expect(ByteFormat.string(1_500_000_000).contains("1"))
    }
}
