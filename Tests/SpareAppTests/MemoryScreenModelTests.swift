import Foundation
import Testing
import SpareCore
import SpareTestSupport
@testable import SpareApp

@MainActor @Suite struct MemoryScreenModelTests {
    func process(_ pid: Int32, name: String, rss: Int64, path: String? = nil, bundle: String? = nil) -> RunningProcess {
        RunningProcess(pid: pid, uid: getuid(), rssBytes: rss,
                       executablePath: path ?? bundle.map { "\($0)/Contents/MacOS/\(name)" } ?? "/opt/\(name)",
                       commandLine: "\(name) --run", appBundlePath: bundle, appBundleID: nil, name: name)
    }

    final class Recorder {
        var consumers: [MemoryConsumer] = []
        var pids: [[Int32]] = []
    }

    /// Who each pid "is" right now; tests change it to simulate a recycled pid.
    final class Identities {
        var table: [Int32: ProcessIdentity] = [:]
        func set(_ pid: Int32, _ path: String, start: Int64 = 1) {
            table[pid] = ProcessIdentity(path: path, startSeconds: start, startMicroseconds: 0)
        }
    }

    func environment(_ processes: [RunningProcess], fails: Bool = false) throws -> SpareEnvironment {
        SpareEnvironment.test(home: try TempHome().url, processes: processes, processListingFails: fails)
    }

    func makeModel(
        processes: [RunningProcess], recorder: Recorder = Recorder(), delivered: Int = 1, listingFails: Bool = false,
        identities: Identities? = nil,
        terminator: MemoryScreenModel.Terminator? = nil
    ) throws -> MemoryScreenModel {
        let env = try environment(processes, fails: listingFails)
        let sampler = ConsumerSampler(environment: { env })
        let ids = identities ?? {
            let ids = Identities()
            for p in processes { ids.set(p.pid, p.executablePath) }
            return ids
        }()
        return MemoryScreenModel(
            sampler: sampler, environment: { env }, settleDelay: .milliseconds(1),
            identify: { ids.table[$0] },
            terminator: terminator ?? { consumer, live in
                recorder.consumers.append(consumer)
                recorder.pids.append(live.map(\.pid))
                return delivered
            })
    }

    @Test func listsTheBiggestUsersFirst() async throws {
        let model = try makeModel(processes: [
            process(100, name: "small", rss: 10), process(101, name: "big", rss: 900), process(102, name: "mid", rss: 90),
        ])
        #expect(model.consumers == nil)
        await model.sampler.sampleIfDue()
        #expect(model.consumers?.map(\.name) == ["big", "mid", "small"])
        #expect(!model.failed)
    }

    @Test func aFailedListingIsAnErrorNotAnEmptyList() async throws {
        let model = try makeModel(processes: [], listingFails: true)
        await model.sampler.sampleIfDue()
        #expect(model.failed)
        #expect(model.consumers == [])
    }

    @Test func nothingIsQuitWithoutAConfirmation() async throws {
        let recorder = Recorder()
        let model = try makeModel(processes: [process(100, name: "node", rss: 10)], recorder: recorder)
        await model.sampler.sampleIfDue()
        await model.confirmQuit()
        #expect(recorder.consumers.isEmpty)

        model.ask(model.consumers![0])
        model.cancelPending()
        await model.confirmQuit()
        #expect(recorder.consumers.isEmpty)
        #expect(model.pending == nil)
    }

    @Test func confirmingQuitsExactlyThePendingRowOnce() async throws {
        let recorder = Recorder()
        let model = try makeModel(processes: [
            process(100, name: "node", rss: 50), process(101, name: "node", rss: 40), process(102, name: "other", rss: 10),
        ], recorder: recorder)
        await model.sampler.sampleIfDue()
        let node = try #require(model.consumers?.first { $0.name == "node" })
        model.ask(node)
        #expect(model.pending?.lines.map(\.pid) == [100, 101])

        await model.confirmQuit()
        #expect(recorder.consumers == [node])
        #expect(recorder.pids == [[100, 101, 102]])  // a fresh listing, to recheck the pids
        #expect(model.outcome == .asked("node", skipped: 0))
        #expect(model.pending == nil)

        await model.confirmQuit()  // a second tap has nothing pending
        #expect(recorder.consumers.count == 1)
    }

    @Test func aRefusedQuitIsReported() async throws {
        let model = try makeModel(processes: [process(100, name: "node", rss: 50)], delivered: 0)
        await model.sampler.sampleIfDue()
        model.ask(model.consumers![0])
        await model.confirmQuit()
        #expect(model.outcome == .failed("node", skipped: 0))
    }

    // MARK: Recycled pids (the real core decides, a recorder stands in for the signal)

    final class Signals: ProcessQuitter, @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [Int32] = []
        var pids: [Int32] { lock.withLock { sent } }
        func quit(_ process: RunningProcess) -> Bool {
            lock.withLock { sent.append(process.pid) }
            return true
        }
    }

    func realCoreTerminator(_ signals: Signals, live: Identities) -> MemoryScreenModel.Terminator {
        { consumer, processes in
            ProcessTerminator.terminate(
                consumer, processes: processes, currentUID: getuid(), ownPID: 1, ancestors: [],
                currentPath: { live.table[$0]?.path }, bundleID: { _ in nil }, quitter: signals)
        }
    }

    @Test func aPidReusedByAnotherExecutableIsNeverSignaled() async throws {
        let ids = Identities()
        ids.set(100, "/opt/node", start: 10)
        ids.set(101, "/opt/node", start: 10)
        let signals = Signals()
        let model = try makeModel(
            processes: [process(100, name: "node", rss: 50, path: "/opt/node"), process(101, name: "node", rss: 40, path: "/opt/node")],
            identities: ids, terminator: realCoreTerminator(signals, live: ids))
        await model.sampler.sampleIfDue()
        model.ask(model.consumers![0])

        // After the prompt opened, pid 100 died and an unrelated program took the number.
        ids.set(100, "/Applications/Photos.app/Contents/MacOS/Photos", start: 99)
        await model.confirmQuit()

        #expect(signals.pids == [101])
        #expect(model.outcome == .asked("node", skipped: 1))
    }

    @Test func aReusedPidWithTheSamePathButANewStartTimeIsSkipped() async throws {
        let ids = Identities()
        ids.set(100, "/opt/node", start: 10)
        let signals = Signals()
        let model = try makeModel(processes: [process(100, name: "node", rss: 50, path: "/opt/node")],
                                  identities: ids, terminator: realCoreTerminator(signals, live: ids))
        await model.sampler.sampleIfDue()
        model.ask(model.consumers![0])
        ids.set(100, "/opt/node", start: 11)
        await model.confirmQuit()

        #expect(signals.pids.isEmpty)
        #expect(model.outcome == .failed("node", skipped: 1))
    }

    @Test func aPidAlreadyReusedWhenThePromptOpensIsLeftOut() async throws {
        // The listing is up to 15 s old: its pid 100 is already another program when the user clicks.
        let ids = Identities()
        ids.set(100, "/opt/other", start: 50)
        ids.set(101, "/opt/node", start: 10)
        let signals = Signals()
        let model = try makeModel(
            processes: [process(100, name: "node", rss: 50, path: "/opt/node"), process(101, name: "node", rss: 40, path: "/opt/node")],
            identities: ids, terminator: realCoreTerminator(signals, live: ids))
        await model.sampler.sampleIfDue()
        model.ask(model.consumers![0])
        await model.confirmQuit()

        #expect(signals.pids == [101])
        #expect(model.outcome == .asked("node", skipped: 1))
    }

    // MARK: Cadence (one `ps`, every 15 s)

    @Test func theListingIsReadEvery15SecondsOnAnInjectedClock() async throws {
        let counter = OutputCapture()
        var env = try environment([process(100, name: "node", rss: 10)])
        let listing = env.memoryProcesses
        env.memoryProcesses = {
            counter.write("ps")
            return try listing()
        }
        let clock = TestClock()
        let sampler = ConsumerSampler(environment: { env }, now: { clock.now })
        func reads() -> Int { counter.text.split(separator: "\n").count }

        await sampler.sampleIfDue()  // first tick of the gate
        #expect(reads() == 1)
        for _ in 0..<2 {  // the 5 s ticks in between reuse the sample
            clock.advance(5)
            await sampler.sampleIfDue()
        }
        #expect(reads() == 1)
        clock.advance(5)  // 15 s
        await sampler.sampleIfDue()
        #expect(reads() == 2)
        clock.advance(5)
        await sampler.sampleIfDue()
        #expect(reads() == 2)
        await sampler.sampleIfDue(force: true)  // after a user action
        #expect(reads() == 3)
    }

    @Test func thePanelAndTheScreenShareOneListing() async throws {
        let counter = OutputCapture()
        let home = try TempHome()
        let big = process(100, name: "Big", rss: 900)
        let model = AppModel(
            home: home.url,
            makeEnvironment: { home, _ in
                var env = SpareEnvironment.test(home: home, processes: [big])
                let listing = env.memoryProcesses
                env.memoryProcesses = {
                    counter.write("ps")
                    return try listing()
                }
                return env
            },
            monitorDisk: false)
        await model.refreshConsumers()  // the panel
        await model.refreshConsumers()  // the next 5 s tick
        await model.consumerSampler.sampleIfDue()  // the Memory screen
        #expect(counter.text.split(separator: "\n").count == 1)
        #expect(model.consumers?.map(\.name) == ["Big"])
        #expect(model.memoryScreen.consumers?.map(\.name) == ["Big"])
    }
}
