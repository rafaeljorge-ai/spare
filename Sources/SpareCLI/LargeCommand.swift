import Foundation
import SpareCore

extension SpareCLI {
    /// `spare large [PATH] [--min-mb N] [--limit N] [--include-library]` lists the biggest files (read-only).
    /// `spare large --trash FILE... [--yes] [--dry-run]` moves chosen files to the Trash, recorded in the history
    /// so `spare undo` works. Like `clean`, it only previews without `--yes`, and `--dry-run` always previews.
    func large(_ args: [String], json: Bool) -> Int32 {
        let valueFlags = ["--min-mb", "--limit", "--trash"]
        for flag in valueFlags where args.filter({ $0 == flag }).count != Self.option(flag, in: args).count {
            writeError("\(flag) needs a value")
            return 64
        }
        if !Self.option("--trash", in: args).isEmpty { return trash(args, json: json) }

        let minText = Self.option("--min-mb", in: args).last ?? "500"
        let limitText = Self.option("--limit", in: args).last ?? "20"
        guard let minMB = Int64(minText), minMB > 0, minMB <= 1_000_000_000, let limit = Int(limitText), limit > 0 else {
            writeError("--min-mb and --limit must be positive numbers")
            return 64
        }
        let root = Self.positional(args, valueFlags: valueFlags).first.map { URL(fileURLWithPath: $0) } ?? environment.home
        let files: [LargeFile]
        do {
            files = try LargeFileFinder.search(
                in: root, minBytes: minMB * 1_000_000, limit: limit, home: environment.home,
                includeLibrary: args.contains("--include-library")).files
        } catch {
            writeError(error.localizedDescription)
            return 66
        }
        if json {
            write(Self.encode(files))
        } else {
            if files.isEmpty { write("No files above \(minMB) MB.") }
            files.forEach { write("\(ByteFormat.string($0.sizeBytes))  \($0.url.path)") }
        }
        return 0
    }

    /// Arguments that are neither a flag nor the value of one.
    static func positional(_ args: [String], valueFlags: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < args.count {
            if valueFlags.contains(args[index]) {
                index += 2
            } else {
                if !args[index].hasPrefix("--") { result.append(args[index]) }
                index += 1
            }
        }
        return result
    }

    /// A previewed file, with whether the guard would refuse it.
    private struct Preview: Encodable {
        let url: URL
        let sizeBytes: Int64
        let lastOpened: Date?
        let isProtected: Bool

        init(file: LargeFile, isProtected: Bool) {
            url = file.url
            sizeBytes = file.sizeBytes
            lastOpened = file.lastOpened
            self.isProtected = isProtected
        }

        enum CodingKeys: String, CodingKey {
            case url, sizeBytes, lastOpened
            case isProtected = "protected"
        }
    }

    /// Makes a path absolute against the current folder. Paths with `.` or `..` get their folder resolved by the
    /// system (the file itself is never resolved, so a link stays a link and is refused later).
    static func absolute(_ path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        guard url.pathComponents.contains(where: { $0 == "." || $0 == ".." }), last != "." && last != ".." else {
            return url
        }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(last)
    }

    private func trash(_ args: [String], json: Bool) -> Int32 {
        let files = Self.option("--trash", in: args).map { path -> LargeFile in
            let url = Self.absolute(path)
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .contentAccessDateKey])
            return LargeFile(url: url, sizeBytes: Int64(values?.totalFileAllocatedSize ?? 0),
                             lastOpened: values?.contentAccessDate)
        }
        guard args.contains("--yes"), !args.contains("--dry-run") else {
            let guardian = SafetyGuard(environment: environment)
            let total = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
            if json {
                write(Self.encode(files.map { Preview(file: $0, isProtected: !guardian.canTrashUserFile($0.url)) }))
            } else {
                write("Would move \(files.count) file(s), \(ByteFormat.string(total)), to the Trash:")
                for file in files {
                    let note = guardian.canTrashUserFile(file.url) ? "" : " [protected, would be skipped]"
                    write("  \(ByteFormat.string(file.sizeBytes))  \(file.url.path)\(note)")
                }
                write(args.contains("--dry-run") ? "Dry run: nothing was changed." : "Run again with --yes to move.")
            }
            return 0
        }

        let record = LargeFileCleaner(environment: environment).trash(files)
        var historySaved = true
        // Nothing moved, nothing to undo: no history entry.
        if record.entries.contains(where: { $0.status == .done }) {
            do {
                try historyStore.append(record)
            } catch {
                historySaved = false
                writeError("Could not save the cleanup history (\(error.localizedDescription)). Files already in the Trash cannot be undone with Spare.")
            }
        }
        if json {
            write(Self.encode(record))
        } else {
            let done = record.entries.filter { $0.status == .done }.count
            write("Moved \(done) file(s), \(ByteFormat.string(record.cleanedBytes)), to the Trash.")
            if record.trashedBytes > 0 {
                write("Undo: spare undo \(record.id). Free it now: spare purge \(record.id) --yes")
            }
        }
        for entry in record.entries where entry.status != .done {
            writeError("  \(entry.status.rawValue) (\(entry.skipReason?.rawValue ?? entry.detail ?? "")): \(entry.originalPath)")
        }
        if !historySaved { return 74 }
        return record.entries.allSatisfy({ $0.status == .done }) ? 0 : 1
    }
}
