import AppKit
import SpareCore
import SwiftUI

struct LargeFilesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tool: LargeFilesModel

    init(model: AppModel) {
        self.model = model
        tool = model.largeFiles
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Large Files",
                             subtitle: "In \(tool.folder.lastPathComponent), bigger than \(String(tool.minMB)) MB")
                VStack(alignment: .leading, spacing: 12) {
                    controls
                    status
                    results
                }
                .padding(.horizontal, 32)
                Spacer(minLength: 0)
            }
            if let file = tool.pending {
                ToolConfirmation(
                    title: "Move to the Trash?", confirm: "Move to the Trash",
                    onConfirm: { Task { await tool.confirmTrash() } }, onCancel: { tool.cancelPending() }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "\(file.url.lastPathComponent)  \(ByteFormat.string(file.sizeBytes))")
                            .font(Txt.label)
                        Text(verbatim: file.url.path)
                            .font(Txt.path).foregroundStyle(Ink.tertiary).lineLimit(2).truncationMode(.middle)
                        Label("It stays in the Trash and in History, so you can undo it.", systemImage: "arrow.uturn.backward")
                            .font(Txt.body).foregroundStyle(Ink.secondary)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: tool.pending)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button { chooseFolder() } label: {
                Label { Text(verbatim: tool.folder.lastPathComponent) } icon: { Image(systemName: "folder") }
            }
            .buttonStyle(QuietButton())
            .disabled(tool.isSearching)

            Menu {
                ForEach(LargeFilesModel.minChoicesMB, id: \.self) { mb in
                    Button { tool.minMB = mb } label: { Text("Bigger than \(String(mb)) MB") }
                }
            } label: {
                Text("Bigger than \(String(tool.minMB)) MB")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(Ink.surface2))
            .disabled(tool.isSearching)

            Spacer()
            if tool.isSearching {
                Button("Stop") { tool.stopSearch() }.buttonStyle(QuietButton())
            } else {
                Button("Search") { tool.startSearch() }.buttonStyle(PrimaryButton())
            }
        }
    }

    @ViewBuilder private var status: some View {
        if tool.isSearching {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Searching...").font(Txt.body).foregroundStyle(Ink.secondary)
                Text(verbatim: tool.progressPath ?? "")
                    .font(Txt.path).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
        } else if case .done(partial: true) = tool.phase {
            ToolNotice(symbol: "exclamationmark.triangle.fill", tint: Ink.review,
                       text: "Partial search: stopped before the whole folder was checked.", onDismiss: {})
        }
        if let outcome = tool.outcome { outcomeNotice(outcome) }
    }

    @ViewBuilder private func outcomeNotice(_ outcome: LargeFilesModel.Outcome) -> some View {
        switch outcome {
        case .trashed(let file, _):
            ToolNotice(symbol: "checkmark.circle.fill", tint: Ink.spare,
                       text: "\(file.url.lastPathComponent) went to the Trash. Undo is also in History.",
                       action: ("Undo", { Task { await tool.undoLast() } }), onDismiss: { tool.dismissOutcome() })
        case .trashedUnrecorded(let file):
            ToolNotice(symbol: "exclamationmark.triangle.fill", tint: Ink.review,
                       text: "\(file.url.lastPathComponent) went to the Trash, but it could not be recorded in History, so there is no Undo. Find it in the Trash.",
                       onDismiss: { tool.dismissOutcome() })
        case .restored(let name):
            ToolNotice(symbol: "arrow.uturn.backward.circle.fill", tint: Ink.spare,
                       text: "\(name) is back where it was.", onDismiss: { tool.dismissOutcome() })
        case .notMoved:
            ToolNotice(symbol: "exclamationmark.triangle.fill", tint: Ink.review,
                       text: "Nothing was moved. Spare keeps this file as it is.",
                       onDismiss: { tool.dismissOutcome() })
        case .undoFailed(let name):
            ToolNotice(symbol: "exclamationmark.triangle.fill", tint: Ink.review,
                       text: "\(name) stays in the Trash: something may already exist at its old place.",
                       onDismiss: { tool.dismissOutcome() })
        }
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        switch tool.phase {
        case .idle:
            ToolEmptyState(symbol: "magnifyingglass", text: "Choose a folder and tap Search.")
        case .searching:
            EmptyView()
        case .failed(let error):
            ToolEmptyState(symbol: "exclamationmark.triangle.fill", text: error.message)
        case .done:
            if tool.files.isEmpty {
                ToolEmptyState(symbol: "checkmark.circle", text: "No file this big here.")
            } else {
                ScrollView {
                    ToolList {
                        ForEach(Array(tool.files.enumerated()), id: \.element.id) { index, file in
                            if index > 0 { Rectangle().fill(Ink.line).frame(height: 1) }
                            row(file)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func row(_ file: LargeFile) -> some View {
        HStack(spacing: 14) {
            Tile(symbol: "doc.fill", tint: .orange, side: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: file.url.lastPathComponent).font(Txt.label).lineLimit(1).truncationMode(.middle)
                Text(verbatim: Self.shortPath(file.url.deletingLastPathComponent(), home: model.home))
                    .font(Txt.path).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let opened = file.lastOpened {
                Text("Opened \(opened.formatted(date: .abbreviated, time: .omitted))")
                    .font(Txt.caption).foregroundStyle(Ink.tertiary)
            }
            Text(verbatim: ByteFormat.string(file.sizeBytes))
                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            toolIcon("magnifyingglass", help: "Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            toolIcon("trash", help: "Move to the Trash") { tool.ask(file) }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private func toolIcon(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(Ink.secondary).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = tool.folder
        if panel.runModal() == .OK, let url = panel.url {
            tool.folder = url
        }
    }

    /// `/Users/me/Movies` shown as `~/Movies`.
    static func shortPath(_ url: URL, home: URL) -> String {
        let path = url.path
        if path == home.path { return "~" }
        return path.hasPrefix(home.path + "/") ? "~" + path.dropFirst(home.path.count) : path
    }
}

extension LargeFileError {
    var message: LocalizedStringKey {
        switch self {
        case .notFound: LocalizedStringKey("That folder no longer exists.")
        case .notAFolder: LocalizedStringKey("That is not a folder, or it is a link. Choose another one.")
        case .systemFolder: LocalizedStringKey("System folders are never searched. Choose another folder.")
        }
    }
}
