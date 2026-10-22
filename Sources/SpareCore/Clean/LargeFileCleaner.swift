import Foundation

/// Moves files the user picked on the Large Files screen to the Trash. Reuses the Cleaner's move, so
/// each item gets the same `trashIdentity` stamp and Undo works through `HistoryStore`.
public struct LargeFileCleaner: Sendable {
    public static let ruleID = "user.largeFile"
    public let environment: SpareEnvironment

    public init(environment: SpareEnvironment) {
        self.environment = environment
    }

    public func trash(_ files: [LargeFile]) -> CleanupRecord {
        let startedAt = environment.now()
        let freeBefore = environment.diskSpace(environment.home)?.freeBytes
        let guardian = SafetyGuard(environment: environment)
        let cleaner = Cleaner(environment: environment)
        // The same path twice in one run is one item.
        var seen = Set<String>()
        let unique = files.filter { seen.insert($0.url.path).inserted }

        let entries = unique.map { file -> CleanupEntry in
            var entry = CleanupEntry(ruleID: Self.ruleID, category: .largeFiles, originalPath: file.url.path,
                                     action: .trash, sizeBytes: file.sizeBytes, status: .skipped)
            if Task.isCancelled {
                entry.skipReason = .cancelled
            } else if Cleaner.isNotNormalized(file.url) {
                entry.skipReason = .outsideCatalog
            } else if !Cleaner.exists(file.url) {
                entry.skipReason = .notFound
            } else if !Self.isRegularFile(file.url) {
                // A folder, or a link put in the file's place after the scan: only real files are moved.
                entry.skipReason = .outsideCatalog
            } else if !guardian.canTrashUserFile(file.url) {
                entry.skipReason = .protected
            } else {
                cleaner.perform(.trash, on: file.url, entry: &entry)
            }
            return entry
        }
        return CleanupRecord(
            startedAt: startedAt, finishedAt: environment.now(), freeBytesBefore: freeBefore,
            freeBytesAfter: environment.diskSpace(environment.home)?.freeBytes,
            entries: entries, cancelled: Task.isCancelled)
    }

    static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }
}
