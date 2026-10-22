import SpareCore
import SwiftUI

/// The confirmation: says what is deleted for good and what goes to the Trash. Nothing runs before it.
struct ConfirmCleanSheet: View {
    @ObservedObject var model: AppModel
    let plan: CleanPlan

    var body: some View {
        ConfirmCleanContent(plan: plan, onCancel: { model.dismissPlan() }, onConfirm: { model.confirmClean() })
            .preferredColorScheme(.dark)
    }
}

/// The sheet's content on its own, so snapshots can draw it in a window.
struct ConfirmCleanContent: View {
    let plan: CleanPlan
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let count = String(plan.items.count)
        let total = ByteFormat.string(plan.totalBytes)
        let trashed = String(plan.trashCount)
        let trashedSize = ByteFormat.string(plan.trashBytes)
        VStack(alignment: .leading, spacing: 16) {
            Text("Clean \(count) items (\(total))?").font(Txt.h2)
            VStack(alignment: .leading, spacing: 12) {
                if plan.deleteCount + plan.commandCount > 0 {
                    line("bolt.fill", Ink.spare) {
                        Text("Caches and leftovers that rebuild themselves are deleted for good to free space now.")
                    }
                }
                if plan.trashCount > 0 {
                    line("trash", Ink.review) {
                        Text("\(trashed) items (\(trashedSize)) go to the Trash and can be undone.")
                    }
                }
                if plan.emptiesTrash {
                    line("exclamationmark.triangle.fill", Ink.busy) {
                        Text("Emptying the Trash cannot be undone.").foregroundStyle(Ink.busy)
                    }
                }
                line("checkmark.shield.fill", Ink.tertiary) {
                    Text("Spare checks each item again right before touching it. Anything in use is skipped.")
                        .foregroundStyle(Ink.tertiary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("Clean", action: onConfirm).buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Ink.night)
        .foregroundStyle(Ink.primary)
    }

    private func line<Content: View>(_ symbol: String, _ tint: Color, @ViewBuilder _ text: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            text().font(Txt.body).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
