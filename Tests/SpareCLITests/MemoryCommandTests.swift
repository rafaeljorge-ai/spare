import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct MemoryCommandTests {
    func node(_ pid: Int32 = 10, bytes: Int64 = 5_000_000) -> RunningProcess {
        RunningProcess(pid: pid, uid: getuid(), rssBytes: bytes, executablePath: "/opt/homebrew/bin/node",
                       commandLine: "node", appBundlePath: nil, appBundleID: nil, name: "node")
    }

    @Test func memoryJSONHasSnapshotAndConsumers() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url, processes: [node()]), write: output.write)
            .run(["memory", "--json"])

        #expect(code == 0)
        struct Out: Decodable { let snapshot: MemorySnapshot; let consumers: [MemoryConsumer] }
        let decoded = try JSONDecoder().decode(Out.self, from: Data(output.text.utf8))
        #expect(decoded.consumers.map(\.name) == ["node"])
        #expect(decoded.snapshot.level == .normal)
    }

    @Test func memoryTextSaysTheNumbersAreApproximate() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url, processes: [node()]), write: output.write)
            .run(["memory"])

        #expect(code == 0)
        #expect(output.text.contains("approx"))
        #expect(output.text.contains("node"))
    }

    @Test func memoryFailsOnTheErrorStreamWhenProcessesCannotBeListed() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url, processListingFails: true),
                                  write: output.write, writeError: errors.write).run(["memory", "--json"])

        #expect(code == 1)
        #expect(output.text.isEmpty)
        #expect(errors.text.contains("Could not list running processes"))
    }

    @Test func quitWithoutYesOnlyPreviews() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let signals = SignalRecorder()
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url, processes: [node()], signals: signals), write: output.write)
            .run(["quit", "node"])

        #expect(code == 0)
        #expect(signals.sent.isEmpty)
        #expect(output.text.contains("--yes"))
    }

    @Test func quitDryRunWinsOverYes() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let signals = SignalRecorder()

        let code = await SpareCLI(environment: .test(home: home.url, processes: [node()], signals: signals), write: { _ in })
            .run(["quit", "node", "--yes", "--dry-run"])

        #expect(code == 0)
        #expect(signals.sent.isEmpty)
    }

    @Test func quitWithYesSendsSIGTERMOnly() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let signals = SignalRecorder()
        let output = OutputCapture()
        let env = SpareEnvironment.test(home: home.url, processes: [node()], signals: signals)

        let code = await SpareCLI(environment: env, write: output.write).run(["quit", "node", "--yes"])

        #expect(code == 0)
        #expect(signals.sent.map(\.0) == [10])
        #expect(signals.sent.map(\.1) == [SIGTERM])
    }

    @Test func quitUnknownNameFailsOnTheErrorStream() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let signals = SignalRecorder()
        let errors = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url, processes: [node()], signals: signals),
                                  write: { _ in }, writeError: errors.write).run(["quit", "ghost", "--yes"])

        #expect(code == 64)
        #expect(signals.sent.isEmpty)
        #expect(errors.text.contains("ghost"))
    }

    @Test func quitWithoutATargetFails() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let errors = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: { _ in }, writeError: errors.write)
            .run(["quit", "--yes"])

        #expect(code == 64)
        #expect(!errors.text.isEmpty)
    }
}
