import AppKit
import SpareCore
import SwiftUI

struct ReviewView: View {
    @ObservedObject var model: AppModel
    let category: CategoryID

    private var items: [ScanItem] { model.lastReport?.items(in: category) ?? [] }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 0) {
                FlowHeader(title: Text(category.title), subtitle: Text(category.explanation)) {
                    model.cleanupRoute = .cards
                }
                StateMessage(symbol: "checkmark", tint: .green, title: Text("Nothing left here"),
                             detail: Text("Everything in this category was cleaned.")) {
                    Button("Back") { model.cleanupRoute = .cards }.buttonStyle(QuietButton())
                }
            }
        } else {
            list
        }
    }

    private var list: some View {
        let selected = model.selectedItems(in: category)
        let size = ByteFormat.string(selected.reduce(0) { $0 + $1.sizeBytes })
        let count = selected.count
        let readyCount = items.filter { $0.availability.isSelectable }.count
        let allOn = selected.count == readyCount
        return VStack(spacing: 0) {
            FlowHeader(title: Text(category.title), subtitle: Text(category.explanation)) {
                model.cleanupRoute = .cards
            }
            ScrollView {
                RowsCard {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id { RowDivider() }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
            }
            ActionBar {
                Text("Selected: \(count) items, \(size)")
                    .font(Txt.label).foregroundStyle(Ink.secondary).monospacedDigit()
                if readyCount > 0 {
                    Button { model.setAll(!allOn, in: category) } label: {
                        allOn ? Text("Clear selection") : Text("Select all")
                    }
                    .buttonStyle(QuietButton())
                }
                Spacer()
                Button("Clean selected") { model.requestClean(selected) }
                    .buttonStyle(PrimaryButton())
                    .disabled(selected.isEmpty || model.isScanning)
            }
        }
    }

    private func row(_ item: ScanItem) -> some View {
        let selectable = item.availability.isSelectable
        return HStack(spacing: 14) {
            Button { model.toggle(item) } label: {
                HStack(spacing: 14) {
                    Checkbox(on: model.selectedItemIDs.contains(item.id) && selectable, enabled: selectable)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: ItemName.of(item)).font(Txt.label)
                            .foregroundStyle(selectable ? Ink.primary : Ink.secondary)
                        Text(verbatim: item.url.path).font(Txt.path).foregroundStyle(Ink.muted)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    Badge(safety: item.safety)
                    Text(verbatim: modified(item)).font(Txt.caption).foregroundStyle(Ink.tertiary)
                        .lineLimit(1).frame(width: 78, alignment: .trailing)
                    ItemStatusLabel(availability: item.availability)
                        .lineLimit(1).frame(width: 140, alignment: .trailing)
                    Text(verbatim: ByteFormat.string(item.sizeBytes))
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.tertiary).frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(Text("Show in Finder"))
            .accessibilityLabel(Text("Show in Finder"))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private func modified(_ item: ScanItem) -> String {
        guard let date = item.lastModified else { return "-" }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
