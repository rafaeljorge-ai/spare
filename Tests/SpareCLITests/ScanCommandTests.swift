import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct ScanCommandTests {
    @Test func scanJSONIsAScanReport() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".npm/_cacache/index/a", bytes: 50_000)
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: output.write).run(["scan", "--json"])

        #expect(code == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ScanReport.self, from: Data(output.text.utf8))
        #expect(report.items.map(\.ruleID) == ["dev.npm"])
    }

    @Test func scanTextListsCategoriesAndTotals() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".npm/_cacache/index/a", bytes: 50_000)
        let output = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: output.write).run(["scan"])

        #expect(code == 0)
        #expect(output.text.contains("devCaches"))
        #expect(output.text.contains("Safe to free:"))
    }

    @Test func scanRejectsUnknownCategory() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let errors = OutputCapture()

        let code = await SpareCLI(environment: .test(home: home.url), write: output.write, writeError: errors.write)
            .run(["scan", "--category", "nope"])

        #expect(code == 64)
        #expect(errors.text.contains("Unknown category"))
        #expect(output.text.isEmpty)
    }
}
