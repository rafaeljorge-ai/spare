import Foundation

public struct LargeFile: Codable, Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let sizeBytes: Int64
    public let lastOpened: Date?

    public init(url: URL, sizeBytes: Int64, lastOpened: Date?) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastOpened = lastOpened
    }
}

/// Finds the biggest regular files under a folder. Read-only.
///
/// - Never follows symlinks (files, folders or the root itself).
/// - Does not enter system folders, packages (`.app`, `.photoslibrary`...), `.git`, the Trash or the places
///   `SafetyGuard.canTrashUserFile` would refuse (keys, Mail, Messages, iCloud Drive).
/// - Keeps only the `limit` biggest files in a small heap, so memory stays flat on a huge home.
/// - Cancellable: checks `Task.isCancelled` every 1,000 entries (call it from the task you cancel).
public enum LargeFileFinder {
    static let checkEvery = 1_000

    /// - Parameter home: when given, the protected folders of that home are skipped.
    public static func find(
        in root: URL, minBytes: Int64, limit: Int = 20, home: URL? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) -> [LargeFile] {
        guard limit > 0 else { return [] }
        var info = stat()
        guard lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              !SafetyGuard.isSystemPath(SafetyGuard.resolved(root))
        else { return [] }

        let pruned = prunedPaths(home: home)
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .isPackageKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentAccessDateKey,
        ]
        let keySet = Set(keys)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true })
        else { return [] }

        var best = BiggestFiles(limit: limit)
        var visited = 0
        while true {
            // Foundation hands back autoreleased URLs: drain them per entry so memory does not grow.
            let finished: Bool = autoreleasepool {
                guard let url = enumerator.nextObject() as? URL else { return true }
                visited += 1
                if visited % checkEvery == 0 {
                    if Task.isCancelled { return true }
                    progress?(url.path)
                }
                guard let values = try? url.resourceValues(forKeys: keySet) else { return false }
                if values.isSymbolicLink == true { return false }
                if values.isDirectory == true {
                    if values.isPackage == true || url.lastPathComponent == ".git" || pruned.contains(url.path) {
                        enumerator.skipDescendants()
                    }
                    return false
                }
                guard values.isRegularFile == true,
                      let size = (values.totalFileAllocatedSize ?? values.fileAllocatedSize).map(Int64.init),
                      size >= minBytes
                else { return false }
                best.offer(LargeFile(url: url, sizeBytes: size, lastOpened: values.contentAccessDate))
                return false
            }
            if finished { break }
        }
        return best.sorted()
    }

    /// Folders never entered: system prefixes and, with a home, its protected places and the Trash.
    static func prunedPaths(home: URL?) -> Set<String> {
        var paths = Set(SafetyGuard.systemPrefixes)
        guard let home else { return paths }
        let relative = SafetyGuard.criticalInHome + SafetyGuard.neverTrashInHome + [".Trash"]
        // The home may be spelled with or without symlinks (/var and /private/var). `standardizedFileURL`
        // would rewrite one spelling into the other, so the spellings are built with `realpath` instead.
        var bases = [home.path]
        if let real = realpath(home.path, nil) {
            bases.append(String(cString: real))
            free(real)
        }
        for base in bases {
            for folder in relative { paths.insert(base + "/" + folder) }
        }
        return paths
    }
}

/// The `limit` biggest files seen so far, in a min-heap: the root is the one to drop first.
struct BiggestFiles {
    private(set) var heap: [LargeFile] = []
    let limit: Int

    init(limit: Int) {
        self.limit = limit
        heap.reserveCapacity(limit)
    }

    /// True when `a` should leave the heap before `b`: smaller, or equal size and later path.
    private static func drops(_ a: LargeFile, before b: LargeFile) -> Bool {
        a.sizeBytes != b.sizeBytes ? a.sizeBytes < b.sizeBytes : a.url.path > b.url.path
    }

    mutating func offer(_ file: LargeFile) {
        if heap.count < limit {
            heap.append(file)
            siftUp(heap.count - 1)
        } else if let root = heap.first, Self.drops(root, before: file) {
            heap[0] = file
            siftDown(0)
        }
    }

    /// Biggest first; ties by path.
    func sorted() -> [LargeFile] {
        heap.sorted { Self.drops($1, before: $0) }
    }

    private mutating func siftUp(_ start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.drops(heap[child], before: heap[parent]) else { return }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(_ start: Int) {
        var parent = start
        while true {
            let left = 2 * parent + 1, right = left + 1
            var smallest = parent
            if left < heap.count, Self.drops(heap[left], before: heap[smallest]) { smallest = left }
            if right < heap.count, Self.drops(heap[right], before: heap[smallest]) { smallest = right }
            if smallest == parent { return }
            heap.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
