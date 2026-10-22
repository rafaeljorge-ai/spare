import Darwin
import Foundation

public enum MemoryPressureLevel: String, Codable, Sendable {
    case normal, warning, critical
}

/// Approximate memory numbers from public APIs only (`host_statistics64`, `sysctl`). They can differ a
/// little from Activity Monitor.
public struct MemorySnapshot: Codable, Sendable, Equatable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let compressedBytes: Int64
    public let level: MemoryPressureLevel

    public init(totalBytes: Int64, usedBytes: Int64, compressedBytes: Int64, level: MemoryPressureLevel) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.level = level
    }

    public var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }
}

/// One app (its helpers included) or one standalone process, with the summed resident memory (RSS).
/// RSS counts shared pages once per process, so the total is an approximation and can exceed real use.
public struct MemoryConsumer: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let bytes: Int64
    public let pids: [Int32]
    public let appBundleID: String?
    public let isApp: Bool

    public init(id: String, name: String, bytes: Int64, pids: [Int32], appBundleID: String?, isApp: Bool) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.pids = pids
        self.appBundleID = appBundleID
        self.isApp = isApp
    }
}

public enum MemoryMonitor {
    /// Executables under these folders belong to the system: never listed, never signaled.
    static let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"]

    static func isSystemPath(_ path: String) -> Bool {
        systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// Used = app memory + wired + compressed (close to Activity Monitor's "Memory Used", but approximate).
    public static func snapshot() -> MemorySnapshot {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = Int64(getpagesize())
        var used: Int64 = 0
        var compressed: Int64 = 0
        if result == KERN_SUCCESS {
            let appPages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            compressed = Int64(stats.compressor_page_count) * page
            used = (appPages + Int64(stats.wire_count)) * page + compressed
        }
        return MemorySnapshot(totalBytes: total, usedBytes: min(max(used, 0), total),
                              compressedBytes: compressed, level: kernelLevel())
    }

    static func kernelLevel() -> MemoryPressureLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return .normal }
        return level(fromKernelValue: value)
    }

    public static func level(fromKernelValue value: Int32) -> MemoryPressureLevel {
        switch value {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
    }

    /// The user's own non-system processes, grouped by app bundle (or executable), largest first.
    /// Spare itself (pid and app bundle) and the PID 1 are never listed. The bundle id is read only for the
    /// `limit` largest rows when the listing did not carry it (the light listing never reads bundles).
    public static func topConsumers(
        processes: [RunningProcess], currentUID: UInt32, ownPID: Int32, limit: Int = 15,
        bundleID: (String) -> String? = { Bundle(path: $0)?.bundleIdentifier }
    ) -> [MemoryConsumer] {
        let ownBundle = processes.first { $0.pid == ownPID }?.appBundlePath
        let eligible = processes.filter { process in
            process.uid == currentUID && process.pid > 1 && process.pid != ownPID
                && !isSystemPath(process.executablePath)
                && (ownBundle == nil || process.appBundlePath != ownBundle)
        }
        let groups = Dictionary(grouping: eligible) { $0.appBundlePath ?? $0.executablePath }
        return groups.map { key, members in
            MemoryConsumer(
                id: key, name: members[0].name, bytes: members.reduce(0) { $0 + $1.rssBytes },
                pids: members.map(\.pid).sorted(), appBundleID: members.first { $0.appBundleID != nil }?.appBundleID,
                isApp: members[0].appBundlePath != nil)
        }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
        .prefix(max(0, limit))
        .map { consumer in
            guard consumer.isApp, consumer.appBundleID == nil else { return consumer }
            return MemoryConsumer(id: consumer.id, name: consumer.name, bytes: consumer.bytes, pids: consumer.pids,
                                  appBundleID: bundleID(consumer.id), isApp: true)
        }
    }
}
