import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct ScannerTests {
    func makeJunk(_ home: TempHome) throws {
        try home.file(".npm/_cacache/index/a", bytes: 50_000)
        try home.file("Library/Caches/com.example.app/data", bytes: 30_000)
        try home.file("Library/Caches/com.apple.Safari/data", bytes: 30_000)
        try home.file("Library/Caches/Homebrew/bottle.tar.gz", bytes: 20_000)
        try home.file("Downloads/old.dmg", bytes: 10_000, modified: daysAgo(60))
        try home.file("Downloads/new.dmg", bytes: 10_000)
        try home.file("Downloads/photo.jpg", bytes: 10_000, modified: daysAgo(60))
        try home.file("Library/Logs/app.log", bytes: 8_000)
    }

    @Test func findsCatalogItemsAndNothingElse() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let scanner = Scanner(environment: .test(home: home.url))

        let report = await scanner.scan()
        let byRule = Dictionary(grouping: report.items, by: \.ruleID)

        #expect(byRule["dev.npm"]?.count == 1)
        #expect(byRule["dev.homebrew"]?.count == 1)
        #expect(byRule["apps.caches"]?.map(\.url.lastPathComponent) == ["com.example.app"])
        #expect(byRule["downloads.installers"]?.map(\.url.lastPathComponent) == ["old.dmg"])
        #expect(byRule["apps.logs"]?.count == 1)
        #expect(report.cancelled == false)
        #expect(report.freeBytesBefore == 10_000_000_000)
    }

    @Test func specificRulesWinOverTheGenericCachesRule() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)

        let report = await Scanner(environment: .test(home: home.url)).scan()

        let cacheChildren = report.items.filter { $0.ruleID == "apps.caches" }.map(\.url.lastPathComponent)
        #expect(!cacheChildren.contains("Homebrew"))
    }

    @Test func totalsAndSafetyBuckets() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        try home.file(".cache/huggingface/hub/model.bin", bytes: 40_000)

        let report = await Scanner(environment: .test(home: home.url)).scan()

        #expect(report.totalBytes(in: .devCaches) >= 70_000)
        #expect(report.reviewBytes >= 40_000)
        #expect(report.safeReclaimableBytes >= 70_000 + 30_000 + 10_000 + 8_000)
    }

    @Test func emptyFoldersAreNotReported() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.directory(".npm/_cacache")

        let report = await Scanner(environment: .test(home: home.url)).scan()

        #expect(report.items.isEmpty)
    }

    @Test func categoryFilterLimitsTheScan() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)

        let report = await Scanner(environment: .test(home: home.url)).scan(categories: [.logs])

        #expect(Set(report.items.map(\.category)) == [.logs])
    }

    @Test func reportsProgressForEveryItem() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let seen = OutputCapture()

        let report = await Scanner(environment: .test(home: home.url)).scan { progress in
            seen.write(progress.currentPath)
        }

        #expect(seen.text.split(separator: "\n").count == report.items.count)
    }

    @Test func cancellationReturnsAPartialReport() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        var environment = SpareEnvironment.test(home: home.url)
        environment.diskSpace = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return nil
        }
        let scanner = Scanner(environment: environment)

        let task = Task { await scanner.scan() }
        task.cancel()
        let report = await task.value

        #expect(report.cancelled)
    }

    @Test func reportRoundTripsThroughJSON() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try makeJunk(home)
        let report = await Scanner(environment: .test(home: home.url)).scan()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanReport.self, from: encoder.encode(report))

        #expect(decoded.items.count == report.items.count)
        #expect(decoded.safeReclaimableBytes == report.safeReclaimableBytes)
    }

    @Test func scannerIncludesIdleProjectLeftovers() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file("Projetos/old/package.json", bytes: 10, modified: daysAgo(60))
        try home.file("Projetos/old/node_modules/lib.js", bytes: 30_000)
        try home.directory("Projetos/old/node_modules", modified: daysAgo(60))
        let environment = SpareEnvironment.test(home: home.url, projectRoots: [home.path("Projetos")])

        let report = await Scanner(environment: environment).scan(categories: [.projectLeftovers])

        #expect(report.items.map(\.ruleID) == ["project.nodeModules"])
        #expect(report.items.first?.safety == .safe)
    }
}
