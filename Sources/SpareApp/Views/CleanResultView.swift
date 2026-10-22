import SpareCore
import SwiftUI

struct CleanResultView: View {
    @ObservedObject var model: AppModel
    let recordID: UUID

    var body: some View {
        if let record = model.record(id: recordID) {
            result(record)
        } else {
            StateMessage(symbol: "questionmark", tint: .gray, title: Text("This cleanup is no longer in the history."),
                         detail: Text("Open the History to see past cleanups.")) {
                Button("OK") { model.cleanupRoute = .cards }.buttonStyle(PrimaryButton())
            }
        }
    }

    private func result(_ record: CleanupRecord) -> some View {
        let outcome = CleanOutcome(record)
        let saved = model.isSaved(record.id)
        return VStack(spacing: 14) {
            Spacer(minLength: 8)
            Image(systemName: record.cancelled ? "hand.raised.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(record.cancelled ? Ink.review : Ink.spare)
            (record.cancelled ? Text("Cleanup stopped") : Text("Cleanup complete")).font(Txt.h1)
            beforeAfter(record)
            Text("Cleaned \(ByteFormat.string(outcome.cleanedBytes)) in \(String(outcome.cleanedCount)) items")
                .font(Txt.body).foregroundStyle(Ink.secondary).monospacedDigit()
            if outcome.skippedCount + outcome.failedCount > 0 {
                Label("\(String(outcome.skippedCount)) skipped, \(String(outcome.failedCount)) failed", systemImage: "exclamationmark.triangle.fill")
                    .font(Txt.caption).foregroundStyle(outcome.failedCount > 0 ? Ink.busy : Ink.review)
            }
            if !saved {
                Label("Could not save this cleanup to the history, so Undo is not available.", systemImage: "xmark.octagon.fill")
                    .font(Txt.caption).foregroundStyle(Ink.busy)
            }
            if saved, outcome.trashedBytes > 0 {
                TrashCard(model: model, record: record).frame(maxWidth: 660)
            }
            if let notice = model.notice { NoticeLine(notice: notice) }
            ScrollView {
                RowsCard {
                    ForEach(record.entries) { entry in
                        CleanRow(name: ItemName.of(entry), sizeBytes: entry.sizeBytes, state: .finished(entry))
                        if entry.id != record.entries.last?.id { RowDivider() }
                    }
                }
            }
            .frame(maxWidth: 660)
            .frame(minHeight: 90)
            HStack(spacing: 10) {
                Button("View history") { model.selection = .history }.buttonStyle(QuietButton())
                Button("OK") { model.cleanupRoute = .cards }
                    .buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func beforeAfter(_ record: CleanupRecord) -> some View {
        if let before = record.freeBytesBefore, let after = record.freeBytesAfter {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(verbatim: ByteFormat.string(before)).foregroundStyle(Ink.tertiary)
                Image(systemName: "arrow.right").font(.system(size: 22, weight: .semibold)).foregroundStyle(Ink.muted)
                Text(verbatim: ByteFormat.string(after)).foregroundStyle(Ink.spare)
                Text("free").font(Txt.h2).foregroundStyle(Ink.secondary)
            }
            .font(Txt.display)
            .monospacedDigit()
        }
    }
}
