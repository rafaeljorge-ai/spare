import SpareCore
import SwiftUI

/// The Cleanup section: cards, then Review, Progress and Result in the same place.
struct CleanupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        content
            .sheet(item: $model.pendingPlan) { plan in
                ConfirmCleanSheet(model: model, plan: plan)
            }
    }

    @ViewBuilder private var content: some View {
        switch model.cleanupRoute {
        case .cards: CleanupCardsView(model: model)
        case .review(let category): ReviewView(model: model, category: category)
        case .progress: CleanProgressView(model: model)
        case .result(let id): CleanResultView(model: model, recordID: id)
        }
    }
}

struct CleanupCardsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let report = model.lastReport {
            let visible = CategoryID.displayOrder.filter { !report.items(in: $0).isEmpty }
            if visible.isEmpty {
                VStack(spacing: 0) {
                    FlowHeader(title: Text("Cleanup"), subtitle: Text("Nothing to clean right now."))
                    StateMessage(symbol: "checkmark", tint: .green, title: Text("All clean"),
                                 detail: Text("The last analysis found nothing to clean.")) {
                        Button("Analyze again") { analyze() }.buttonStyle(QuietButton()).disabled(model.isScanning)
                    }
                }
            } else {
                cards(report, visible)
            }
        } else {
            VStack(spacing: 0) {
                FlowHeader(title: Text("Cleanup"), subtitle: Text("Run an analysis to see what can be freed."))
                StateMessage(symbol: "magnifyingglass", tint: Ink.glow, title: Text("No analysis yet"),
                             detail: Text("Spare only touches what an analysis found.")) {
                    Button("Analyze everything") { analyze() }.buttonStyle(PrimaryButton()).disabled(model.isScanning)
                }
            }
        }
    }

    private func analyze() {
        model.selection = .overview
        model.startScan()
    }

    private func cards(_ report: ScanReport, _ visible: [CategoryID]) -> some View {
        let safe = ByteFormat.string(report.safeReclaimableBytes)
        let review = ByteFormat.string(report.reviewBytes)
        let empty = CategoryID.displayOrder.count - visible.count
        return VStack(spacing: 0) {
            FlowHeader(title: Text("Cleanup"), subtitle: Text("\(safe) safe and \(review) to review"))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if report.cancelled {
                        Label("Analysis interrupted, partial results", systemImage: "exclamationmark.triangle.fill")
                            .font(Txt.label).foregroundStyle(Ink.review)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(visible, id: \.self) { category in
                            CategoryCard(model: model, category: category, items: report.items(in: category))
                        }
                    }
                    if empty > 0 {
                        Text("\(String(empty)) categories with nothing to clean")
                            .font(Txt.caption).foregroundStyle(Ink.tertiary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            ActionBar {
                Label {
                    Text("Safe items rebuild themselves or can be undone.")
                        .font(Txt.label).foregroundStyle(Ink.secondary)
                } icon: {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(Ink.spare)
                }
                Spacer()
                Button("Clean what's safe") { model.requestCleanSafe() }
                    .buttonStyle(PrimaryButton())
                    .disabled(report.safeReclaimableBytes == 0 || model.isScanning)
            }
        }
    }
}

struct CategoryCard: View {
    @ObservedObject var model: AppModel
    let category: CategoryID
    let items: [ScanItem]

    private var safety: Safety { items.allSatisfy { $0.safety == .safe } ? .safe : .review }
    private var blocked: Int { items.filter { !$0.availability.isSelectable }.count }
    private var total: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    private var readyToClean: Bool { items.contains { $0.availability.isSelectable } && !model.isScanning }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Tile(symbol: category.symbol, tint: category.tint, side: 36)
                    Spacer()
                    Badge(safety: safety)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title).font(Txt.h3)
                    Text(category.explanation).font(Txt.caption).foregroundStyle(Ink.tertiary)
                        .lineLimit(2, reservesSpace: true)
                    if blocked > 0 {
                        Label("\(String(blocked)) in use or not verified, left alone", systemImage: "lock.fill")
                            .font(Txt.caption).foregroundStyle(Ink.busy)
                    }
                }
                HStack {
                    Text(verbatim: ByteFormat.string(total)).font(Txt.figure).monospacedDigit()
                    Spacer()
                    Button("Review") { model.openReview(category) }.buttonStyle(QuietButton())
                    if safety == .safe {
                        Button("Clean") { model.requestClean(items) }
                            .buttonStyle(PrimaryButton())
                            .disabled(!readyToClean)
                    }
                }
            }
        }
    }
}
