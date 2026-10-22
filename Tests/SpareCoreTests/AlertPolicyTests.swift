import Foundation
import Testing
@testable import SpareCore

@Suite struct AlertPolicyTests {
    let now = Date()

    @Test func diskAlertsBelowThresholdWithCooldown() {
        #expect(AlertPolicy.shouldAlertDisk(freeBytes: 9_000_000_000, thresholdGB: 15, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertDisk(freeBytes: 20_000_000_000, thresholdGB: 15, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertDisk(freeBytes: 15_000_000_000, thresholdGB: 15, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertDisk(freeBytes: 9_000_000_000, thresholdGB: 15,
                                             lastAlert: now.addingTimeInterval(-3600), now: now))
        #expect(AlertPolicy.shouldAlertDisk(freeBytes: 9_000_000_000, thresholdGB: 15,
                                            lastAlert: now.addingTimeInterval(-7 * 3600), now: now))
    }

    @Test func memoryAlertsOnlyWhenCriticalEnabledAndCooledDown() {
        #expect(AlertPolicy.shouldAlertMemory(level: .critical, enabled: true, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertMemory(level: .warning, enabled: true, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertMemory(level: .normal, enabled: true, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertMemory(level: .critical, enabled: false, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertMemory(level: .critical, enabled: true,
                                               lastAlert: now.addingTimeInterval(-60), now: now))
        #expect(AlertPolicy.shouldAlertMemory(level: .critical, enabled: true,
                                              lastAlert: now.addingTimeInterval(-2 * 3600), now: now))
    }
}
