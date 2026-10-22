import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Backdrop()
            HStack(spacing: 0) {
                Sidebar(model: model)
                    .frame(width: 216)
                Rectangle().fill(Ink.line).frame(width: 1)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Ink.primary)
        .frame(width: 1000, height: 660)
        .preferredColorScheme(.dark)
        .background(VisibilityReader { model.setVisible($0, source: "main") })
    }

    @ViewBuilder private var content: some View {
        switch model.selection {
        case .overview: OverviewView(model: model)
        case .cleanup: CleanupView(model: model)
        case .history: HistoryView(model: model)
        // Task 11 replaces the placeholder with the remaining screens.
        default: ComingSoonView(section: model.selection)
        }
    }
}

private struct ComingSoonView: View {
    let section: AppSection

    var body: some View {
        VStack(spacing: 14) {
            Tile(symbol: section.symbol, tint: section.tint, side: 44)
            Text(section.title).font(Txt.h1)
            Text("Coming in the next update").font(Txt.body).foregroundStyle(Ink.tertiary)
        }
    }
}
