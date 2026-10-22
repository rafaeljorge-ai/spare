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
        let processes = runningProcesses(for: items)
        var completedCommands: [String: CleanupEntry] = [:]
        var entries: [CleanupEntry] = []

        for (index, item) in items.enumerated() {
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
            entries.append(entry)
            progress(CleanProgress(index: index, total: items.count, entry: entry))
        }

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
        guard let root = roots.first(where: { path.hasPrefix($0.path + "/") }) else { return false }
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
        } catch {
            entry.status = .failed
            entry.detail = error.localizedDescription
        }
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
