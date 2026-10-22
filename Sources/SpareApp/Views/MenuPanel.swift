import AppKit
import SpareCore
import SwiftUI

/// The menu bar label: mini ring (or a warning triangle below the threshold) and the free GB.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Label {
            Text(verbatim: model.menuTitle)
        } icon: {
            if model.isDiskLow {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                Image(nsImage: MenuBarIcon.ring(usedFraction: model.disk?.usedFraction ?? 0))
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

struct MenuPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Backdrop()
            VStack(alignment: .leading, spacing: 12) {
                diskCard
                memoryCard
                recommendationCard
                Button {
                    model.show(.overview)
                    model.startScan()
                } label: {
                    Text("Analyze everything").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                .disabled(model.isScanning)
                .opacity(model.isScanning ? 0.5 : 1)
                footer
            }
            .padding(16)
        }
        .foregroundStyle(Ink.primary)
        .frame(width: 340)
        .preferredColorScheme(.dark)
        .task { await model.watchMemory() }
        .onAppear { model.refreshDisk() }
    }

    // MARK: Cards

    private var diskCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Overline(text: "Disk")
                    Spacer()
                    Text(verbatim: model.volumeName).font(Txt.caption).foregroundStyle(Ink.tertiary)
                }
                if let disk = model.disk {
                    Text("\(ByteFormat.string(disk.freeBytes)) free of \(ByteFormat.string(disk.totalBytes))")
                        .font(Txt.h3).monospacedDigit()
                    bar(fraction: disk.usedFraction, tint: model.isDiskLow ? Ink.busy : Ink.used)
                    HStack {
                        Spacer()
                        Button("Free up") { model.show(.cleanup) }.buttonStyle(QuietButton())
                    }
                } else {
                    unreadable(message: "Could not read the disk.") { model.refreshDisk() }
                }
            }
        }
    }

    private var memoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Overline(text: "Memory")
                    Spacer()
                    if let memory = model.memory {
                        Text(memory.level.title).font(Txt.caption).foregroundStyle(memory.level.color)
                    }
                }
                if let memory = model.memory {
                    Text("\(ByteFormat.string(memory.usedBytes)) used of \(ByteFormat.string(memory.totalBytes))")
                        .font(Txt.h3).monospacedDigit()
                    bar(fraction: memory.usedFraction, tint: memory.level.color)
                    consumerRows
                    HStack {
                        Spacer()
                        Button("View") { model.show(.memory) }.buttonStyle(QuietButton())
                    }
                } else {
                    unreadable(message: "Could not read the memory.") { model.refreshMemory() }
                }
            }
        }
    }

    @ViewBuilder private var consumerRows: some View {
        if let consumers = model.consumers, !consumers.isEmpty {
            VStack(spacing: 5) {
                ForEach(consumers) { consumer in
                    HStack {
                        Text(verbatim: consumer.name).font(Txt.caption).foregroundStyle(Ink.secondary).lineLimit(1)
                        Spacer()
                        Text(verbatim: ByteFormat.string(consumer.bytes))
                            .font(Txt.caption).foregroundStyle(Ink.tertiary).monospacedDigit()
                    }
                }
            }
        } else if model.consumersFailed {
            Text("Could not list the apps using memory.").font(Txt.caption).foregroundStyle(Ink.tertiary)
        }
    }

    private var recommendationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Overline(text: "Today's recommendation")
                HStack(alignment: .center, spacing: 12) {
                    switch model.recommendation {
                    case .lowDisk(let free):
                        Text("Only \(ByteFormat.string(free)) left. Analyze to free space.").font(Txt.body)
                        Spacer(minLength: 0)
                        Button("Analyze") {
                            model.show(.overview)
                            model.startScan()
                        }
                        .buttonStyle(QuietButton(tint: Ink.busy))
                    case .reclaimable(let bytes):
                        Text("You can free \(ByteFormat.string(bytes)) safely.").font(Txt.body)
                        Spacer(minLength: 0)
                        Button("Review") { model.show(.cleanup) }.buttonStyle(QuietButton(tint: Ink.spare))
                    case .highMemory:
                        Text("Memory is high. See what is using it.").font(Txt.body)
                        Spacer(minLength: 0)
                        Button("View") { model.show(.memory) }.buttonStyle(QuietButton(tint: Ink.review))
                    case .allGood:
                        Label("All good here.", systemImage: "checkmark.circle.fill")
                            .font(Txt.body).foregroundStyle(Ink.spare)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            footerButton("Open Spare") { model.show(.overview) }
            footerButton("Settings") { model.show(.settings) }
            Spacer()
            footerButton("Quit") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 4)
    }

    private func footerButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Txt.label).foregroundStyle(Ink.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Pieces

    private func bar(fraction: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.track)
                Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }

    private func unreadable(message: LocalizedStringKey, retry: @escaping () -> Void) -> some View {
        HStack {
            Text(message).font(Txt.body).foregroundStyle(Ink.tertiary)
            Spacer()
            Button("Try again", action: retry).buttonStyle(QuietButton())
        }
    }
}
