import SpareCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            headline
                .padding(.top, 48)
            Spacer(minLength: 16)
            ZStack {
                ring
                center
            }
            Spacer(minLength: 16)
            // Fixed height so the ring does not jump between the three states.
            footer
                .frame(height: 124, alignment: .bottom)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Ring

    @ViewBuilder private var ring: some View {
        let total = model.disk?.totalBytes ?? 0
        let free = model.disk?.freeBytes ?? 0
        switch model.scanState {
        case .idle:
            SpareRing(totalBytes: total, freeBytes: free)
        case .scanning:
            SpareRing(totalBytes: total, freeBytes: free, scanning: true)
        case .finished(let report):
            SpareRing(totalBytes: total, freeBytes: free,
                      safeBytes: report.safeReclaimableBytes, reviewBytes: report.reviewBytes)
        }
    }

    @ViewBuilder private var center: some View {
        switch model.scanState {
        case .idle:
            ScanButton { model.startScan() }
                .disabled(model.disk == nil)
        case .scanning:
            VStack(spacing: 2) {
                Text(verbatim: "\(Int((model.scanFraction ?? 0) * 100))%").font(Txt.display).monospacedDigit()
                Text("\(String(model.finishedCategories.count)) of \(String(CategoryID.displayOrder.count)) categories")
                    .font(Txt.caption).foregroundStyle(Ink.tertiary)
            }
        case .finished(let report):
            VStack(spacing: 2) {
                Text(verbatim: ByteFormat.string(report.safeReclaimableBytes))
                    .font(Txt.display).foregroundStyle(Ink.spare).monospacedDigit()
                Text("can go safely").font(Txt.label).foregroundStyle(Ink.secondary)
            }
        }
    }

    // MARK: Headline

    @ViewBuilder private var headline: some View {
        VStack(spacing: 6) {
            switch model.scanState {
            case .idle:
                if let disk = model.disk {
                    Text("Your Mac has \(ByteFormat.string(disk.freeBytes)) free").font(Txt.h1).tracking(-0.3)
                    Text("Analyze caches, idle projects and AI leftovers in a single pass.")
                        .font(Txt.body).foregroundStyle(Ink.tertiary)
                } else {
                    Text("Could not read the disk.").font(Txt.h1).tracking(-0.3)
                    Button("Try again") { model.refreshDisk() }.buttonStyle(QuietButton())
                }
            case .scanning(let progress):
                Text("Analyzing...").font(Txt.h1).tracking(-0.3)
                Text(verbatim: progress?.currentPath ?? " ")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Ink.muted)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 460)
            case .finished(let report):
                if report.cancelled {
                    Label("Analysis interrupted, partial results", systemImage: "exclamationmark.triangle.fill")
                        .font(Txt.h3).foregroundStyle(Ink.review)
                } else {
                    Text("Analysis complete").font(Txt.h1).tracking(-0.3)
                }
                Text("Plus \(ByteFormat.string(report.reviewBytes)) to review at your own pace.")
                    .font(Txt.body).foregroundStyle(Ink.tertiary)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        switch model.scanState {
        case .idle:
            idleStats
        case .scanning:
            HStack(spacing: 8) {
                ForEach(CategoryID.displayOrder, id: \.self) { category in
                    let done = model.finishedCategories.contains(category)
                    Tile(symbol: done ? "checkmark" : category.symbol, tint: done ? category.tint : Ink.surface2, side: 30)
                        .opacity(done ? 1 : 0.6)
                        .help(category.title)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(category.title))
                        .accessibilityValue(done ? Text("Done") : Text("Analyzing..."))
                }
                Spacer().frame(width: 16)
                Button("Stop") { model.cancelScan() }.buttonStyle(QuietButton())
            }
        case .finished(let report):
            VStack(spacing: 14) {
                legend(report)
                leftOut(report)
                HStack(spacing: 10) {
                    Button("Analyze again") { model.startScan() }.buttonStyle(QuietButton())
                    Button("Review all") { model.show(.cleanup) }.buttonStyle(PrimaryButton())
                }
            }
        }
    }

    private var idleStats: some View {
        HStack(spacing: 12) {
            diskStat
            memoryStat
            cleanupStat
        }
    }

    @ViewBuilder private var diskStat: some View {
        if let disk = model.disk {
            Stat(title: "Disk", value: Text(verbatim: ByteFormat.string(disk.totalBytes - disk.freeBytes))) {
                Text("in use of \(ByteFormat.string(disk.totalBytes))")
            }
        } else {
            Stat(title: "Disk", value: Text(verbatim: "-")) { Text("unavailable") }
        }
    }

    @ViewBuilder private var memoryStat: some View {
        if let memory = model.memory {
            Stat(title: "Memory", value: Text(verbatim: ByteFormat.string(memory.usedBytes))) {
                Text(memory.level.title)
            }
        } else {
            Stat(title: "Memory", value: Text(verbatim: "-")) { Text("unavailable") }
        }
    }

    @ViewBuilder private var cleanupStat: some View {
        if let last = model.lastCleanup {
            Stat(title: "Last cleanup", value: Text(verbatim: ByteFormat.string(last.cleanedBytes))) {
                Text(verbatim: RelativeDateTimeFormatter().localizedString(for: last.finishedAt, relativeTo: Date()))
            }
        } else {
            Stat(title: "Last cleanup", value: Text("Never")) { Text("Run the first analysis") }
        }
    }

    private func legend(_ report: ScanReport) -> some View {
        HStack(spacing: 18) {
            Swatch(color: Ink.spare) { Text("Safe \(ByteFormat.string(report.safeReclaimableBytes))") }
            Swatch(color: Ink.review) { Text("Review \(ByteFormat.string(report.reviewBytes))") }
            Swatch(color: Ink.used) { Text("In use") }
            Swatch(color: Ink.track) { Text("Free \(ByteFormat.string(model.disk?.freeBytes ?? 0))") }
        }
    }

    /// Items an app is using, or that could not be checked: shown, never selectable.
    @ViewBuilder private func leftOut(_ report: ScanReport) -> some View {
        let blocked = report.items.filter { !$0.availability.isSelectable }
        if !blocked.isEmpty {
            VStack(spacing: 6) {
                ForEach(blocked.prefix(2)) { item in
                    HStack(spacing: 10) {
                        Text(verbatim: item.url.lastPathComponent)
                            .font(Txt.path).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.middle)
                        ItemStatusLabel(availability: item.availability)
                    }
                }
                if blocked.count > 2 {
                    Text("And \(String(blocked.count - 2)) more stay untouched.")
                        .font(Txt.caption).foregroundStyle(Ink.tertiary)
                }
            }
        }
    }
}

private struct Swatch<Label: View>: View {
    let color: Color
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            label.font(Txt.caption).foregroundStyle(Ink.secondary).monospacedDigit()
        }
    }
}

private struct Stat<Detail: View>: View {
    let title: LocalizedStringKey
    let value: Text
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Overline(text: title)
            value.font(Txt.figure).monospacedDigit()
            detail.font(Txt.caption).foregroundStyle(Ink.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
    }
}
