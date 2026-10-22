import Foundation

public struct InUseGuard: Sendable {
    public let processes: [RunningProcess]

    public init(processes: [RunningProcess]) {
        self.processes = processes
    }

    /// `ScanItem.inUseBy` value when the process list could not be read: never shown as free to clean.
    public static let unknownReason = "unknown"

    /// Whether the rule depends on knowing the running processes (official-command rules do not).
    public static func needsCheck(_ rule: Rule) -> Bool {
        if case .command = rule.action { return false }
        return rule.inUse != .none
    }

    /// Display name of what is using the item, or nil when it is free to clean.
    public func reason(rule: Rule, url: URL) -> String? {
        if case .command = rule.action { return nil }  // the tool handles its own locks
        let hint = rule.inUse

        if !hint.processNames.isEmpty {
            let names = Set(hint.processNames.map { $0.lowercased() })
            if let match = processes.first(where: {
                names.contains($0.executableName.lowercased()) || names.contains($0.scriptName?.lowercased() ?? "")
            }) {
                return match.name
            }
        }

        if hint.checkCommandLines {
            let isProject: Bool
            let base: URL
            if case .projectArtifact = rule.kind {
                isProject = true
                base = url.deletingLastPathComponent()
            } else {
                isProject = false
                base = url
            }
            let targets = Self.spellings(of: base)
            // A shell parked in a project folder is not using node_modules, so project items skip the cwd check.
            if let match = processes.first(where: {
                Self.mentions($0, targets: targets) || (!isProject && Self.runsInside($0, targets: targets))
            }) {
                return match.name
            }
        }

        if hint.checkOwningApp {
            let folder = url.lastPathComponent
            if let match = processes.first(where: { $0.appBundleID == folder }) {
                return match.name
            }
        }
        return nil
    }

    /// The path as processes may spell it: `/var` and `/private/var` name the same folder.
    static func spellings(of url: URL) -> [String] {
        var paths = [url.path, url.resolvingSymlinksInPath().path]
        for path in paths {
            if path.hasPrefix("/private/") {
                paths.append(String(path.dropFirst("/private".count)))
            } else if ["/var/", "/tmp/", "/etc/"].contains(where: { path.hasPrefix($0) }) {
                paths.append("/private" + path)
            }
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// The path appears whole (not as a prefix of a longer name) in the command line or executable path.
    static func mentions(_ process: RunningProcess, targets: [String]) -> Bool {
        targets.contains { target in
            process.commandLine.contains(target + "/") || process.commandLine.hasSuffix(target)
                || process.commandLine.contains(target + " ") || process.executablePath.hasPrefix(target + "/")
        }
    }

    /// The process's working directory is the folder or inside it.
    static func runsInside(_ process: RunningProcess, targets: [String]) -> Bool {
        guard let cwd = process.cwd else { return false }
        return targets.contains { cwd == $0 || cwd.hasPrefix($0 + "/") }
    }
}
