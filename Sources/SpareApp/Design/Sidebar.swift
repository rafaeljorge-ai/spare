import SpareCore
import SwiftUI

struct Sidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .trim(from: 0, to: 0.78)
                    .stroke(Ink.spare, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                Text(verbatim: "Spare").font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.top, 40)
            .padding(.bottom, 20)

            ForEach(AppSection.mainGroup) { row($0) }
            Overline(text: "Records")
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(AppSection.recordsGroup) { row($0) }

            Spacer()
            diskMeter
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
    }

    private func row(_ section: AppSection) -> some View {
        let active = model.selection == section
        return Button {
            // Clicking the open Cleanup row goes back to its cards.
            if section == .cleanup, model.selection == .cleanup { model.resetCleanupRoute() }
            withAnimation(.easeOut(duration: 0.18)) { model.selection = section }
        } label: {
            HStack(spacing: 10) {
                Tile(symbol: section.symbol, tint: section.tint, side: 24)
                Text(section.title)
                    .font(Txt.label)
                    .foregroundStyle(active ? Ink.primary : Ink.secondary)
                Spacer()
                if section == .cleanup, model.cleanupRoute == .progress {
                    ProgressView().controlSize(.mini).accessibilityLabel(Text("Cleaning..."))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? Ink.surface2 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var diskMeter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: model.volumeName).font(Txt.caption).foregroundStyle(Ink.tertiary).lineLimit(1)
                Spacer()
                if let disk = model.disk {
                    Text("\(ByteFormat.string(disk.freeBytes)) free")
                        .font(Txt.caption).foregroundStyle(Ink.secondary).monospacedDigit()
                } else {
                    Text(verbatim: "-").font(Txt.caption).foregroundStyle(Ink.secondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.track)
                    Capsule().fill(Ink.used).frame(width: proxy.size.width * (model.disk?.usedFraction ?? 0))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.surface1))
    }
}
