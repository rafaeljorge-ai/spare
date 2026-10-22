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
}
