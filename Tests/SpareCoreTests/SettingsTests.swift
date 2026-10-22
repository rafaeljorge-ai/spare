import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct SettingsTests {
    @Test func defaultsUseExistingProjectFolders() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.directory("Projetos")

        let settings = SpareSettings.defaults(home: home.url)

        #expect(settings.diskAlertThresholdGB == 15)
        #expect(settings.memoryAlertsEnabled)
        #expect(settings.projectIdleDays == 30)
        #expect(settings.projectRootPaths == [home.path("Projetos").path])
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(SpareSettings.self, from: Data(#"{"diskAlertThresholdGB": 20}"#.utf8))

        #expect(decoded.diskAlertThresholdGB == 20)
        #expect(decoded.projectIdleDays == 30)
        #expect(decoded.memoryAlertsEnabled)
    }

    @Test func storeRoundTripsAndSurvivesCorruption() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = SettingsStore(directory: home.path("support"))
        var settings = SpareSettings.defaults(home: home.url)
        settings.diskAlertThresholdGB = 25

        try store.save(settings)
        #expect(store.load(home: home.url).diskAlertThresholdGB == 25)

        try "not json".write(to: home.path("support/settings.json"), atomically: true, encoding: .utf8)
        #expect(store.load(home: home.url).diskAlertThresholdGB == 15)
    }

    @Test func lastScanStoreRoundTripsAndToleratesCorruption() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = ScanReportStore(directory: home.path("support"))
        let report = ScanReport(items: [], startedAt: Date(), finishedAt: Date(), freeBytesBefore: 5, cancelled: false)

        try store.save(report)
        #expect(store.load()?.freeBytesBefore == 5)

        try "{".write(to: home.path("support/last-scan.json"), atomically: true, encoding: .utf8)
        #expect(store.load() == nil)
    }

    @Test func liveEnvironmentUsesSettings() throws {
        let home = try TempHome()
        defer { home.remove() }
        var settings = SpareSettings.defaults(home: home.url)
        settings.projectRootPaths = [home.path("Work").path]
        settings.projectIdleDays = 45

        let environment = SpareEnvironment.live(home: home.url, settings: settings)

        #expect(environment.projectRoots.map(\.path) == [home.path("Work").path])
        #expect(environment.projectIdleDays == 45)
    }
}
