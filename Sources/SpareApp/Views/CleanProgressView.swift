import SpareCore
import SwiftUI

/// Live progress. Rows are matched to entries by path: events arrive in execution order.
struct CleanProgressView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let rows = AppModel.rowStates(queue: model.cleanQueue, entries: model.cleanEntries, stopping: model.isStopping)
        let finishedCount = rows.filter { if case .finished = $0.state { true } else { false } }.count
        let done = String(finishedCount)
        let total = String(model.cleanQueue.count)
        return VStack(spacing: 0) {
            FlowHeader(
                title: model.isStopping ? Text("Stopping...") : Text("Cleaning..."),
                subtitle: Text("Spare checks each item again right before touching it."))
            VStack(spacing: 14) {
                HStack {
                    bar(fraction: Double(finishedCount) / Double(max(model.cleanQueue.count, 1)))
                    Text("\(done) of \(total)").font(Txt.caption).foregroundStyle(Ink.tertiary).monospacedDigit()
                }
                ScrollView {
                    RowsCard {
                        ForEach(rows, id: \.item.id) { row in
                            CleanRow(name: ItemName.of(row.item), sizeBytes: row.item.sizeBytes, state: row.state)
                            if row.item.id != rows.last?.item.id { RowDivider() }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
            ActionBar {
                Text("Items go to the Trash or are deleted, as confirmed.")
                    .font(Txt.label).foregroundStyle(Ink.tertiary)
                Spacer()
                Button("Stop") { model.stopClean() }.buttonStyle(QuietButton()).disabled(model.isStopping)
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track)
                Capsule()
                    .fill(LinearGradient(colors: [Ink.spare, Ink.glow], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(1, fraction))
                    .animation(.easeOut(duration: 0.2), value: fraction)
            }
        }
        .frame(height: 6)
    }
}
