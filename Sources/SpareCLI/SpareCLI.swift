import Foundation
import SpareCore

public struct SpareCLI: Sendable {
    public let environment: SpareEnvironment
    let write: @Sendable (String) -> Void
    let writeError: @Sendable (String) -> Void
    /// Base for relative paths (`--trash ./a.bin`). Injected so tests never change the process folder.
    let currentDirectory: URL

    /// `writeError` receives failures so they never pollute piped stdout (e.g. `--json | jq`).
    /// It falls back to `write` when omitted.
    public init(
        environment: SpareEnvironment,
        write: @escaping @Sendable (String) -> Void,
        writeError: (@Sendable (String) -> Void)? = nil,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) {
        self.currentDirectory = currentDirectory
        self.environment = environment
        self.write = write
        self.writeError = writeError ?? write
    }

    public static let usage = """
        spare: keep your Mac's disk and memory in check

        USAGE:
          spare status [--json]      Free disk space and memory
          spare scan [--json] [--category ID]   Preview what can be freed (changes nothing)
          spare rules                Rule IDs for clean
          spare clean --rule ID [--rule ID] [--yes] [--dry-run]   Clean the items of these rules
                                     (only a preview without --yes; --dry-run always previews)
          spare undo [RECORD_ID] [--dry-run]   Restore trashed items of the last (or given) cleanup
          spare purge [RECORD_ID] [--yes] [--dry-run]   Permanently delete Spare's own items from the Trash
                                     (only a preview without --yes; the rest of the Trash is never touched)
          spare history [--json]     Past cleanups
          spare large [PATH] [--min-mb 500] [--limit 20] [--include-library] [--json]   Biggest files under PATH (default: home)
                                     (~/Library is skipped unless --include-library)
          spare large --trash FILE [--trash FILE] [--yes] [--dry-run]   Move chosen files to the Trash, with Undo
                                     (only a preview without --yes; --dry-run always previews)
          spare memory [--json]      Memory pressure and top consumers (approximate: shared memory is counted per process)
          spare help                 Show this help
        """

    public func run(_ arguments: [String]) async -> Int32 {
        var args = arguments
        let json = args.contains("--json")
        args.removeAll { $0 == "--json" }
        guard let command = args.first else {
            write(Self.usage)
            return 0
        }
        switch command {
        case "status":
            return status(json: json)
        case "scan":
            return await scan(Array(args.dropFirst()), json: json)
        case "rules":
            return rules()
        case "clean":
            return await clean(Array(args.dropFirst()), json: json)
        case "undo":
            return undo(Array(args.dropFirst()))
        case "purge":
            return purge(Array(args.dropFirst()))
        case "history":
            return history(json: json)
        case "large":
            return large(Array(args.dropFirst()), json: json)
        case "memory":
            return memory(json: json)
        case "help", "--help", "-h":
            write(Self.usage)
            return 0
        default:
            writeError("Unknown command: \(command)\n\n\(Self.usage)")
            return 64
        }
    }

    func status(json: Bool) -> Int32 {
        guard let disk = environment.diskSpace(environment.home) else {
            writeError("Could not read disk space")
            return 1
        }
        let memory = environment.memory()
        if json {
            write(Self.encode(StatusOutput(disk: disk, memory: memory)))
        } else {
            write("Free: \(ByteFormat.string(disk.freeBytes)) of \(ByteFormat.string(disk.totalBytes))")
            if let memory { write(Self.memoryLine(memory)) }
        }
        return 0
    }

    static func memoryLine(_ memory: MemorySnapshot) -> String {
        "Memory (approx.): \(ByteFormat.string(memory.usedBytes)) of \(ByteFormat.string(memory.totalBytes)) used (pressure: \(memory.level.rawValue))"
    }

    // MARK: Memory

    func listProcesses() -> [RunningProcess]? {
        do {
            return try environment.memoryProcesses()
        } catch {
            writeError("Could not list running processes")
            return nil
        }
    }

    func memory(json: Bool) -> Int32 {
        guard let processes = listProcesses() else { return 1 }
        let snapshot = environment.memory()
        let consumers = MemoryMonitor.topConsumers(
            processes: processes, currentUID: getuid(), ownPID: ProcessInfo.processInfo.processIdentifier)
        if json {
            write(Self.encode(MemoryOutput(snapshot: snapshot, consumers: consumers)))
            return 0
        }
        if let snapshot { write(Self.memoryLine(snapshot)) }
        write("Top consumers (approximate: shared memory is counted in every process that uses it):")
        for consumer in consumers {
            write("  ~\(ByteFormat.string(consumer.bytes))  \(consumer.name)  pids: \(consumer.pids.map(String.init).joined(separator: ","))")
        }
        return 0
    }

    func scan(_ args: [String], json: Bool) async -> Int32 {
        var categories: Set<CategoryID>?
        let names = Self.option("--category", in: args)
        if !names.isEmpty {
            let parsed = names.compactMap(CategoryID.init(rawValue:))
            guard parsed.count == names.count else {
                writeError("Unknown category. Valid: \(CategoryID.allCases.map(\.rawValue).joined(separator: ", "))")
                return 64
            }
            categories = Set(parsed)
        }
        let report = await Scanner(environment: environment).scan(categories: categories)
        if json {
            write(Self.encode(report))
            return 0
        }
        for category in CategoryID.allCases {
            let items = report.items(in: category)
            guard !items.isEmpty else { continue }
            write("\(category.rawValue): \(ByteFormat.string(report.totalBytes(in: category))) in \(items.count) item(s)")
            for item in items {
                let flag = item.inUseBy.map { " [in use: \($0)]" } ?? ""
                write("  \(item.safety.rawValue)  \(ByteFormat.string(item.sizeBytes))  \(item.url.path)\(flag)")
            }
        }
        write("Safe to free: \(ByteFormat.string(report.safeReclaimableBytes))")
        write("To review: \(ByteFormat.string(report.reviewBytes))")
        return 0
    }

    // MARK: Cleaning

    var historyStore: HistoryStore { HistoryStore(directory: environment.supportDirectory) }

    func rules() -> Int32 {
        for rule in RuleCatalog.standard.rules {
            write("\(rule.id)  \(rule.category.rawValue)  \(rule.safety.rawValue)")
        }
        return 0
    }

    /// Cleans only with `--yes`, and never with `--dry-run`. Anything else is a preview.
    func clean(_ args: [String], json: Bool) async -> Int32 {
        let ruleIDs = Self.option("--rule", in: args)
        let rules = ruleIDs.compactMap { RuleCatalog.standard.rule(id: $0) }
        guard !ruleIDs.isEmpty, rules.count == ruleIDs.count else {
            writeError("Pass one or more valid --rule IDs (see: spare rules)")
            return 64
        }
        let report = await Scanner(environment: environment).scan(categories: Set(rules.map(\.category)))
        // Items in use (including "unknown", when the check failed) are never offered for cleaning.
        let items = report.items.filter { ruleIDs.contains($0.ruleID) && $0.inUseBy == nil }
        let total = items.reduce(Int64(0)) { $0 + $1.sizeBytes }

        guard args.contains("--yes"), !args.contains("--dry-run") else {
            if json {
                write(Self.encode(items))
            } else {
                write("Would clean \(items.count) item(s), \(ByteFormat.string(total)):")
                items.forEach { write("  \(ByteFormat.string($0.sizeBytes))  \($0.url.path)") }
                write(args.contains("--dry-run") ? "Dry run: nothing was changed." : "Run again with --yes to clean.")
            }
            return 0
        }

        let record = await Cleaner(environment: environment).clean(items)
        var historySaved = true
        do {
            try historyStore.append(record)
        } catch {
            historySaved = false
            writeError("Could not save the cleanup history (\(error.localizedDescription)). Items already in the Trash cannot be undone with Spare.")
        }
        if json {
            write(Self.encode(record))
        } else {
            let done = record.entries.filter { $0.status == .done }.count
            write("Cleaned \(ByteFormat.string(record.cleanedBytes)) in \(done) item(s).")
            for entry in record.entries where entry.status != .done {
                write("  \(entry.status.rawValue) (\(entry.skipReason?.rawValue ?? entry.detail ?? "")): \(entry.originalPath)")
            }
            if record.trashedBytes > 0 {
                write("\(ByteFormat.string(record.trashedBytes)) went to the Trash. Undo: spare undo \(record.id). Free it now: spare purge \(record.id) --yes")
            }
        }
        if !historySaved { return 74 }
        return record.entries.contains { $0.status == .failed } ? 1 : 0
    }

    enum RecordTarget {
        case record(UUID)
        case none
        case invalid(String)
    }

    /// The record named by the first positional argument, else the most recent one.
    func target(_ args: [String]) throws -> RecordTarget {
        if let given = args.first(where: { !$0.hasPrefix("--") }) {
            return UUID(uuidString: given).map(RecordTarget.record) ?? .invalid(given)
        }
        return try historyStore.load().first.map { .record($0.id) } ?? .none
    }

    /// "Not found" is a different failure from a history file that cannot be read or written.
    func report(_ error: any Error, id: UUID?) -> Int32 {
        if let error = error as? HistoryError, error == .recordNotFound {
            writeError("No cleanup with id \(id?.uuidString ?? "").")
            return 1
        }
        writeError("Could not use the cleanup history: \(error.localizedDescription)")
        return 74
    }

    /// The record to act on, or the exit code to return right away.
    func resolveTarget(_ args: [String], verb: String) -> Result<UUID, ExitCode> {
        do {
            switch try target(args) {
            case .record(let id): return .success(id)
            case .none:
                writeError("No cleanup to \(verb).")
                return .failure(ExitCode(1))
            case .invalid(let text):
                writeError("Not a valid cleanup id: \(text)")
                return .failure(ExitCode(64))
            }
        } catch {
            return .failure(ExitCode(report(error, id: nil)))
        }
    }

    struct ExitCode: Error {
        let value: Int32
        init(_ value: Int32) { self.value = value }
    }

    func undo(_ args: [String]) -> Int32 {
        let id: UUID
        switch resolveTarget(args, verb: "undo") {
        case .success(let found): id = found
        case .failure(let code): return code.value
        }
        do {
            if args.contains("--dry-run") {
                let preview = try historyStore.previewUndo(recordID: id, trash: environment.trash)
                write("Would restore \(preview.wouldRestore.count) item(s):")
                preview.wouldRestore.forEach { write("  \(ByteFormat.string($0.sizeBytes))  \($0.originalPath)") }
                preview.failures.forEach { writeError("  Would stay in the Trash (\($0.reason.message)): \($0.path)") }
                write("Dry run: nothing was changed.")
                return 0
            }
            let result = try historyStore.undo(recordID: id, trash: environment.trash)
            write("Restored \(result.restored) item(s).")
            result.failures.forEach { writeError("  Kept in the Trash (\($0.reason.message)): \($0.path)") }
            return result.failures.isEmpty ? 0 : 1
        } catch {
            return report(error, id: id)
        }
    }

    func purge(_ args: [String]) -> Int32 {
        let id: UUID
        switch resolveTarget(args, verb: "purge") {
        case .success(let found): id = found
        case .failure(let code): return code.value
        }
        do {
            guard args.contains("--yes"), !args.contains("--dry-run") else {
                let pending = try historyStore.pendingPurge(recordID: id, trash: environment.trash)
                let total = pending.reduce(Int64(0)) { $0 + $1.sizeBytes }
                write("Would delete forever \(pending.count) item(s), \(ByteFormat.string(total)), that Spare moved to the Trash:")
                pending.forEach { write("  \(ByteFormat.string($0.sizeBytes))  \($0.originalPath)") }
                write(args.contains("--dry-run") ? "Dry run: nothing was changed." : "Run again with --yes to delete.")
                return 0
            }
            let result = try historyStore.purge(recordID: id, trash: environment.trash)
            write("Freed \(ByteFormat.string(result.freedBytes)) from the Trash.")
            result.failures.forEach { writeError("  Not deleted (\($0.message)): \($0.path)") }
            return result.failures.isEmpty ? 0 : 1
        } catch {
            return report(error, id: id)
        }
    }

    func history(json: Bool) -> Int32 {
        let records: [CleanupRecord]
        do {
            records = try historyStore.load()
        } catch {
            return report(error, id: nil)
        }
        if json {
            write(Self.encode(records))
            return 0
        }
        if records.isEmpty { write("No cleanups yet.") }
        for record in records {
            // Purged items were cleaned too: count them with the ones still done.
            let bytes = record.entries.filter { $0.status == .done || $0.status == .purged }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }
            write("\(record.id)  \(record.startedAt.formatted())  \(ByteFormat.string(bytes))  \(record.entries.count) item(s)")
        }
        return 0
    }

    static func option(_ name: String, in args: [String]) -> [String] {
        var values: [String] = []
        var index = 0
        while index < args.count {
            if args[index] == name, index + 1 < args.count {
                values.append(args[index + 1])
                index += 2
            } else {
                index += 1
            }
        }
        return values
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct StatusOutput: Codable {
    let disk: DiskSpace
    let memory: MemorySnapshot?
}

struct MemoryOutput: Codable {
    let snapshot: MemorySnapshot?
    let consumers: [MemoryConsumer]
}
