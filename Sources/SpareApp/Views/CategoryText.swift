import SpareCore
import SwiftUI

extension CategoryID {
    static let displayOrder: [CategoryID] = [
        .projectLeftovers, .devCaches, .aiTools, .appCaches, .installers, .logs, .trash,
    ]

    var title: LocalizedStringKey {
        switch self {
        case .devCaches: LocalizedStringKey("Developer caches")
        case .projectLeftovers: LocalizedStringKey("Idle project leftovers")
        case .aiTools: LocalizedStringKey("AI tools")
        case .appCaches: LocalizedStringKey("App caches")
        case .logs: LocalizedStringKey("Logs")
        case .installers: LocalizedStringKey("Forgotten installers")
        case .trash: LocalizedStringKey("Trash")
        case .largeFiles: LocalizedStringKey("Large files")
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .devCaches: LocalizedStringKey("Package manager caches. They rebuild themselves when needed.")
        case .projectLeftovers: LocalizedStringKey("Dependencies of projects untouched for a while. Reinstall with one command.")
        case .aiTools: LocalizedStringKey("Downloaded models and runtimes. Review: they download again if you use them.")
        case .appCaches: LocalizedStringKey("Temporary data of closed apps. They rebuild themselves.")
        case .logs: LocalizedStringKey("Old diagnostic logs.")
        case .installers: LocalizedStringKey("Installers in Downloads older than 30 days. Go to the Trash.")
        case .trash: LocalizedStringKey("Emptying the Trash cannot be undone.")
        case .largeFiles: LocalizedStringKey("Files you picked on the Large Files screen.")
        }
    }

    var symbol: String {
        switch self {
        case .devCaches: "hammer.fill"
        case .projectLeftovers: "shippingbox.fill"
        case .aiTools: "brain.head.profile"
        case .appCaches: "square.stack.3d.up.fill"
        case .logs: "doc.text.fill"
        case .installers: "arrow.down.circle.fill"
        case .trash: "trash.fill"
        case .largeFiles: "doc.fill"
        }
    }

    var tint: Color {
        switch self {
        case .devCaches: .blue
        case .projectLeftovers: .green
        case .aiTools: .purple
        case .appCaches: .indigo
        case .logs: .gray
        case .installers: .pink
        case .trash: .orange
        case .largeFiles: .teal
        }
    }
}

extension Safety {
    var title: LocalizedStringKey {
        switch self {
        case .safe: LocalizedStringKey("Safe")
        case .review: LocalizedStringKey("Review")
        }
    }
}

extension MemoryPressureLevel {
    var title: LocalizedStringKey {
        switch self {
        case .normal: LocalizedStringKey("Pressure: normal")
        case .warning: LocalizedStringKey("Pressure: attention")
        case .critical: LocalizedStringKey("Pressure: high")
        }
    }

    var color: Color {
        switch self {
        case .normal: Ink.spare
        case .warning: Ink.review
        case .critical: Ink.busy
        }
    }
}
