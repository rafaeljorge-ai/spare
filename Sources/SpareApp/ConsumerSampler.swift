import Darwin
import Foundation
import SpareCore

/// The one `ps` listing behind the menu panel and the Memory screen. The app model's gate ticks every 5 s
/// (memory totals); the listing itself is read only when the last one is 15 s old, so the panel and the
/// screen share a single sample and never run two `ps` in the same cycle.
@MainActor
final class ConsumerSampler: ObservableObject {
    static let interval: TimeInterval = 15
    /// The gate ticks every 5 s with some jitter: a tick a second early still counts as due.
    static let tolerance: TimeInterval = 1

    /// The 15 biggest users. Nil until the first read.
    @Published private(set) var consumers: [MemoryConsumer]?
    @Published private(set) var failed = false
    /// The listing the consumers came from, by pid (the confirmation shows commands from it).
    private(set) var processes: [Int32: RunningProcess] = [:]

    private let environment: () -> SpareEnvironment
    private let now: () -> Date
    private var lastSample: Date?
    private var inFlight = false

    init(environment: @escaping () -> SpareEnvironment, now: @escaping () -> Date = { Date() }) {
        self.environment = environment
        self.now = now
    }

    /// Reads the listing when it is due (or `force`d after a user action). Never overlaps itself.
    func sampleIfDue(force: Bool = false) async {
        guard !inFlight else { return }
        if !force, let lastSample, now().timeIntervalSince(lastSample) < Self.interval - Self.tolerance { return }
        inFlight = true
        defer { inFlight = false }
        let environment = environment()
        let result = await Task.detached(priority: .utility) { () -> ([RunningProcess], [MemoryConsumer])? in
            guard let listing = try? environment.memoryProcesses() else { return nil }
            let top = MemoryMonitor.topConsumers(processes: listing, currentUID: getuid(), ownPID: getpid(), limit: 15)
            return (listing, top)
        }.value
        lastSample = now()
        guard let (listing, top) = result else {
            failed = true
            if consumers == nil { consumers = [] }
            return
        }
        failed = false
        processes = Dictionary(listing.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        consumers = top
    }
}
