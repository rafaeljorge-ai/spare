import Foundation

/// Local state of the Settings screen that is not a saved setting: "Open at login" and its error.
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var opensAtLogin: Bool
    /// True when macOS refused the change (an app that is not installed or signed may be refused).
    @Published private(set) var loginFailed = false

    private let loginItem: any LoginItemControlling

    init(loginItem: any LoginItemControlling = SystemLoginItem()) {
        self.loginItem = loginItem
        opensAtLogin = loginItem.isEnabled
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginFailed = false
        } catch {
            loginFailed = true
        }
        opensAtLogin = loginItem.isEnabled
    }

    func refresh() {
        opensAtLogin = loginItem.isEnabled
    }
}
