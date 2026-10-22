import Foundation

/// Last line of defense: decides if a path may be touched by a rule.
public struct SafetyGuard: Sendable {
    public let home: URL
    public let projectRoots: [URL]

    static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/Applications", "/Library", "/opt", "/cores"]
    static let protectedInHome = [
        ".ssh", ".gnupg", ".aws", ".kube", "Documents", "Desktop", "Pictures", "Movies", "Music",
        "Library", "Library/Keychains", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
    ]
    static let criticalInHome = [".ssh", ".gnupg", ".aws", ".kube", "Library/Keychains"]

    public init(home: URL, projectRoots: [URL]) {
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
        self.projectRoots = projectRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
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
        case .children(let parent, let excluded, _, _):
            let name = (relative as NSString).lastPathComponent
            let itemParent = (relative as NSString).deletingLastPathComponent
            guard itemParent == parent, !name.hasPrefix(".") else { return .outsideCatalog }
            return excluded.contains(where: { name.hasPrefix($0) }) ? .outsideCatalog : nil
        case .projectArtifact(let directoryName, _):
            guard (path as NSString).lastPathComponent == directoryName else { return .outsideCatalog }
            let insideRoot = projectRoots.contains { path.hasPrefix($0.path + "/") }
            return insideRoot ? nil : .outsideCatalog
        }
    }

    /// For files the user picked explicitly (Large Files screen).
    public func canTrashUserFile(_ url: URL) -> Bool {
        let path = Self.resolved(url)
        guard !Self.isSystemPath(path), path.hasPrefix(home.path + "/") else { return false }
        let relative = String(path.dropFirst(home.path.count + 1))
        return !Self.isInside(relative, any: Self.criticalInHome) && !Self.criticalInHome.contains(relative)
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
