import SpareCore
import SwiftUI

struct MemoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tool: MemoryScreenModel

    init(model: AppModel) {
        self.model = model
        tool = model.memoryScreen
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Memory", subtitle: "Approximate: memory shared between processes counts for each one.")
                if let outcome = tool.outcome {
                    outcomeNotice(outcome)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }
                HStack(alignment: .top, spacing: 20) {
                    pressureCard
                    consumerList
                }
                .padding(.horizontal, 32)
                Spacer(minLength: 0)
            }
            if let prompt = tool.pending {
                ToolConfirmation(
                    title: "Quit \(prompt.consumer.name)?", confirm: "End now",
                    onConfirm: { Task { await tool.confirmQuit() } }, onCancel: { tool.cancelPending() }
                ) { promptBody(prompt) }
            }
        }
        .animation(.easeOut(duration: 0.15), value: tool.pending)
    }

    // MARK: Pressure

    private var pressureCard: some View {
        Card {
            VStack(spacing: 12) {
                if let memory = model.memory {
                    ZStack {
                        Circle().stroke(Ink.track, lineWidth: 12)
                        Circle().trim(from: 0, to: memory.usedFraction)
                            .stroke(memory.level.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(verbatim: "\(Int((memory.usedFraction * 100).rounded()))%")
                                .font(Txt.display).monospacedDigit()
                            Text("in use").font(Txt.caption).foregroundStyle(Ink.tertiary)
                        }
                    }
                    .frame(width: 160, height: 160)
                    Text(memory.level.title).font(Txt.h3).foregroundStyle(memory.level.color)
                    Text("\(ByteFormat.string(memory.usedBytes)) used of \(ByteFormat.string(memory.totalBytes))")
                        .font(Txt.caption).foregroundStyle(Ink.secondary).monospacedDigit()
                    Text("Compressed: \(ByteFormat.string(memory.compressedBytes))")
                        .font(Txt.caption).foregroundStyle(Ink.tertiary).monospacedDigit()
                } else if !model.memoryLoaded {
                    ProgressView().controlSize(.small).frame(height: 160)
                    Text("Loading...").font(Txt.caption).foregroundStyle(Ink.tertiary)
                } else {
                    Tile(symbol: "exclamationmark.triangle.fill", tint: Ink.review, side: 40)
                    Text("Could not read the memory.").font(Txt.body).foregroundStyle(Ink.tertiary)
                    Button("Try again") { model.refreshMemory() }.buttonStyle(QuietButton())
                }
            }
            .frame(width: 190)
        }
    }

    // MARK: Consumers

    @ViewBuilder private var consumerList: some View {
        if let consumers = tool.consumers, !consumers.isEmpty {
            ScrollView {
                ToolList {
                    ForEach(Array(consumers.enumerated()), id: \.element.id) { index, consumer in
                        if index > 0 { Rectangle().fill(Ink.line).frame(height: 1) }
                        row(consumer)
                    }
                }
                .padding(.bottom, 24)
            }
        } else if tool.consumers == nil {
            ToolEmptyState(symbol: "memorychip", text: "Loading...")
        } else if tool.failed {
            VStack(spacing: 12) {
                ToolEmptyState(symbol: "exclamationmark.triangle.fill", text: "Could not list the apps using memory.")
                Button("Try again") { Task { await tool.sampler.sampleIfDue(force: true) } }.buttonStyle(QuietButton())
            }
        } else {
            ToolEmptyState(symbol: "checkmark.circle", text: "No app is using notable memory.")
        }
    }

    private func row(_ consumer: MemoryConsumer) -> some View {
        HStack(spacing: 12) {
            Tile(symbol: consumer.isApp ? "app.fill" : "terminal.fill", tint: consumer.isApp ? Ink.glow : .gray, side: 28)
            Text(verbatim: consumer.name).font(Txt.label).lineLimit(1)
            if consumer.pids.count > 1 {
                Text("\(String(consumer.pids.count)) processes").font(Txt.caption).foregroundStyle(Ink.tertiary)
            }
            Spacer(minLength: 8)
            Text(verbatim: ByteFormat.string(consumer.bytes))
                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            Button("End") { tool.ask(consumer) }.buttonStyle(QuietButton(tint: Ink.busy))
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    // MARK: Confirmation

    @ViewBuilder private func promptBody(_ prompt: QuitPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if prompt.consumer.isApp {
                Text("The app is asked to quit and may offer to save your work.")
                    .font(Txt.body).foregroundStyle(Ink.secondary)
            } else {
                Text("Unsaved work in this process may be lost.").font(Txt.body).foregroundStyle(Ink.secondary)
            }
            if prompt.isGrouped {
                Text("\(String(prompt.consumer.pids.count)) processes will be asked to quit:")
                    .font(Txt.label).foregroundStyle(Ink.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(prompt.lines, id: \.pid) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: String(line.pid)).font(Txt.path).foregroundStyle(Ink.tertiary)
                                .frame(width: 52, alignment: .trailing)
                            Text(verbatim: line.command).font(Txt.path).foregroundStyle(Ink.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    if prompt.hiddenCount > 0 {
                        Text("And \(String(prompt.hiddenCount)) more.").font(Txt.caption).foregroundStyle(Ink.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func outcomeNotice(_ outcome: MemoryScreenModel.Outcome) -> some View {
        switch outcome {
        case .asked(let name, let skipped):
            if skipped > 0 {
                ToolNotice(symbol: "exclamationmark.triangle.fill", tint: Ink.review,
                           text: "\(name) was asked to quit. \(String(skipped)) changed since you looked and were left alone.",
                           onDismiss: { tool.dismissOutcome() })
            } else {
                ToolNotice(symbol: "checkmark.circle.fill", tint: Ink.spare,
                           text: "\(name) was asked to quit.", onDismiss: { tool.dismissOutcome() })
            }
        case .failed(let name, let skipped):
            if skipped > 0 {
                ToolNotice(symbol: "exclamationmark.triangle.fill", tint: Ink.review,
                           text: "Nothing was quit: \(name) changed since you looked. Look at the list again.",
                           onDismiss: { tool.dismissOutcome() })
            } else {
                ToolNotice(symbol: "exclamationmark.triangle.fill", tint: Ink.review,
                           text: "Could not quit \(name). It may have closed already.",
                           onDismiss: { tool.dismissOutcome() })
            }
        }
    }
}
