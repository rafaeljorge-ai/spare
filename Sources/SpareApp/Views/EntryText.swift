import SpareCore
import SwiftUI

/// Why an entry looks the way it does, in words. Matched on the entry itself, never on an index.
enum EntryNote: Equatable {
    case inUse(String)
    case notVerified
    case alreadyGone
    case protected
    case stopped
    case toolMissing
    case projectActive
    case failed(String)
    case restored
    case purged
    case inTrash
    case none

    init(_ entry: CleanupEntry) {
        switch entry.skipReason {
        case .inUse?:
            if entry.detail == InUseGuard.unknownReason || entry.detail == nil {
                self = .notVerified
            } else {
                self = .inUse(entry.detail ?? "")
            }
        case .notFound?: self = .alreadyGone
        case .outsideCatalog?, .protected?: self = .protected
        case .cancelled?: self = .stopped
        case .toolNotFound?: self = .toolMissing
        case .projectActive?: self = .projectActive
        case nil:
            switch entry.status {
            case .failed: self = .failed(entry.detail ?? "")
            case .restored: self = .restored
            case .purged: self = .purged
            case .done: self = entry.action == .trash ? .inTrash : .none
            case .skipped: self = .none
            }
        }
    }

    var text: Text? {
        switch self {
        case .inUse(let name): Text("In use by \(name)")
        case .notVerified: Text("Not verified")
        case .alreadyGone: Text("Already gone")
        case .protected: Text("Protected, not touched")
        case .stopped: Text("Stopped")
        case .toolMissing: Text("Tool not installed")
        case .projectActive: Text("Project used again, left alone")
        case .failed(let message): Text("Failed: \(message)")
        case .restored: Text("Restored")
        case .purged: Text("Deleted from the Trash")
        case .inTrash: Text("In the Trash")
        case .none: nil
        }
    }
}

/// Name people recognize: the tool for single-path rules, `project/folder` for project leftovers.
enum ItemName {
    static let tools: [String: String] = [
        "dev.npm": "npm", "dev.pnpm": "pnpm", "dev.yarn": "Yarn", "dev.uv": "uv", "dev.pip": "pip",
        "dev.cargo": "Cargo", "dev.homebrew": "Homebrew", "dev.xcodeDerivedData": "Xcode DerivedData",
        "dev.preCommit": "pre-commit", "dev.playwright": "Playwright", "ai.huggingface": "Hugging Face",
        "ai.whisper": "Whisper", "ai.ollama": "Ollama", "ai.lmstudio": "LM Studio", "ai.claudeVM": "Claude VM",
    ]

    static func of(ruleID: String, category: CategoryID, path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if category == .projectLeftovers {
            return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
        }
        return tools[ruleID] ?? url.lastPathComponent
    }

    static func of(_ item: ScanItem) -> String {
        of(ruleID: item.ruleID, category: item.category, path: item.url.path)
    }

    static func of(_ entry: CleanupEntry) -> String {
        of(ruleID: entry.ruleID, category: entry.category, path: entry.originalPath)
    }
}

/// What happens to the entry's row: waiting, working, or its outcome.
enum CleanRowState: Equatable {
    case waiting
    case working
    case finished(CleanupEntry)
}

/// One line of the progress and result lists.
struct CleanRow: View {
    let name: String
    let sizeBytes: Int64
    let state: CleanRowState

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(Txt.label).foregroundStyle(state == .waiting ? Ink.tertiary : Ink.primary)
                if let note {
                    note.font(Txt.caption).foregroundStyle(noteColor)
                }
            }
            Spacer(minLength: 12)
            Text(verbatim: ByteFormat.string(sizeBytes))
                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(state == .waiting ? Ink.tertiary : Ink.primary)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private var note: Text? {
        if case .finished(let entry) = state { return EntryNote(entry).text }
        return nil
    }

    private var noteColor: Color {
        guard case .finished(let entry) = state else { return Ink.tertiary }
        switch EntryNote(entry) {
        case .inUse, .notVerified, .failed: return Ink.busy
        case .projectActive, .stopped: return Ink.review
        default: return Ink.tertiary
        }
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .waiting:
            Image(systemName: "circle").foregroundStyle(Ink.muted)
        case .working:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        case .finished(let entry):
            switch entry.status {
            case .done, .restored, .purged:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.spare)
            case .skipped:
                Image(systemName: entry.skipReason == .inUse ? "lock.fill" : "minus.circle")
                    .foregroundStyle(entry.skipReason == .inUse ? Ink.busy : Ink.tertiary)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Ink.busy)
            }
        }
    }
}
