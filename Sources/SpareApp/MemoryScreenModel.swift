import Darwin
import Foundation
import SpareCore

/// State of the Memory screen: the 15 biggest users, refreshed every 15 s and only while the screen is
/// visible (`SamplingGate`), and the confirmed quit of one row. The memory totals above the list come from
/// `AppModel.memory`, sampled every 5 s by the model's own gate.
@MainActor
final class MemoryScreenModel: ObservableObject {
    enum Outcome: Equatable {
        case asked(String)
        case failed(String)
    }

    /// Asks the processes of a row to quit and returns how many requests were delivered.
    typealias Terminator = (MemoryConsumer, [RunningProcess]) -> Int

    static let refreshSeconds = 15

    /// Nil until the first read.
    @Published private(set) var consumers: [MemoryConsumer]?
    @Published private(set) var failed = false
    @Published var pending: QuitPrompt?
    @Published private(set) var outcome: Outcome?

    private let environment: () -> SpareEnvironment
    private let terminator: Terminator
    private let settleDelay: Duration
    private var processes: [Int32: RunningProcess] = [:]
    private var gate: SamplingGate?

    init(
        environment: @escaping () -> SpareEnvironment,
        interval: Duration = .seconds(MemoryScreenModel.refreshSeconds),
        settleDelay: Duration = .seconds(2),
        terminator: @escaping Terminator = MemoryScreenModel.liveTerminator
    ) {
        self.environment = environment
        self.terminator = terminator
        self.settleDelay = settleDelay
        gate = SamplingGate(interval: interval) { [weak self] in await self?.refresh() }
    }

    /// Graceful for apps with a bundle, SIGTERM for the rest; the core still refuses Spare, its ancestors
    /// and the system.
    static let liveTerminator: Terminator = { consumer, processes in
        ProcessTerminator.terminate(
            consumer, processes: processes, currentUID: getuid(), ownPID: getpid(), quitter: AppQuitter())
    }

    /// The Memory screen became visible or hidden.
    func setVisible(_ isVisible: Bool) {
        gate?.setVisible(isVisible, source: "memory-screen")
    }

    func refresh() async {
        let environment = environment()
        let result = await Task.detached(priority: .utility) { () -> ([RunningProcess], [MemoryConsumer])? in
            guard let listing = try? environment.memoryProcesses() else { return nil }
            let top = MemoryMonitor.topConsumers(processes: listing, currentUID: getuid(), ownPID: getpid(), limit: 15)
            return (listing, top)
        }.value
        guard let (listing, top) = result else {
            failed = true
            if consumers == nil { consumers = [] }
            return
        }
        failed = false
        processes = Dictionary(listing.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        consumers = top
    }

    // MARK: Quit

    func ask(_ consumer: MemoryConsumer) {
        pending = QuitPrompt.make(consumer: consumer, processes: processes)
    }

    func cancelPending() {
        pending = nil
    }

    /// Asks the pending row to quit. Nothing happens without `ask`.
    func confirmQuit() async {
        guard let prompt = pending else { return }
        pending = nil
        let environment = environment()
        // A fresh listing: the pids must still be what the screen showed.
        guard let live = await Task.detached(priority: .userInitiated, operation: { try? environment.memoryProcesses() }).value
        else {
            outcome = .failed(prompt.consumer.name)
            return
        }
        let delivered = terminator(prompt.consumer, live)
        outcome = delivered > 0 ? .asked(prompt.consumer.name) : .failed(prompt.consumer.name)
        try? await Task.sleep(for: settleDelay)
        await refresh()
    }

    func dismissOutcome() {
        outcome = nil
    }
}
