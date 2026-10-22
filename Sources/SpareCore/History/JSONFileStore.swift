import Foundation

/// Small JSON file with atomic writes. A corrupt file is renamed, never deleted.
/// The folder is private (0700) and the file owner-only (0600): paths in it are personal data.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            setAsideCorruptFile()
            return nil
        }
    }

    public func save(_ value: Value) throws {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        // Only the final folder gets 0700; parents such as `Library` keep the system defaults.
        try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// `<name>.corrupt-<unix time>.json`; a numeric suffix keeps two files from the same second apart.
    private func setAsideCorruptFile() {
        let folder = url.deletingLastPathComponent()
        let stamp = Int(Date().timeIntervalSince1970)
        var aside = folder.appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp).json")
        var attempt = 1
        while FileManager.default.fileExists(atPath: aside.path) {
            attempt += 1
            aside = folder.appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)-\(attempt).json")
        }
        try? FileManager.default.moveItem(at: url, to: aside)
    }
}
