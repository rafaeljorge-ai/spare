import Foundation

public enum CategoryID: String, Codable, Sendable, CaseIterable, Hashable {
    case devCaches, projectLeftovers, aiTools, appCaches, logs, installers, trash
    /// Files the user picks on the Large Files screen. No catalog rule uses it.
    case largeFiles
}

public enum Safety: String, Codable, Sendable, Hashable {
    case safe, review
}

public enum CleanAction: Codable, Sendable, Hashable {
    /// Regenerable data: removed for good, frees space immediately.
    case delete
    /// Content that does not regenerate: moved to the Trash, can be undone.
    case trash
    /// The tool's own official cleanup command (it knows its locks).
    case command(executable: String, arguments: [String])
    /// Empties ~/.Trash. The only irreversible removal of user content.
    case emptyTrash
}

public struct InUseHint: Codable, Sendable, Hashable {
    /// Process executable names (or the script name for node/python tools) that block cleanup.
    public var processNames: [String]
    /// Block if any process command line contains the item path (project items: the project path).
    public var checkCommandLines: Bool
    /// Block if a running app's bundle identifier equals the item folder name (~/Library/Caches/<bundle id>).
    public var checkOwningApp: Bool

    public init(processNames: [String] = [], checkCommandLines: Bool = false, checkOwningApp: Bool = false) {
        self.processNames = processNames
        self.checkCommandLines = checkCommandLines
        self.checkOwningApp = checkOwningApp
    }

    public static let none = InUseHint()
}

public enum RuleKind: Codable, Sendable, Hashable {
    /// One item at `home/<path>`.
    case path(String)
    /// Each direct child of `home/<parent>` is an item (hidden entries are ignored).
    case children(parent: String, excludingPrefixes: [String], extensions: [String]?, minAgeDays: Int?)
    /// A folder named `directoryName` inside a configured project root whose parent holds one of `manifests`.
    case projectArtifact(directoryName: String, manifests: [String])
}

public enum SkipReason: String, Codable, Sendable, Hashable {
    case inUse, notFound, outsideCatalog, protected, cancelled, toolNotFound
    /// A project leftover whose project was used again after the scan.
    case projectActive
    /// Tool commands are off on a throwaway home (`SPARE_HOME`), so real tool caches stay safe.
    case toolsDisabled
}

public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let category: CategoryID
    public let kind: RuleKind
    public let safety: Safety
    public let action: CleanAction
    public let inUse: InUseHint

    public init(
        id: String, category: CategoryID, kind: RuleKind, safety: Safety,
        action: CleanAction, inUse: InUseHint = .none
    ) {
        self.id = id
        self.category = category
        self.kind = kind
        self.safety = safety
        self.action = action
        self.inUse = inUse
    }
}
