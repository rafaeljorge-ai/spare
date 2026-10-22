import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct SizeCalculatorTests {
    @Test func sumsFilesInsideADirectory() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("cache/a.bin", bytes: 10_000)
        try home.file("cache/sub/b.bin", bytes: 5_000)

        let size = SizeCalculator.allocatedSize(of: home.path("cache"))

        #expect(size >= 15_000)
        #expect(size < 15_000 + 3 * 4096)
    }

    @Test func measuresASingleFile() throws {
        let home = try TempHome()
        defer { home.remove() }
        let file = try home.file("big.dmg", bytes: 50_000)

        #expect(SizeCalculator.allocatedSize(of: file) >= 50_000)
    }

    @Test func countsHardLinkedFilesOnce() throws {
        let home = try TempHome()
        defer { home.remove() }
        let original = try home.file("store/blob", bytes: 200_000)
        try FileManager.default.createDirectory(at: home.path("store/linked"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: home.path("store/linked/blob"))

        let size = SizeCalculator.allocatedSize(of: home.path("store"))

        #expect(size >= 200_000)
        #expect(size < 400_000)
    }

    @Test func doesNotFollowSymlinkedDirectories() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("elsewhere/huge.bin", bytes: 1_000_000)
        try home.directory("cache")
        try FileManager.default.createSymbolicLink(
            at: home.path("cache/link"), withDestinationURL: home.path("elsewhere"))

        #expect(SizeCalculator.allocatedSize(of: home.path("cache")) < 100_000)
    }

    @Test func missingPathIsZero() {
        #expect(SizeCalculator.allocatedSize(of: URL(fileURLWithPath: "/nope/nothing")) == 0)
    }
}
