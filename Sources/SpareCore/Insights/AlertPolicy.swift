import Foundation

/// When a notification is worth sending. Pure rules: the app layer keeps the last-alert dates.
public enum AlertPolicy {
    public static let diskCooldown: TimeInterval = 6 * 3600
    public static let memoryCooldown: TimeInterval = 3600

    public static func shouldAlertDisk(freeBytes: Int64, thresholdGB: Int, lastAlert: Date?, now: Date) -> Bool {
        guard freeBytes < Int64(thresholdGB) * 1_000_000_000 else { return false }
        guard let lastAlert else { return true }
        return now.timeIntervalSince(lastAlert) >= diskCooldown
    }

    /// Only `.critical` pressure alerts; `.warning` is shown in the app but never interrupts.
    public static func shouldAlertMemory(level: MemoryPressureLevel, enabled: Bool, lastAlert: Date?, now: Date) -> Bool {
        guard enabled, level == .critical else { return false }
        guard let lastAlert else { return true }
        return now.timeIntervalSince(lastAlert) >= memoryCooldown
    }
}
