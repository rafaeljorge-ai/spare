import Foundation
import SpareCore

public struct SpareCLI: Sendable {
    public let environment: SpareEnvironment
    let write: @Sendable (String) -> Void
    let writeError: @Sendable (String) -> Void

    /// `writeError` receives failures so they never pollute piped stdout (e.g. `--json | jq`).
    /// It falls back to `write` when omitted.
    public init(
        environment: SpareEnvironment,
        write: @escaping @Sendable (String) -> Void,
        writeError: (@Sendable (String) -> Void)? = nil
    ) {
        self.environment = environment
        self.write = write
        self.writeError = writeError ?? write
    }

    public static let usage = """
        spare: keep your Mac's disk and memory in check

        USAGE:
          spare status [--json]      Free disk space
          spare scan [--json] [--category ID]   Preview what can be freed (changes nothing)
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
        if json {
            write(Self.encode(StatusOutput(disk: disk)))
        } else {
            write("Free: \(ByteFormat.string(disk.freeBytes)) of \(ByteFormat.string(disk.totalBytes))")
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
}
