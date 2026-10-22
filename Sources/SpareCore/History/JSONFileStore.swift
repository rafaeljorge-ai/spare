import Foundation

/// Small JSON file with atomic writes. A corrupt file is renamed, never deleted.
/// The folder is private (0700) and the file owner-only (0600): paths in it are personal data.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `nil` only when the file does not exist or is corrupt (it is then set aside). Any other read failure
    /// (permissions, I/O) throws, so callers never mistake an unreadable history for an empty one.
    public func load() throws -> Value? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            setAsideCorruptFile()
            return nil
        }
    }

    /// Creates the private folder. Only the final folder gets 0700; parents such as `Library` keep the defaults.
    func prepareFolder() throws {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }

    /// Runs `body` holding an exclusive `flock` on `<name>.lock` next to the file, so a read, change and
    /// write cycle cannot interleave with another process or task.
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try prepareFolder()
        let lockPath = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".lock").path
        let descriptor = open(lockPath, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    public func save(_ value: Value) throws {
        let fm = FileManager.default
        try prepareFolder()
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
