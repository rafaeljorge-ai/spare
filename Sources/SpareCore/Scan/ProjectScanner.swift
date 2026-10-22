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
    /// - Returns: artifact directory name -> artifact URLs of idle projects.
    public func artifacts(named: [String: [String]]) -> [String: [URL]] {
        let fm = FileManager.default
        let artifactNames = Set(named.keys)
        var found: [String: [URL]] = [:]
        var idleCache: [String: Bool] = [:]

        for root in roots {
            // Same rule as SafetyGuard: nothing under a `.git` component is ever an artifact.
            if root.resolvingSymlinksInPath().pathComponents.contains(".git") { continue }
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [], errorHandler: { _, _ in true })
            else { continue }

            while let url = enumerator.nextObject() as? URL {
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

                let idle = idleCache[project.path] ?? isIdle(project: project, skipping: artifactNames)
                idleCache[project.path] = idle
                if idle { found[name, default: []].append(url) }
            }
        }
        return found
    }

    /// True when no file outside artifacts and ignored folders changed within `idleDays`.
    public func isIdle(project: URL, skipping artifactNames: Set<String>) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(idleDays) * 86_400)
        guard let enumerator = FileManager.default.enumerator(
            at: project,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey],
            options: [], errorHandler: { _, _ in true })
        else { return false }

        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey])
            if values?.isDirectory == true {
                let name = url.lastPathComponent
                if artifactNames.contains(name) || Self.ignoredForActivity.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isSymbolicLink == true { continue }
            if let modified = values?.contentModificationDate, modified > cutoff { return false }
        }
        return true
    }
}
