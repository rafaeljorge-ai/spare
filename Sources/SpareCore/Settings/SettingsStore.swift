import Foundation

public struct SettingsStore: Sendable {
    let file: JSONFileStore<SpareSettings>

    public init(directory: URL) {
        file = JSONFileStore(url: directory.appendingPathComponent("settings.json"))
    }

    public func load(home: URL) -> SpareSettings {
        (try? file.load()) ?? .defaults(home: home)
    }

    public func save(_ settings: SpareSettings) throws {
        try file.save(settings)
    }
}
