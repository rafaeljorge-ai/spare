import Foundation
import SpareCore

/// What the "Quit?" confirmation shows. A row that groups several processes (a "node" with workers, an app
/// with helpers) lists their pids and commands, so the user sees exactly what will be asked to quit.
struct QuitPrompt: Identifiable, Equatable {
    struct Line: Equatable {
        let pid: Int32
        let command: String
    }

    static let maxLines = 6
    static let maxCommandLength = 90

    let consumer: MemoryConsumer
    /// Biggest processes first; at most `maxLines`.
    let lines: [Line]
    /// Processes of the row that are not listed.
    let hiddenCount: Int

    var id: String { consumer.id }
    var isGrouped: Bool { consumer.pids.count > 1 }

    static func make(consumer: MemoryConsumer, processes: [Int32: RunningProcess]) -> QuitPrompt {
        guard consumer.pids.count > 1 else {
            return QuitPrompt(consumer: consumer, lines: [], hiddenCount: 0)
        }
        let members = consumer.pids.map { pid -> (Int32, Int64, String) in
            let process = processes[pid]
            return (pid, process?.rssBytes ?? 0, display(process?.commandLine ?? process?.executablePath ?? consumer.name))
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        let lines = members.prefix(maxLines).map { Line(pid: $0.0, command: $0.2) }
        return QuitPrompt(consumer: consumer, lines: Array(lines), hiddenCount: members.count - lines.count)
    }

    /// The executable and its first argument that is not a flag (`node server.js`), with secrets masked.
    /// Command lines often carry tokens and passwords, so nothing else is shown.
    static func display(_ commandLine: String) -> String {
        let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = tokens.first else { return "" }
        var shown = [executable]
        if let argument = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) { shown.append(argument) }
        return shorten(redact(shown.joined(separator: " ")))
    }

    static let secretWords = ["token", "key", "secret", "pass", "auth", "cred"]

    static func isSecretKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return secretWords.contains { lower.contains($0) }
    }

    /// Masks `--x=value` and `-x value` when the key names a secret, and `user:password@` in URLs.
    static func redact(_ command: String) -> String {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [String] = []
        var maskNext = false
        for token in tokens {
            if maskNext {
                maskNext = false
                if !token.hasPrefix("-") { result.append("***"); continue }
            }
            var token = maskCredentials(in: token)
            if token.hasPrefix("-") {
                if let equals = token.firstIndex(of: "=") {
                    if isSecretKey(String(token[..<equals])) { token = String(token[...equals]) + "***" }
                } else if isSecretKey(token) {
                    maskNext = true
                }
            }
            result.append(token)
        }
        return result.joined(separator: " ")
    }

    private static func maskCredentials(in token: String) -> String {
        guard let scheme = token.range(of: "://"), let at = token.range(of: "@", range: scheme.upperBound..<token.endIndex),
              token[scheme.upperBound..<at.lowerBound].contains(":") else { return token }
        return String(token[..<scheme.upperBound]) + "***" + String(token[at.lowerBound...])
    }

    static func shorten(_ command: String) -> String {
        guard command.count > maxCommandLength else { return command }
        return String(command.prefix(maxCommandLength - 3)) + "..."
    }
}
