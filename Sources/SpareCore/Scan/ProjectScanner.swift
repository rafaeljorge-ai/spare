import Foundation

public struct ProjectScanner: Sendable {
    public static let maxDepth = 6
    public static let conventionalRoots = ["Projetos", "Projects", "dev", "Developer", "code"]
    /// Folders that never count as "recent activity" and are never descended into.
    static let ignoredForActivity: Set<String> = [".git", "dist", "build", ".turbo", ".cache"]

    public let roots: [URL]
    public let idleDays: Int
    public let now: Date

    public init(roots: [URL], idleDays: Int, now: Date) {
        self.roots = roots
        self.idleDays = idleDays
        self.now = now
    }

    public static func defaultRoots(home: URL) -> [URL] {
        conventionalRoots
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
    }

    /// - Parameter named: artifact directory name -> manifest file names (any one is enough).
    /// - Parameter progress: called with each root and each candidate artifact it is about to inspect.
    /// - Returns: artifact directory name -> artifact URLs of idle projects. Honors task cancellation:
    ///   the result then holds only what was already confirmed idle.
    public func artifacts(
        named: [String: [String]], progress: (String) -> Void = { _ in }
    ) -> [String: [URL]] {
        let fm = FileManager.default
        let artifactNames = Set(named.keys)
        var found: [String: [URL]] = [:]
        var idleCache: [String: Bool] = [:]

        for root in roots {
            if Task.isCancelled { break }
            progress(root.path)
            // Same rule as SafetyGuard: nothing under a `.git` component is ever an artifact.
            if root.resolvingSymlinksInPath().pathComponents.contains(".git") { continue }
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [], errorHandler: { _, _ in true })
            else { continue }

            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                let name = url.lastPathComponent
                if enumerator.level > Self.maxDepth || Self.ignoredForActivity.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                guard artifactNames.contains(name) else { continue }
                enumerator.skipDescendants()

                let project = url.deletingLastPathComponent()
                let manifests = named[name] ?? []
                let hasManifest = manifests.contains {
                    fm.fileExists(atPath: project.appendingPathComponent($0).path)
                }
                guard hasManifest else { continue }
                progress(url.path)

                // Activity is measured at the whole repository when there is one, so a monorepo
                // package is only idle if every package is.
                let measured = repositoryRoot(of: project, within: root) ?? project
                let idle = idleCache[measured.path] ?? isIdle(project: measured, skipping: artifactNames)
                idleCache[measured.path] = idle
                if idle { found[name, default: []].append(url) }
            }
        }
        return found
    }

    /// Outermost folder from `project` up to `root` (inclusive) that holds a `.git` entry.
    /// A directory or a file counts, because worktrees and submodules use a `.git` file.
    func repositoryRoot(of project: URL, within root: URL) -> URL? {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var current = project.standardizedFileURL
        var outermost: URL?
        while current.path == rootPath || current.path.hasPrefix(rootPath + "/") {
            if fm.fileExists(atPath: current.appendingPathComponent(".git").path) { outermost = current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return outermost
    }

    /// True when nothing outside ignored folders was modified or created within `idleDays`.
    /// Artifact folders are not descended into, but their own dates count (fresh `npm install`).
    public func isIdle(project: URL, skipping artifactNames: Set<String>) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(idleDays) * 86_400)
        guard let enumerator = FileManager.default.enumerator(
            at: project,
            includingPropertiesForKeys: Self.activityKeys,
            options: [], errorHandler: { _, _ in true })
        else { return false }
        let activityKeys = Set(Self.activityKeys)

        while let url = enumerator.nextObject() as? URL {
            // Cancelled mid-walk: not proven idle, so the project is never offered for cleaning.
            if Task.isCancelled { return false }
            let values = try? url.resourceValues(forKeys: activityKeys)
            if values?.isDirectory == true {
                let name = url.lastPathComponent
                if Self.ignoredForActivity.contains(name) {
                    enumerator.skipDescendants()
                } else if artifactNames.contains(name) {
                    enumerator.skipDescendants()
                    if isRecent(values, after: cutoff) { return false }
                }
                continue
            }
            if values?.isSymbolicLink == true { continue }
            if isRecent(values, after: cutoff) { return false }
        }
        return true
    }

    private static let activityKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey,
    ]

    /// Modification or creation date newer than the cutoff. Creation counts because unzipping or
    /// restoring a backup keeps old modification dates.
    private func isRecent(_ values: URLResourceValues?, after cutoff: Date) -> Bool {
        if let modified = values?.contentModificationDate, modified > cutoff { return true }
        if let created = values?.creationDate, created > cutoff { return true }
        return false
    }
}
