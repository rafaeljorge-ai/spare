import Foundation
import Testing
import SpareCore
import SpareTestSupport
@testable import SpareApp

final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    var isEnabled = false
    var refuses = false
    struct Refused: Error {}

    func setEnabled(_ enabled: Bool) throws {
        if refuses { throw Refused() }
        isEnabled = enabled
    }
}

@MainActor @Suite struct SettingsModelTests {
    @Test func startsFromTheSystemState() {
        let login = FakeLoginItem()
        login.isEnabled = true
        #expect(SettingsModel(loginItem: login).opensAtLogin)
    }

    @Test func togglingAppliesTheChange() {
        let login = FakeLoginItem()
        let model = SettingsModel(loginItem: login)
        model.setOpensAtLogin(true)
        #expect(login.isEnabled)
        #expect(model.opensAtLogin)
        #expect(!model.loginFailed)
        model.setOpensAtLogin(false)
        #expect(!login.isEnabled)
        #expect(!model.opensAtLogin)
    }

    @Test func aRefusalRevertsTheSwitchAndShowsAFriendlyNote() {
        let login = FakeLoginItem()
        login.refuses = true
        let model = SettingsModel(loginItem: login)
        model.setOpensAtLogin(true)
        #expect(!model.opensAtLogin)
        #expect(model.loginFailed)

        login.refuses = false
        model.setOpensAtLogin(true)
        #expect(model.opensAtLogin)
        #expect(!model.loginFailed)
    }
}

@MainActor @Suite struct SettingsPersistenceTests {
    func makeModel(_ home: TempHome) -> AppModel {
        AppModel(
            home: home.url,
            makeEnvironment: { home, settings in
                var environment = SpareEnvironment.test(home: home)
                environment.projectIdleDays = settings.projectIdleDays
                return environment
            },
            monitorDisk: false)
    }

    @Test func changesAreSavedAndLoadedByTheNextLaunch() throws {
        let home = try TempHome()
        let model = makeModel(home)
        model.settings.diskAlertThresholdGB = 40
        model.settings.memoryAlertsEnabled = false
        model.settings.projectIdleDays = 90
        model.settings.projectRootPaths = ["/tmp/x"]

        let next = makeModel(home)
        #expect(next.settings.diskAlertThresholdGB == 40)
        #expect(!next.settings.memoryAlertsEnabled)
        #expect(next.settings.projectIdleDays == 90)
        #expect(next.settings.projectRootPaths == ["/tmp/x"])
    }

    @Test func changesApplyRightAway() throws {
        let home = try TempHome()
        let model = makeModel(home)  // the test environment reports 10 GB free
        model.settings.diskAlertThresholdGB = 5
        #expect(!model.isDiskLow)
        model.settings.diskAlertThresholdGB = 15
        #expect(model.isDiskLow)
        #expect(model.environment.projectIdleDays == 30)
        model.settings.projectIdleDays = 60
        #expect(model.environment.projectIdleDays == 60)
    }
}
