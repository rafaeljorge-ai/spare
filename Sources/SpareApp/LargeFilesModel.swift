import Foundation
import SpareCore

/// State of the Large Files screen. The search runs off the main actor, reports progress, can be stopped
/// (a stopped search keeps what it found and says so), and a file goes to the Trash only after a
/// confirmation, through `LargeFileCleaner`, with a History entry and Undo.
@MainActor
final class LargeFilesModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case searching
        case done(partial: Bool)
        case failed(LargeFileError)
    }

    enum Outcome: Equatable {
        case trashed(LargeFile, recordID: UUID)
        case restored(String)
        case notMoved(String)
        case undoFailed(String)
    }

    /// `(folder, minimum bytes, home, progress)`; the real one walks the disk with `LargeFileFinder`.
    typealias Search = @Sendable (URL, Int64, URL, @escaping @Sendable (String) -> Void) throws -> LargeFileSearch

    static let minChoicesMB = [100, 250, 500, 1_000, 2_000, 5_000]

    @Published var folder: URL
    @Published var minMB = 500
    @Published private(set) var files: [LargeFile] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progressPath: String?
    /// The file waiting for the user's "Move to the Trash" confirmation.
    @Published var pending: LargeFile?
    @Published private(set) var outcome: Outcome?

    private let home: URL
    private let environment: () -> SpareEnvironment
    private let search: Search
    private let didChangeDisk: () -> Void
    private var worker: Task<LargeFileSearch, Error>?
    private var runner: Task<Void, Never>?

    init(
        home: URL, environment: @escaping () -> SpareEnvironment, didChangeDisk: @escaping () -> Void = {},
        search: @escaping Search = LargeFilesModel.liveSearch
    ) {
        self.home = home
        self.folder = home
        self.environment = environment
        self.didChangeDisk = didChangeDisk
        self.search = search
    }

    static let liveSearch: Search = { folder, minBytes, home, progress in
        try LargeFileFinder.search(in: folder, minBytes: minBytes, home: home, progress: progress)
    }

    var isSearching: Bool { phase == .searching }

    // MARK: Search

    func startSearch() {
        guard !isSearching else { return }
        phase = .searching
        progressPath = nil
        outcome = nil
        files = []
        let (folder, minBytes, home, search) = (folder, Int64(minMB) * 1_000_000, home, search)
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            try search(folder, minBytes, home) { path in
                Task { @MainActor in self?.report(path) }
            }
        }
        self.worker = worker
        runner = Task { [weak self] in
            let result = await worker.result
            self?.finish(result)
        }
    }

    func stopSearch() {
        worker?.cancel()
    }

    /// Waits for the running search to publish its result (tests).
    func waitForSearch() async {
        await runner?.value
    }

    private func report(_ path: String) {
        if isSearching { progressPath = path }
    }

    private func finish(_ result: Result<LargeFileSearch, Error>) {
        worker = nil
        runner = nil
        progressPath = nil
        switch result {
        case .success(let search):
            files = search.files
            phase = .done(partial: search.partial)
        case .failure(let error):
            files = []
            phase = .failed(error as? LargeFileError ?? .notFound(folder.path))
        }
    }

    // MARK: Move to the Trash

    func ask(_ file: LargeFile) {
        pending = file
    }

    func cancelPending() {
        pending = nil
    }

    /// Moves the pending file to the Trash and records it in the History. Nothing happens without `ask`.
    func confirmTrash() async {
        guard let file = pending else { return }
        pending = nil
        let environment = environment()
        let record = await Task.detached(priority: .userInitiated) {
            LargeFileCleaner(environment: environment).trash([file])
        }.value
        guard let entry = record.entries.first, entry.status == .done else {
            outcome = .notMoved(record.entries.first?.skipReason?.rawValue ?? record.entries.first?.detail ?? "failed")
            return
        }
        try? HistoryStore(directory: environment.supportDirectory).append(record)
        files.removeAll { $0.id == file.id }
        outcome = .trashed(file, recordID: record.id)
        didChangeDisk()
    }

    /// Takes the last file back out of the Trash (the same Undo the History screen uses).
    func undoLast() async {
        guard case .trashed(let file, let recordID) = outcome else { return }
        let environment = environment()
        let result = await Task.detached(priority: .userInitiated) {
            try? HistoryStore(directory: environment.supportDirectory).undo(recordID: recordID, trash: environment.trash)
        }.value
        if let result, result.restored > 0 {
            files = (files + [file]).sorted { $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.id < $1.id }
            outcome = .restored(file.url.lastPathComponent)
            didChangeDisk()
        } else {
            outcome = .undoFailed(file.url.lastPathComponent)
        }
    }

    func dismissOutcome() {
        outcome = nil
    }
}
