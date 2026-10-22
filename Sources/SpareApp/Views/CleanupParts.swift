import SpareCore
import SwiftUI

/// Screen header with a back chevron, for the screens inside a flow.
struct FlowHeader: View {
    let title: Text
    let subtitle: Text
    var back: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Ink.surface2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
            }
            VStack(alignment: .leading, spacing: 4) {
                title.font(Txt.h1).tracking(-0.3)
                subtitle.font(Txt.body).foregroundStyle(Ink.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
}

/// The bar at the bottom of a screen: a total on the left, the main action on the right.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 32)
            .frame(height: 68)
            .background(Ink.night.opacity(0.35))
            .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 1) }
    }
}

/// A white-on-glass block for lists of rows.
struct RowsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
    }
}

struct RowDivider: View {
    var inset: CGFloat = 46

    var body: some View {
        Rectangle().fill(Ink.line).frame(height: 1).padding(.leading, inset)
    }
}

/// A short message that stands in for a list: nothing yet, or something went wrong.
struct StateMessage<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: Text
    let detail: Text
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Tile(symbol: symbol, tint: tint, side: 44)
            title.font(Txt.h2)
            detail.font(Txt.body).foregroundStyle(Ink.tertiary).multilineTextAlignment(.center)
            actions.padding(.top, 6)
        }
        .frame(maxWidth: 420, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }
}

/// What an undo or "Free it now" did.
struct NoticeLine: View {
    let notice: CleanupNotice

    var body: some View {
        switch notice {
        case .restored(let restored, let stayed):
            let count = String(restored)
            let left = String(stayed)
            if stayed == 0 {
                line("arrow.uturn.backward.circle.fill", Ink.spare, Text("Restored \(count) items."))
            } else {
                line("exclamationmark.triangle.fill", Ink.review,
                     Text("Restored \(count) items. \(left) stayed in the Trash: the original place is taken or the item changed."))
            }
        case .freed(let bytes, let purged, let stayed):
            let size = ByteFormat.string(bytes)
            let count = String(purged)
            let left = String(stayed)
            if stayed == 0 {
                line("flame.fill", Ink.spare, Text("Freed \(size) from \(count) items."))
            } else {
                line("exclamationmark.triangle.fill", Ink.review,
                     Text("Freed \(size) from \(count) items. \(left) stayed in the Trash."))
            }
        case .failed:
            line("xmark.octagon.fill", Ink.busy, Text("Could not read or write the history."))
        }
    }

    private func line(_ symbol: String, _ tint: Color, _ text: Text) -> some View {
        Label { text.font(Txt.body).foregroundStyle(Ink.secondary) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
    }
}

/// Local flag for the "Free it now" confirmation (no `@State`: the macro plugin is missing).
final class ConfirmFlag: ObservableObject {
    @Published var isOn = false
}

/// Items waiting in the Trash with the two ways out: Undo or Free it now.
struct TrashCard: View {
    @ObservedObject var model: AppModel
    let record: CleanupRecord
    @StateObject private var confirm = ConfirmFlag()

    var body: some View {
        let outcome = CleanOutcome(record)
        let busy = model.busyRecord != nil
        Card {
            HStack(spacing: 14) {
                Image(systemName: "trash.fill").foregroundStyle(Ink.review)
                Text("\(ByteFormat.string(outcome.trashedBytes)) are in the Trash. The space comes back when they leave it.")
                    .font(Txt.body).foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Undo") { Task { await model.undo(record.id) } }
                    .buttonStyle(QuietButton()).disabled(busy)
                Button("Free it now") { confirm.isOn = true }
                    .buttonStyle(QuietButton(tint: Ink.review)).disabled(busy)
            }
        }
        .confirmationDialog(
            Text("Delete \(ByteFormat.string(outcome.trashedBytes)) for good?"),
            isPresented: Binding(get: { confirm.isOn }, set: { confirm.isOn = $0 }), titleVisibility: .visible
        ) {
            Button("Free it now", role: .destructive) { Task { await model.purge(record.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Only the items Spare moved are deleted; the rest of the Trash stays.")
        }
    }
}
