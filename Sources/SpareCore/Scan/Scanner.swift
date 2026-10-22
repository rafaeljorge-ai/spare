import Foundation

public struct Scanner: Sendable {
    public let environment: SpareEnvironment
    public let catalog: RuleCatalog
    static let maxConcurrentMeasurements = 4

    public init(environment: SpareEnvironment, catalog: RuleCatalog = .standard) {
        self.environment = environment
        self.catalog = catalog
    }

    public func scan(
        categories: Set<CategoryID>? = nil,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async -> ScanReport {
        let startedAt = environment.now()
        let freeBefore = environment.diskSpace(environment.home)?.freeBytes
        let rules = catalog.rules.filter { categories?.contains($0.category) ?? true }

        let projectRules = rules.filter { if case .projectArtifact = $0.kind { true } else { false } }
        let projectFound = projectRules.isEmpty ? [:] : projectArtifacts(for: projectRules)
        var candidates: [(Rule, URL)] = []
        for rule in rules where !Task.isCancelled {
            if case .projectArtifact(let name, _) = rule.kind {
                candidates += (projectFound[name] ?? []).map { (rule, $0) }
            } else {
                candidates += self.candidates(for: rule).map { (rule, $0) }
            }
        }

        // A failed listing is not "nothing running": items that need the check become "unknown", never free.
        let inUse = try? InUseGuard(processes: environment.processes())
        var pendingPerCategory = Dictionary(grouping: candidates, by: { $0.0.category }).mapValues(\.count)
        var items: [ScanItem] = []
        var completed = 0
        let total = candidates.count

        await withTaskGroup(of: (CategoryID, String, ScanItem?).self) { group in
            var iterator = candidates.makeIterator()
            func addNext() {
                guard let (rule, url) = iterator.next() else { return }
                group.addTask { (rule.category, url.path, Self.measure(rule: rule, url: url)) }
            }
            for _ in 0..<Self.maxConcurrentMeasurements { addNext() }
            while let (category, path, measured) = await group.next() {
                completed += 1
                var item = measured
                if var found = item {
                    if let rule = catalog.rule(id: found.ruleID) {
                        if let inUse {
                            found.inUseBy = inUse.reason(rule: rule, url: found.url)
                        } else if InUseGuard.needsCheck(rule) {
                            found.inUseBy = InUseGuard.unknownReason
                        }
                    }
                    item = found
                    items.append(found)
                }
                pendingPerCategory[category, default: 1] -= 1
                let finished = pendingPerCategory[category] == 0 ? category : nil
                if item != nil || finished != nil {
                    progress(ScanProgress(currentPath: path, completed: completed, total: total,
                                          item: item, finishedCategory: finished))
                }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                addNext()
            }
        }

        items.sort { $0.sizeBytes > $1.sizeBytes }
        return ScanReport(items: items, startedAt: startedAt, finishedAt: environment.now(),
                          freeBytesBefore: freeBefore, cancelled: Task.isCancelled)
    }

    static func measure(rule: Rule, url: URL) -> ScanItem? {
        let size = SizeCalculator.allocatedSize(of: url)
        guard size > 0 else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ScanItem(ruleID: rule.id, category: rule.category, url: url, sizeBytes: size,
                        safety: rule.safety, lastModified: modified)
    }

    /// Paths a rule points at right now.
    public func candidates(for rule: Rule) -> [URL] {
        let fm = FileManager.default
        switch rule.kind {
        case .path(let relative):
            let url = environment.home.appendingPathComponent(relative)
            return fm.fileExists(atPath: url.path) ? [url] : []
        case .children(let parent, let excluded, let extensions, let minAgeDays):
            let dir = environment.home.appendingPathComponent(parent)
            let claimed = catalog.claimedPaths(home: environment.home)
            guard let children = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
            else { return [] }
            let cutoff = minAgeDays.map { environment.now().addingTimeInterval(-Double($0) * 86_400) }
            return children.filter { child in
                let name = child.lastPathComponent
                if name.hasPrefix(".") { return false }
                if excluded.contains(where: { name.hasPrefix($0) }) { return false }
                // Same normalization on both sides: enumeration may return /private/var for /var.
                let childPath = child.resolvingSymlinksInPath().path
                if claimed.contains(where: { $0 == childPath || $0.hasPrefix(childPath + "/") }) { return false }
                if let extensions, !extensions.contains(child.pathExtension.lowercased()) { return false }
                if let cutoff {
                    let date = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    guard let date, date < cutoff else { return false }
                }
                return true
            }
        case .projectArtifact(let directoryName, _):
            return projectArtifacts()[directoryName] ?? []
        }
    }

    func projectArtifacts(for rules: [Rule]) -> [String: [URL]] {
        var named: [String: [String]] = [:]
        for rule in rules {
            if case .projectArtifact(let name, let manifests) = rule.kind { named[name] = manifests }
        }
        return ProjectScanner(roots: environment.projectRoots, idleDays: environment.projectIdleDays,
                              now: environment.now()).artifacts(named: named)
    }

    func projectArtifacts() -> [String: [URL]] {
        projectArtifacts(for: catalog.rules)
    }
}
