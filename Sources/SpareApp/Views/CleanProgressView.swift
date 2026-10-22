import SpareCore
import SwiftUI

/// Live progress. Rows are matched to entries by path: events arrive in execution order.
struct CleanProgressView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let finished = Dictionary(model.cleanEntries.map { ($0.originalPath, $0) }, uniquingKeysWith: { first, _ in first })
        let current = model.cleanQueue.first { finished[$0.url.path] == nil }
        let done = String(finished.count)
        let total = String(model.cleanQueue.count)
        return VStack(spacing: 0) {
            FlowHeader(
                title: model.isStopping ? Text("Stopping...") : Text("Cleaning..."),
                subtitle: Text("Spare checks each item again right before touching it."))
            VStack(spacing: 14) {
                HStack {
                    bar(fraction: Double(finished.count) / Double(max(model.cleanQueue.count, 1)))
                    Text("\(done) of \(total)").font(Txt.caption).foregroundStyle(Ink.tertiary).monospacedDigit()
                }
                ScrollView {
                    RowsCard {
                        ForEach(model.cleanQueue) { item in
                            CleanRow(name: ItemName.of(item), sizeBytes: item.sizeBytes,
                                     state: state(of: item, finished: finished, current: current))
                            if item.id != model.cleanQueue.last?.id { RowDivider() }
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

    private func state(of item: ScanItem, finished: [String: CleanupEntry], current: ScanItem?) -> CleanRowState {
        if let entry = finished[item.url.path] { return .finished(entry) }
        return item.id == current?.id && !model.isStopping ? .working : .waiting
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
