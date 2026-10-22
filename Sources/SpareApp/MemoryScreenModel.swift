import Combine
import Darwin
import Foundation
import SpareCore

/// State of the Memory screen: the 15 biggest users (the shared `ConsumerSampler` listing, so the screen
/// adds no `ps` of its own) and the confirmed quit of one row. The memory totals above the list come from
/// `AppModel.memory`, sampled every 5 s by the model's own gate.
///
/// A pid can be recycled between the listing and the click. `ask` records who each pid is (executable and
/// start time) and `confirmQuit` signals only the pids that still are that same process.
@MainActor
final class MemoryScreenModel: ObservableObject {
    enum Outcome: Equatable {
        /// `skipped` pids changed identity (or went away) since the confirmation was shown.
        case asked(String, skipped: Int)
        case failed(String, skipped: Int)
    }

    /// Asks the processes of a row to quit and returns how many requests were delivered.
    typealias Terminator = (MemoryConsumer, [RunningProcess]) -> Int
    typealias Identify = (Int32) -> ProcessIdentity?

    let sampler: ConsumerSampler
    @Published var pending: QuitPrompt?
    @Published private(set) var outcome: Outcome?

    private let environment: () -> SpareEnvironment
    private let terminator: Terminator
    private let identify: Identify
    private let settleDelay: Duration
    /// Identity of each pid of the pending row when the confirmation opened, and how many were left out.
    private var pendingIdentities: [Int32: ProcessIdentity] = [:]
    private var pendingSkipped = 0
    private var forward: AnyCancellable?

    init(
        sampler: ConsumerSampler, environment: @escaping () -> SpareEnvironment,
        settleDelay: Duration = .seconds(2),
        identify: @escaping Identify = { ProcessTerminator.identity(of: $0) },
        terminator: @escaping Terminator = MemoryScreenModel.liveTerminator
    ) {
        self.sampler = sampler
        self.environment = environment
        self.terminator = terminator
        self.identify = identify
        self.settleDelay = settleDelay
        forward = sampler.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    /// Graceful for apps with a bundle, SIGTERM for the rest; the core still refuses Spare, its ancestors
    /// and the system.
    static let liveTerminator: Terminator = { consumer, processes in
        ProcessTerminator.terminate(
            consumer, processes: processes, currentUID: getuid(), ownPID: getpid(), quitter: AppQuitter())
    }

    var consumers: [MemoryConsumer]? { sampler.consumers }
    var failed: Bool { sampler.failed }

    // MARK: Quit

    func ask(_ consumer: MemoryConsumer) {
        let listed = sampler.processes
        pendingIdentities = [:]
        for pid in consumer.pids {
            // The listing can be 15 s old: a pid that is not the listed executable any more is left out.
            if let live = identify(pid), let process = listed[pid], process.executablePath == live.path {
                pendingIdentities[pid] = live
            }
        }
        pendingSkipped = consumer.pids.count - pendingIdentities.count
        pending = QuitPrompt.make(consumer: consumer, processes: listed)
    }

    func cancelPending() {
        pending = nil
        pendingIdentities = [:]
    }

    /// Asks the pending row to quit. Nothing happens without `ask`.
    func confirmQuit() async {
        guard let prompt = pending else { return }
        let identities = pendingIdentities
        var skipped = pendingSkipped
        cancelPending()
        let consumer = prompt.consumer
        // A fresh listing, and only the pids that are still the very same process.
        let environment = environment()
        guard let live = await Task.detached(priority: .userInitiated, operation: { try? environment.memoryProcesses() }).value
        else {
            outcome = .failed(consumer.name, skipped: skipped)
            return
        }
        let same = consumer.pids.filter { identities[$0] != nil && identify($0) == identities[$0] }
        skipped += identities.count - same.count
        let kept = MemoryConsumer(id: consumer.id, name: consumer.name, bytes: consumer.bytes, pids: same,
                                  appBundleID: consumer.appBundleID, isApp: consumer.isApp)
        let delivered = same.isEmpty ? 0 : terminator(kept, live)
        outcome = delivered > 0 ? .asked(consumer.name, skipped: skipped) : .failed(consumer.name, skipped: skipped)
        try? await Task.sleep(for: settleDelay)
        await sampler.sampleIfDue(force: true)
    }

    func dismissOutcome() {
        outcome = nil
    }
}
