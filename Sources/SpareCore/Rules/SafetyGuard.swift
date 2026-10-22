import Foundation

/// Last line of defense: decides if a path may be touched by a rule.
public struct SafetyGuard: Sendable {
    public let home: URL
    public let projectRoots: [URL]
    let catalog: RuleCatalog
    let now: @Sendable () -> Date

    static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/Applications", "/Library", "/opt", "/cores"]
    static let protectedInHome = [
        ".ssh", ".gnupg", ".aws", ".kube", "Documents", "Desktop", "Pictures", "Movies", "Music",
        "Library", "Library/Keychains", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
    ]
    /// Mail, messages and iCloud Drive: never moved to the Trash from the Large Files screen.
    static let neverTrashInHome = ["Library/Mail", "Library/Messages", "Library/Mobile Documents"]
    static let criticalInHome = [".ssh", ".gnupg", ".aws", ".kube", "Library/Keychains"]

    public init(home: URL, projectRoots: [URL], catalog: RuleCatalog = .standard,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.catalog = catalog
        self.now = now
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
        self.projectRoots = projectRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    /// Same home, project roots and clock as the scan, so both judge a path identically.
    public init(environment: SpareEnvironment, catalog: RuleCatalog = .standard) {
        self.init(home: environment.home, projectRoots: environment.projectRoots, catalog: catalog, now: environment.now)
    }

    public func violation(for url: URL, rule: Rule) -> SkipReason? {
        let path = Self.resolved(url)
        if Self.isSystemPath(path) { return .protected }
        let homePath = home.path
        if path == homePath { return .protected }
        guard path.hasPrefix(homePath + "/") else { return .outsideCatalog }
        let relative = String(path.dropFirst(homePath.count + 1))
        // Protected folders themselves are never items; their subfolders only via explicit rules below.
        if Self.protectedInHome.contains(relative) { return .protected }
        if Self.isInside(relative, any: ["Documents", "Desktop", "Pictures", "Movies", "Music"] + Self.criticalInHome) {
            return .protected
        }

        switch rule.kind {
        case .path(let rulePath):
            return relative == rulePath ? nil : .outsideCatalog
        case .children(let parent, let excluded, let extensions, let minAgeDays):
            let name = (relative as NSString).lastPathComponent
            let itemParent = (relative as NSString).deletingLastPathComponent
            guard itemParent == parent, !name.hasPrefix(".") else { return .outsideCatalog }
            if excluded.contains(where: { name.hasPrefix($0) }) { return .outsideCatalog }
            // Items owned by a more specific `.path` rule never fall under a generic one.
            if catalog.claimedPaths(home: home).contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { return .outsideCatalog }
            if let extensions, !extensions.contains((name as NSString).pathExtension.lowercased()) {
                return .outsideCatalog
            }
            if let minAgeDays {
                let cutoff = now().addingTimeInterval(-Double(minAgeDays) * 86_400)
                let date = (try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard let date, date < cutoff else { return .outsideCatalog }
            }
            return nil
        case .projectArtifact(let directoryName, let manifests):
            guard (path as NSString).lastPathComponent == directoryName else { return .outsideCatalog }
            if path.split(separator: "/").contains(".git") { return .protected }
            guard projectRoots.contains(where: { path.hasPrefix($0.path + "/") }) else { return .outsideCatalog }
            let parent = (path as NSString).deletingLastPathComponent
            let hasManifest = manifests.contains {
                FileManager.default.fileExists(atPath: (parent as NSString).appendingPathComponent($0))
            }
            return hasManifest ? nil : .outsideCatalog
        }
    }

    /// For files the user picked explicitly (Large Files screen).
    public func canTrashUserFile(_ url: URL) -> Bool {
        let path = Self.resolved(url)
        guard !Self.isSystemPath(path), path.hasPrefix(home.path + "/") else { return false }
        let relative = String(path.dropFirst(home.path.count + 1))
        if Self.isInside(relative, any: Self.criticalInHome + Self.neverTrashInHome + [".Trash"]) { return false }
        // Repository internals and volume Trashes are never the user's to pick.
        if relative.split(separator: "/").contains(where: { $0 == ".git" || $0 == ".Trashes" }) { return false }
        // Refuse the protected/critical folders themselves and any folder that contains one.
        let sensitive = Self.criticalInHome + Self.protectedInHome
        return !sensitive.contains { $0 == relative || $0.hasPrefix(relative + "/") }
    }

    static func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func isSystemPath(_ path: String) -> Bool {
        systemPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func isInside(_ relative: String, any folders: [String]) -> Bool {
        folders.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }
}
