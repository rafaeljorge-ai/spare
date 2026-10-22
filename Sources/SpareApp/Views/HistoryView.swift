import SpareCore
import SwiftUI

/// Which cleanup is open (no `@State`: the macro plugin is missing from Command Line Tools).
final class HistorySelection: ObservableObject {
    @Published var recordID: UUID?
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @StateObject private var selection = HistorySelection()

    var body: some View {
        Group {
            if let id = selection.recordID, let record = model.record(id: id) {
                detail(record)
            } else {
                list
            }
        }
        .onAppear { model.reloadHistory() }
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        VStack(spacing: 0) {
            FlowHeader(title: Text("History"),
                       subtitle: Text("Everything Spare cleaned, with Undo while it is in the Trash"))
            if model.historyFailed {
                StateMessage(symbol: "exclamationmark.triangle.fill", tint: .orange,
                             title: Text("Could not read the history"),
                             detail: Text("The file exists but could not be opened. Nothing was changed.")) {
                    Button("Try again") { model.reloadHistory() }.buttonStyle(QuietButton())
                }
            } else if model.history.isEmpty {
                StateMessage(symbol: "clock.arrow.circlepath", tint: .purple, title: Text("No cleanups yet"),
                             detail: Text("When you clean something, it shows up here.")) { EmptyView() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.history) { record in card(record) }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func card(_ record: CleanupRecord) -> some View {
        let outcome = CleanOutcome(record)
        let count = String(outcome.cleanedCount)
        let waiting = ByteFormat.string(outcome.trashedBytes)
        return Card {
            HStack(spacing: 14) {
                Button { selection.recordID = record.id } label: {
                    HStack(spacing: 14) {
                        Tile(symbol: record.cancelled ? "pause.fill" : "checkmark",
                             tint: record.cancelled ? .orange : .green, side: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(Txt.label)
                            if outcome.trashedBytes > 0 {
                                Text("\(count) items, \(waiting) in the Trash").font(Txt.caption).foregroundStyle(Ink.review)
                            } else {
                                Text("\(count) items").font(Txt.caption).foregroundStyle(Ink.tertiary)
                            }
                        }
                        Spacer()
                        Text(verbatim: ByteFormat.string(outcome.cleanedBytes))
                            .font(Txt.figure).foregroundStyle(Ink.spare).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button("Undo") { Task { await model.undo(record.id) } }
                    .buttonStyle(QuietButton())
                    .disabled(outcome.trashedBytes == 0 || model.busyRecord != nil)
                    .opacity(outcome.trashedBytes == 0 ? 0.4 : 1)
            }
        }
    }

    // MARK: Detail

    private func detail(_ record: CleanupRecord) -> some View {
        let outcome = CleanOutcome(record)
        return VStack(spacing: 0) {
            FlowHeader(
                title: Text(verbatim: record.startedAt.formatted(date: .abbreviated, time: .shortened)),
                subtitle: Text("Cleaned \(ByteFormat.string(outcome.cleanedBytes)) in \(String(outcome.cleanedCount)) items")
            ) {
                selection.recordID = nil
                model.notice = nil
            }
            ScrollView {
                VStack(spacing: 14) {
                    if outcome.trashedBytes > 0 { TrashCard(model: model, record: record) }
                    if let notice = model.notice { NoticeLine(notice: notice).frame(maxWidth: .infinity, alignment: .leading) }
                    RowsCard {
                        ForEach(record.entries) { entry in
                            CleanRow(name: ItemName.of(entry), sizeBytes: entry.sizeBytes, state: .finished(entry))
                            if entry.id != record.entries.last?.id { RowDivider() }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
    }
}
