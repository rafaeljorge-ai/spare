import Foundation

/// Executes a cleanup. Every guard runs again right before each item is touched; any doubt skips it.
public struct Cleaner: Sendable {
    public let environment: SpareEnvironment
    public let catalog: RuleCatalog

    public init(environment: SpareEnvironment, catalog: RuleCatalog = .standard) {
        self.environment = environment
        self.catalog = catalog
    }

    public func clean(
        _ items: [ScanItem],
        progress: @escaping @Sendable (CleanProgress) -> Void = { _ in }
    ) async -> CleanupRecord {
        let startedAt = environment.now()
        let freeBefore = environment.diskSpace(environment.home)?.freeBytes
        let guardian = SafetyGuard(environment: environment, catalog: catalog)
        // The same path twice in one run is one item. Emptying the Trash goes first, so it can never
        // destroy something this run just moved there (the record would claim it is undoable).
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.url.path).inserted }
        let order = unique.indices.filter { Self.emptiesTrash(unique[$0], catalog) }
            + unique.indices.filter { !Self.emptiesTrash(unique[$0], catalog) }
        let processes = runningProcesses(for: unique)
        var completedCommands: [String: CleanupEntry] = [:]
        var results: [CleanupEntry?] = Array(repeating: nil, count: unique.count)

        for (step, index) in order.enumerated() {
            let item = unique[index]
            var entry = CleanupEntry(ruleID: item.ruleID, category: item.category, originalPath: item.url.path,
                                     action: .delete, sizeBytes: item.sizeBytes, status: .skipped)
            if let rule = catalog.rule(id: item.ruleID) {
                entry.action = ActionKind(rule.action)
                if Task.isCancelled {
                    entry.skipReason = .cancelled
                } else if let user = item.inUseBy {
                    // The scan already saw it in use (or could not tell, "unknown"): never cleaned.
                    entry.skipReason = .inUse
                    entry.detail = user
                } else if Self.isNotNormalized(item.url) {
                    // `..` can name a different place once symlinks are followed than the one the guard checks.
                    entry.skipReason = .outsideCatalog
                } else if let violation = guardian.violation(for: item.url, rule: rule) {
                    entry.skipReason = violation
                } else if !Self.exists(item.url) {
                    entry.skipReason = .notFound
                } else if let user = inUseNow(rule: rule, url: item.url, processes: processes) {
                    entry.skipReason = .inUse
                    entry.detail = user
                } else if !isStillIdle(rule: rule, url: item.url) {
                    entry.skipReason = .projectActive
                } else if case .command = rule.action, let previous = completedCommands[rule.id] {
                    entry.status = previous.status
                    entry.skipReason = previous.skipReason
                    entry.detail = previous.detail
                } else {
                    perform(rule.action, on: item.url, entry: &entry)
                    if case .command = rule.action { completedCommands[rule.id] = entry }
                }
            } else {
                entry.skipReason = .outsideCatalog
            }
            results[index] = entry
            progress(CleanProgress(index: step, total: unique.count, entry: entry))
        }
        let entries = results.compactMap { $0 }

        return CleanupRecord(
            startedAt: startedAt, finishedAt: environment.now(), freeBytesBefore: freeBefore,
            freeBytesAfter: environment.diskSpace(environment.home)?.freeBytes,
            entries: entries, cancelled: Task.isCancelled)
    }

    /// One listing for the whole run. `nil` means it failed: items that need the check are skipped.
    /// Not listed at all when no item depends on it.
    private func runningProcesses(for items: [ScanItem]) -> Result<InUseGuard, any Error> {
        let needed = items.contains { item in
            catalog.rule(id: item.ruleID).map(InUseGuard.needsCheck) ?? false
        }
        guard needed else { return .success(InUseGuard(processes: [])) }
        return Result { InUseGuard(processes: try environment.processes()) }
    }

    /// Process name using the item, `InUseGuard.unknownReason` when the listing failed, nil when free.
    private func inUseNow(rule: Rule, url: URL, processes: Result<InUseGuard, any Error>) -> String? {
        guard InUseGuard.needsCheck(rule) else { return nil }
        switch processes {
        case .success(let guardian): return guardian.reason(rule: rule, url: url)
        case .failure: return InUseGuard.unknownReason
        }
    }

    /// Project leftovers only: the project (measured at its repository root) was not used since the scan.
    /// Anything that cannot be measured counts as active.
    private func isStillIdle(rule: Rule, url: URL) -> Bool {
        guard case .projectArtifact = rule.kind else { return true }
        let path = SafetyGuard.resolved(url)
        let roots = environment.projectRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        // Outermost root that contains the item: the widest view of the repository wins.
        guard let root = roots.filter({ path.hasPrefix($0.path + "/") }).min(by: { $0.path.count < $1.path.count })
        else { return false }
        let scanner = ProjectScanner(roots: roots, idleDays: environment.projectIdleDays, now: environment.now())
        let project = URL(fileURLWithPath: path).deletingLastPathComponent()
        let measured = scanner.repositoryRoot(of: project, within: root) ?? project
        let artifactNames = Set(catalog.rules.compactMap { rule -> String? in
            if case .projectArtifact(let name, _) = rule.kind { return name }
            return nil
        })
        return scanner.isIdle(project: measured, skipping: artifactNames)
    }

    func perform(_ action: CleanAction, on url: URL, entry: inout CleanupEntry) {
        do {
            switch action {
            case .delete:
                try FileManager.default.removeItem(at: url)
            case .trash:
                entry.trashPath = try environment.trash.moveToTrash(url).path
            case .command(let executable, let arguments):
                let result = try environment.commandRunner.run(executable, arguments)
                guard result.exitCode == 0 else {
                    entry.status = .failed
                    entry.detail = String(result.output.suffix(300))
                    return
                }
            case .emptyTrash:
                let fm = FileManager.default
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) {
                    try fm.removeItem(at: child)
                }
            }
            entry.status = .done
        } catch CommandError.notFound {
            entry.status = .skipped
            entry.skipReason = .toolNotFound
        } catch CommandError.timedOut(let tool) {
            entry.status = .failed
            entry.detail = "\(tool) took too long and was stopped"
        } catch {
            entry.status = .failed
            entry.detail = error.localizedDescription
        }
    }

    static func emptiesTrash(_ item: ScanItem, _ catalog: RuleCatalog) -> Bool {
        if case .emptyTrash? = catalog.rule(id: item.ruleID)?.action { return true }
        return false
    }

    /// True when the path has `.` or `..` components or is not absolute.
    static func isNotNormalized(_ url: URL) -> Bool {
        !url.isFileURL || !url.path.hasPrefix("/") || url.pathComponents.contains { $0 == ".." || $0 == "." }
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
