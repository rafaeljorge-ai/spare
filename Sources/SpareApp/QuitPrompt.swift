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
            return (pid, process?.rssBytes ?? 0, shorten(process?.commandLine ?? process?.executablePath ?? consumer.name))
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        let lines = members.prefix(maxLines).map { Line(pid: $0.0, command: $0.2) }
        return QuitPrompt(consumer: consumer, lines: Array(lines), hiddenCount: members.count - lines.count)
    }

    static func shorten(_ command: String) -> String {
        let single = command.replacingOccurrences(of: "\n", with: " ")
        guard single.count > maxCommandLength else { return single }
        return String(single.prefix(maxCommandLength - 3)) + "..."
    }
}
