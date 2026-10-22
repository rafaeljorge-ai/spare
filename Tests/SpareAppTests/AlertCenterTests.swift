import Foundation
import Testing
import SpareCore
@testable import SpareApp

@MainActor
final class RecordingPoster: AlertPosting {
    var onOpen: ((AlertKind) -> Void)?
    private(set) var alerts: [SpareAlert] = []
    private(set) var authorizationRequests = 0

    func requestAuthorization() { authorizationRequests += 1 }
    func post(_ alert: SpareAlert) { alerts.append(alert) }
}

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@MainActor @Suite struct AlertCenterTests {
    let low = DiskSpace(freeBytes: 9_000_000_000, totalBytes: 245_000_000_000)
    let fine = DiskSpace(freeBytes: 80_000_000_000, totalBytes: 245_000_000_000)
    func memory(_ level: MemoryPressureLevel) -> MemorySnapshot {
        MemorySnapshot(totalBytes: 16_000_000_000, usedBytes: 15_000_000_000, compressedBytes: 1_000_000_000, level: level)
    }

    func makeCenter(_ clock: TestClock) -> (AlertCenter, RecordingPoster) {
        let poster = RecordingPoster()
        return (AlertCenter(poster: poster, defaults: freshDefaults(), now: { clock.now }), poster)
    }

    /// A throwaway defaults domain: tests never touch the real one.
    func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "spare-tests-\(UUID().uuidString)")!
    }

    @Test func cooldownSurvivesARelaunch() {
        let clock = TestClock()
        let defaults = freshDefaults()
        let first = RecordingPoster()
        AlertCenter(poster: first, defaults: defaults, now: { clock.now })
            .evaluate(disk: low, memory: memory(.critical), settings: SpareSettings())
        #expect(first.alerts.count == 2)

        // A new process (same defaults) five minutes later: nothing repeats.
        clock.advance(300)
        let second = RecordingPoster()
        let relaunched = AlertCenter(poster: second, defaults: defaults, now: { clock.now })
        relaunched.evaluate(disk: low, memory: memory(.critical), settings: SpareSettings())
        #expect(second.alerts.isEmpty)

        clock.advance(AlertPolicy.diskCooldown)
        relaunched.evaluate(disk: low, memory: memory(.critical), settings: SpareSettings())
        #expect(second.alerts.map(\.kind) == [.disk, .memory])
    }

    @Test func startAsksForPermissionOnce() {
        let (center, poster) = makeCenter(TestClock())
        center.start()
        #expect(poster.authorizationRequests == 1)
    }

    @Test func diskAlertFiresBelowTheThresholdOnly() {
        let (center, poster) = makeCenter(TestClock())
        center.evaluate(disk: fine, memory: nil, settings: SpareSettings())
        #expect(poster.alerts.isEmpty)
        center.evaluate(disk: low, memory: nil, settings: SpareSettings())
        #expect(poster.alerts == [SpareAlert(kind: .disk, freeBytes: 9_000_000_000)])
    }

    @Test func diskAlertFollowsTheSettingAndDoesNotRepeatInsideTheCooldown() {
        let clock = TestClock()
        let (center, poster) = makeCenter(clock)
        var settings = SpareSettings()
        settings.diskAlertThresholdGB = 5
        center.evaluate(disk: low, memory: nil, settings: settings)
        #expect(poster.alerts.isEmpty)

        settings.diskAlertThresholdGB = 15
        for _ in 0..<10 {  // the monitor ticks every minute
            center.evaluate(disk: low, memory: nil, settings: settings)
            clock.advance(60)
        }
        #expect(poster.alerts.count == 1)

        clock.advance(AlertPolicy.diskCooldown)
        center.evaluate(disk: low, memory: nil, settings: settings)
        #expect(poster.alerts.count == 2)
    }

    @Test func memoryAlertNeedsCriticalPressureAndTheSwitchOn() {
        let clock = TestClock()
        let (center, poster) = makeCenter(clock)
        var settings = SpareSettings()
        center.evaluate(disk: nil, memory: memory(.warning), settings: settings)
        #expect(poster.alerts.isEmpty)

        settings.memoryAlertsEnabled = false
        center.evaluate(disk: nil, memory: memory(.critical), settings: settings)
        #expect(poster.alerts.isEmpty)

        settings.memoryAlertsEnabled = true
        center.evaluate(disk: nil, memory: memory(.critical), settings: settings)
        center.evaluate(disk: nil, memory: memory(.critical), settings: settings)
        #expect(poster.alerts == [SpareAlert(kind: .memory, freeBytes: nil)])

        clock.advance(AlertPolicy.memoryCooldown)
        center.evaluate(disk: nil, memory: memory(.critical), settings: settings)
        #expect(poster.alerts.count == 2)
    }

    @Test func diskAndMemoryCooldownsAreIndependent() {
        let (center, poster) = makeCenter(TestClock())
        center.evaluate(disk: low, memory: memory(.critical), settings: SpareSettings())
        #expect(poster.alerts.map(\.kind) == [.disk, .memory])
    }

    @Test func clickingANotificationReachesTheCallback() {
        let (center, poster) = makeCenter(TestClock())
        var opened: AlertKind?
        center.onOpen = { opened = $0 }
        poster.onOpen?(.memory)
        #expect(opened == .memory)
    }
}
