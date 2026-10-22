import Foundation

public struct ScanReportStore: Sendable {
    let file: JSONFileStore<ScanReport>

    public init(directory: URL) {
        file = JSONFileStore(url: directory.appendingPathComponent("last-scan.json"))
    }

    public func load() -> ScanReport? { (try? file.load()) ?? nil }

    public func save(_ report: ScanReport) throws { try file.save(report) }
}
