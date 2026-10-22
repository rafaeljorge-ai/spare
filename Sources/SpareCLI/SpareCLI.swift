import Foundation
import SpareCore

public struct SpareCLI: Sendable {
    public let environment: SpareEnvironment
    let write: @Sendable (String) -> Void

    public init(environment: SpareEnvironment, write: @escaping @Sendable (String) -> Void) {
        self.environment = environment
        self.write = write
    }

    public static let usage = """
        spare: keep your Mac's disk and memory in check

        USAGE:
          spare status [--json]      Free disk space
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
        case "help", "--help", "-h":
            write(Self.usage)
            return 0
        default:
            write("Unknown command: \(command)\n\n\(Self.usage)")
            return 64
        }
    }

    func status(json: Bool) -> Int32 {
        guard let disk = environment.diskSpace(environment.home) else {
            write("Could not read disk space")
            return 1
        }
        if json {
            write(Self.encode(StatusOutput(disk: disk)))
        } else {
            write("Free: \(ByteFormat.string(disk.freeBytes)) of \(ByteFormat.string(disk.totalBytes))")
        }
        return 0
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
