import SwiftUI

struct RootView: View {
    @ObservedObject var model: ProtoModel

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
        .sheet(isPresented: $model.confirming) { ConfirmSheet(model: model) }
    }

    @ViewBuilder private var content: some View {
        switch model.route {
        case .overview: OverviewScreen(model: model)
        case .cleanup: CleanupScreen(model: model)
        case .review(let id): ReviewScreen(model: model, categoryID: id)
        case .result: ResultScreen(model: model)
        case .largeFiles: LargeFilesScreen()
        case .memory: MemoryScreen()
        case .history: HistoryScreen(model: model)
        case .settings: SettingsScreen()
        }
    }
}

private struct NavEntry: Identifiable {
    let route: Route
    let title: String
    let symbol: String
    let tint: Color
    var id: String { title }
}

struct Sidebar: View {
    @ObservedObject var model: ProtoModel

    private let main = [
        NavEntry(route: .overview, title: "Visão geral", symbol: "sparkles", tint: Ink.glow),
        NavEntry(route: .cleanup, title: "Limpeza", symbol: "wand.and.stars", tint: .green),
        NavEntry(route: .largeFiles, title: "Maiores arquivos", symbol: "archivebox.fill", tint: .orange),
        NavEntry(route: .memory, title: "Memória", symbol: "memorychip.fill", tint: .blue),
    ]
    private let more = [
        NavEntry(route: .history, title: "Histórico", symbol: "clock.arrow.circlepath", tint: .purple),
        NavEntry(route: .settings, title: "Ajustes", symbol: "gearshape.fill", tint: .gray),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .trim(from: 0, to: 0.78)
                    .stroke(Ink.spare, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                Text("Spare").font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.top, 40)
            .padding(.bottom, 20)

            ForEach(main) { row($0) }
            Text("REGISTRO")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(more) { row($0) }

            Spacer()
            diskMeter
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
    }

    private func row(_ entry: NavEntry) -> some View {
        let active = isActive(entry.route)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { model.route = entry.route }
        } label: {
            HStack(spacing: 10) {
                Tile(symbol: entry.symbol, tint: entry.tint, side: 24)
                Text(entry.title)
                    .font(Txt.label)
                    .foregroundStyle(active ? Ink.primary : Ink.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? Ink.surface2 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isActive(_ route: Route) -> Bool {
        switch (route, model.route) {
        case (.cleanup, .review), (.cleanup, .result): return true
        default: return route == model.route
        }
    }

    private var diskMeter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Macintosh HD").font(Txt.caption).foregroundStyle(Ink.tertiary)
                Spacer()
                Text(size(model.freeGB) + " livres").font(Txt.caption).foregroundStyle(Ink.secondary).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.track)
                    Capsule().fill(Ink.used).frame(width: proxy.size.width * (1 - model.freeGB / model.totalGB))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.surface1))
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String
    var back: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28)
                        .background(Circle().fill(Ink.surface2))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Txt.h1).tracking(-0.3)
                Text(subtitle).font(Txt.body).foregroundStyle(Ink.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
}
