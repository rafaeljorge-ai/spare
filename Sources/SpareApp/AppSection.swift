import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, cleanup, largeFiles, memory, history, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: LocalizedStringKey("Overview")
        case .cleanup: LocalizedStringKey("Cleanup")
        case .largeFiles: LocalizedStringKey("Large Files")
        case .memory: LocalizedStringKey("Memory")
        case .history: LocalizedStringKey("History")
        case .settings: LocalizedStringKey("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles"
        case .cleanup: "wand.and.stars"
        case .largeFiles: "archivebox.fill"
        case .memory: "memorychip.fill"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview: Ink.glow
        case .cleanup: .green
        case .largeFiles: .orange
        case .memory: .blue
        case .history: .purple
        case .settings: .gray
        }
    }

    /// Sidebar groups: the three tools and Overview first, then the records.
    static let mainGroup: [AppSection] = [.overview, .cleanup, .largeFiles, .memory]
    static let recordsGroup: [AppSection] = [.history, .settings]
}
