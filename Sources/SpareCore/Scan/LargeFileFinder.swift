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

/// Why a search could not start. A bad root is an error, never an empty result.
public enum LargeFileError: Error, Equatable, Sendable {
    case notFound(String)
    case notAFolder(String)
    case systemFolder(String)
}

extension LargeFileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let path): return "No such folder: \(path)"
        case .notAFolder(let path): return "Not a folder (links are never followed): \(path)"
        case .systemFolder(let path): return "System folders are never searched: \(path)"
        }
    }
}

/// Result of a search. `partial` is true when it was cancelled before the whole folder was walked.
public struct LargeFileSearch: Sendable {
    public let files: [LargeFile]
    public let partial: Bool

    public init(files: [LargeFile], partial: Bool) {
        self.files = files
        self.partial = partial
    }
}

/// Finds the biggest regular files under a folder. Read-only.
///
/// - Never follows symlinks (files, folders or the root itself) and stays on the root's volume.
/// - Does not enter system folders, packages (`.app`, `.photoslibrary`...), `.git`, the Trash, dependency
///   folders other categories already cover (`node_modules`, `.venv`, `.next`, `target`, `DerivedData`),
///   `~/Library` (unless `includeLibrary`) or the places `SafetyGuard.canTrashUserFile` would refuse.
/// - Keeps only the `limit` biggest files in a small heap, so memory stays flat on a huge home.
/// - Cancellable: checks `Task.isCancelled` every 1,000 entries (call it from the task you cancel).
public enum LargeFileFinder {
    static let checkEvery = 1_000
    static let skippedNames: Set<String> = ["node_modules", ".venv", ".next", "target", "DerivedData", ".git"]

    /// Non-throwing form: a bad root gives an empty list. Prefer `search` when the reason matters.
    public static func find(
        in root: URL, minBytes: Int64, limit: Int = 20, home: URL? = nil, includeLibrary: Bool = false,
        isPackage: (@Sendable (String) -> Bool)? = nil,
        deviceOf: (@Sendable (String) -> Int64)? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) -> [LargeFile] {
        (try? search(in: root, minBytes: minBytes, limit: limit, home: home, includeLibrary: includeLibrary,
                     isPackage: isPackage, deviceOf: deviceOf, progress: progress))?.files ?? []
    }

    /// - Parameter home: the home whose protected folders are skipped; defaults to the current user's home.
    public static func search(
        in root: URL, minBytes: Int64, limit: Int = 20, home: URL? = nil, includeLibrary: Bool = false,
        isPackage: (@Sendable (String) -> Bool)? = nil,
        deviceOf: (@Sendable (String) -> Int64)? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> LargeFileSearch {
        guard limit > 0 else { return LargeFileSearch(files: [], partial: false) }
        let root = root.standardizedFileURL
        var info = stat()
        guard lstat(root.path, &info) == 0 else { throw LargeFileError.notFound(root.path) }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { throw LargeFileError.notAFolder(root.path) }
        guard !SafetyGuard.isSystemPath(SafetyGuard.resolved(root)) else { throw LargeFileError.systemFolder(root.path) }

        let rootDevice = deviceOf?(root.path) ?? Int64(info.st_dev)
        let home = home ?? FileManager.default.homeDirectoryForCurrentUser
        let pruned = prunedPaths(home: home, includeLibrary: includeLibrary)
        // `fts` walks with one `lstat` per entry and no Foundation objects: about 10 times faster than
        // `FileManager.enumerator` on a whole home. Links are never followed; `/Volumes` is skipped explicitly.
        guard let rootPath = strdup(root.path) else { throw LargeFileError.notFound(root.path) }
        defer { free(rootPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil)
        else { throw LargeFileError.notFound(root.path) }
        defer { fts_close(fts) }

        var best = BiggestFiles(limit: limit)
        var visited = 0
        var partial = false
        while let entry = fts_read(fts) {
            visited += 1
            if visited % checkEvery == 0 {
                if Task.isCancelled { partial = true; break }
                progress?(String(cString: entry.pointee.fts_path))
            }
            if entry.pointee.fts_level == 0 { continue }
            switch Int32(entry.pointee.fts_info) {
            case FTS_D:
                let path = String(cString: entry.pointee.fts_path)
                // Another volume mounted inside (network share, disk image, FUSE) is not entered, unless the
                // root is `/` itself.
                let device = deviceOf?(path) ?? entry.pointee.fts_statp.map { Int64($0.pointee.st_dev) } ?? rootDevice
                if root.path != "/" && device != rootDevice {
                    fts_set(fts, entry, FTS_SKIP)
                    continue
                }
                let name = path.split(separator: "/").last.map(String.init) ?? path
                if skippedNames.contains(name) || pruned.contains(path) || looksLikePackage(name, path, ask: isPackage) {
                    fts_set(fts, entry, FTS_SKIP)
                }
            case FTS_F:
                guard let info = entry.pointee.fts_statp?.pointee, (info.st_mode & S_IFMT) == S_IFREG else { continue }
                // Allocated size, like Finder's "size on disk" (sparse files and clones count what they use).
                let size = Int64(info.st_blocks) * 512
                if size >= minBytes {
                    let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
                    best.offer(LargeFile(url: url, sizeBytes: size, lastOpened: nil))
                }
            default:
                break
            }
        }
        let files = best.sorted().map { file in
            LargeFile(url: file.url, sizeBytes: file.sizeBytes,
                      lastOpened: (try? file.url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate)
        }
        return LargeFileSearch(files: files, partial: partial)
    }

    /// Bundle folders that behave as one file in Finder; their insides are never listed.
    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
        "bundle", "framework", "plugin", "appex", "kext", "xcodeproj", "xcworkspace", "rtfd", "sparsebundle",
        "dsym", "vst", "vst3", "component", "prefpane", "qlgenerator", "mdimporter", "xpc", "saver",
        "pvm", "utm", "vmwarevm", "logicx", "band", "pages", "numbers", "key", "xcarchive", "mlpackage", "lrdata",
    ]

    /// Fast path: the known list. Any other folder with an extension is asked to Launch Services
    /// (`isPackageKey`), so unknown bundles (VMs, project files) are never listed by their insides.
    static func looksLikePackage(_ name: String, _ path: String, ask: (@Sendable (String) -> Bool)?) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        if packageExtensions.contains(name[name.index(after: dot)...].lowercased()) { return true }
        if let ask { return ask(path) }
        return (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    /// Folders never entered: system prefixes and, for the home, its protected places, the Trash and `Library`.
    static func prunedPaths(home: URL, includeLibrary: Bool) -> Set<String> {
        var paths = Set(SafetyGuard.systemPrefixes + ["/Volumes"])
        var relative = SafetyGuard.criticalInHome + SafetyGuard.neverTrashInHome + [".Trash"]
        if !includeLibrary { relative.append("Library") }
        // The home may be spelled with or without symlinks (/var and /private/var). `standardizedFileURL`
        // would rewrite one spelling into the other, so the spellings are built with `realpath` instead.
        var bases = [home.standardizedFileURL.path]
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
