import Foundation
import Testing
import SpareCore
import SpareTestSupport
@testable import SpareApp

@MainActor @Suite struct MemoryScreenModelTests {
    func process(_ pid: Int32, name: String, rss: Int64, bundle: String? = nil) -> RunningProcess {
        RunningProcess(pid: pid, uid: getuid(), rssBytes: rss, executablePath: bundle.map { "\($0)/Contents/MacOS/\(name)" } ?? "/opt/\(name)",
                       commandLine: "\(name) --run", appBundlePath: bundle, appBundleID: nil, name: name)
    }

    final class Recorder {
        var consumers: [MemoryConsumer] = []
        var pids: [[Int32]] = []
    }

    func makeModel(
        processes: [RunningProcess], recorder: Recorder = Recorder(), delivered: Int = 1,
        listingFails: Bool = false, interval: Duration = .seconds(60)
    ) throws -> MemoryScreenModel {
        let home = try TempHome()
        let environment = SpareEnvironment.test(home: home.url, processes: processes, processListingFails: listingFails)
        return MemoryScreenModel(
            environment: { environment }, interval: interval, settleDelay: .milliseconds(1),
            terminator: { consumer, live in
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
        await model.refresh()
        #expect(model.consumers?.map(\.name) == ["big", "mid", "small"])
        #expect(!model.failed)
    }

    @Test func aFailedListingIsAnErrorNotAnEmptyList() async throws {
        let model = try makeModel(processes: [], listingFails: true)
        await model.refresh()
        #expect(model.failed)
        #expect(model.consumers == [])
    }

    @Test func nothingIsQuitWithoutAConfirmation() async throws {
        let recorder = Recorder()
        let model = try makeModel(processes: [process(100, name: "node", rss: 10)], recorder: recorder)
        await model.refresh()
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
        await model.refresh()
        let node = try #require(model.consumers?.first { $0.name == "node" })
        model.ask(node)
        #expect(model.pending?.lines.map(\.pid) == [100, 101])

        await model.confirmQuit()
        #expect(recorder.consumers == [node])
        #expect(recorder.pids == [[100, 101, 102]])  // a fresh listing, to recheck the pids
        #expect(model.outcome == .asked("node"))
        #expect(model.pending == nil)

        await model.confirmQuit()  // a second tap has nothing pending
        #expect(recorder.consumers.count == 1)
    }

    @Test func aRefusedQuitIsReported() async throws {
        let model = try makeModel(processes: [process(100, name: "node", rss: 50)], delivered: 0)
        await model.refresh()
        model.ask(model.consumers![0])
        await model.confirmQuit()
        #expect(model.outcome == .failed("node"))
    }

    @Test func sampledOnlyWhileTheScreenIsVisible() async throws {
        let counter = OutputCapture()
        let home = try TempHome()
        var environment = SpareEnvironment.test(home: home.url, processes: [process(100, name: "node", rss: 10)])
        let listing = environment.memoryProcesses
        environment.memoryProcesses = {
            counter.write("listed")
            return try listing()
        }
        let model = MemoryScreenModel(environment: { environment }, interval: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(100))
        #expect(counter.text.isEmpty)

        model.setVisible(true)
        try await Task.sleep(for: .milliseconds(150))
        model.setVisible(false)
        try await Task.sleep(for: .milliseconds(50))
        let seen = counter.text.split(separator: "\n").count
        #expect(seen > 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(counter.text.split(separator: "\n").count == seen)
    }

    @Test func consumersRefreshEvery15Seconds() {
        #expect(MemoryScreenModel.refreshSeconds == 15)
        #expect(AppModel.memoryRefreshSeconds == 5)
    }
}
