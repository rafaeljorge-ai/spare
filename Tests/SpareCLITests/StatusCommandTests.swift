import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct StatusCommandTests {
    @Test func statusJSONReportsDiskSpace() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url), write: output.write)

        let code = await cli.run(["status", "--json"])

        #expect(code == 0)
        struct Status: Decodable { let disk: DiskSpace; let memory: MemorySnapshot? }
        let status = try JSONDecoder().decode(Status.self, from: Data(output.text.utf8))
        #expect(status.disk.freeBytes == 10_000_000_000)
        #expect(status.disk.totalBytes == 100_000_000_000)
        #expect(status.memory != nil)
    }

    @Test func statusTextIsHumanReadable() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url), write: output.write)

        let code = await cli.run(["status"])

        #expect(code == 0)
        #expect(output.text.contains("Free:"))
        #expect(output.text.contains("Memory"))
    }

    @Test func unknownCommandFailsWithUsage() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url), write: output.write)

        let code = await cli.run(["explode"])

        #expect(code == 64)
        #expect(output.text.contains("USAGE"))
    }

    @Test func unknownCommandWritesToErrorStream() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url), write: output.write, writeError: errors.write)

        let code = await cli.run(["explode", "--json"])

        #expect(code == 64)
        #expect(output.text.isEmpty)
        #expect(errors.text.contains("Unknown command: explode"))
    }

    @Test func unreadableDiskFailsOnErrorStream() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url, disk: nil), write: output.write, writeError: errors.write)

        let code = await cli.run(["status", "--json"])

        #expect(code == 1)
        #expect(output.text.isEmpty)
        #expect(errors.text.contains("Could not read disk space"))
    }
}
