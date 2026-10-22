import Foundation
import SpareCore
import UserNotifications

enum AlertKind: String, Sendable {
    case disk, memory
}

struct SpareAlert: Equatable, Sendable {
    let kind: AlertKind
    /// Free bytes at the moment of a disk alert.
    var freeBytes: Int64?
}

/// Where alerts go. The real one is `SystemAlertPoster`; tests record them.
@MainActor
protocol AlertPosting: AnyObject {
    var onOpen: ((AlertKind) -> Void)? { get set }
    func requestAuthorization()
    func post(_ alert: SpareAlert)
}

/// Decides when to alert (`AlertPolicy` cooldowns) and remembers when it last did. The Spare alert for a
/// kind is sent once, then not again until its cooldown passes, no matter how often the monitor ticks.
@MainActor
final class AlertCenter {
    private let poster: any AlertPosting
    private let now: @Sendable () -> Date
    private let defaults: UserDefaults
    /// Persisted, so relaunching the app (or a login item start) does not alert again inside the cooldown.
    private var lastDiskAlert: Date? {
        didSet { defaults.set(lastDiskAlert, forKey: Self.diskKey) }
    }
    private var lastMemoryAlert: Date? {
        didSet { defaults.set(lastMemoryAlert, forKey: Self.memoryKey) }
    }

    static let diskKey = "spare.lastDiskAlert"
    static let memoryKey = "spare.lastMemoryAlert"
    var onOpen: ((AlertKind) -> Void)? {
        didSet { poster.onOpen = onOpen }
    }

    init(poster: any AlertPosting, defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.poster = poster
        self.defaults = defaults
        self.now = now
        lastDiskAlert = defaults.object(forKey: Self.diskKey) as? Date
        lastMemoryAlert = defaults.object(forKey: Self.memoryKey) as? Date
    }

    func start() {
        poster.requestAuthorization()
    }

    func evaluate(disk: DiskSpace?, memory: MemorySnapshot?, settings: SpareSettings) {
        let moment = now()
        if let disk, AlertPolicy.shouldAlertDisk(
            freeBytes: disk.freeBytes, thresholdGB: settings.diskAlertThresholdGB, lastAlert: lastDiskAlert, now: moment) {
            lastDiskAlert = moment
            poster.post(SpareAlert(kind: .disk, freeBytes: disk.freeBytes))
        }
        if let memory, AlertPolicy.shouldAlertMemory(
            level: memory.level, enabled: settings.memoryAlertsEnabled, lastAlert: lastMemoryAlert, now: moment) {
            lastMemoryAlert = moment
            poster.post(SpareAlert(kind: .memory, freeBytes: nil))
        }
    }
}

/// Local notifications. Off when the binary is not an `.app` (`swift run`, tests), where
/// `UNUserNotificationCenter` would crash.
@MainActor
final class SystemAlertPoster: NSObject, AlertPosting, UNUserNotificationCenterDelegate {
    var onOpen: ((AlertKind) -> Void)?

    private var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func requestAuthorization() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ alert: SpareAlert) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        switch alert.kind {
        case .disk:
            content.title = String(localized: "Your Mac is running out of space")
            let free = ByteFormat.string(alert.freeBytes ?? 0)
            content.body = String(localized: "Only \(free) left. Open Spare to free space.")
        case .memory:
            content.title = String(localized: "Memory is under pressure")
            content.body = String(localized: "Open Spare to see what is using it.")
        }
        content.userInfo = ["kind": alert.kind.rawValue]
        // A fixed identifier per kind: a new alert replaces the previous one instead of stacking.
        let request = UNNotificationRequest(identifier: "spare.\(alert.kind.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo["kind"] as? String
        await MainActor.run { onOpen?(raw.flatMap(AlertKind.init(rawValue:)) ?? .disk) }
    }
}
