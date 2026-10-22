import SpareCore
import SwiftUI

enum CleanupRoute: Equatable {
    case cards
    case review(CategoryID)
    case progress
    case result(UUID)
}

/// What an undo or "Free it now" did, for the line shown under the Trash actions.
enum CleanupNotice: Equatable {
    case restored(Int, stayed: Int)
    case freed(Int64, purged: Int, stayed: Int)
    /// The history could not be read or written.
    case failed
}

extension AppModel {
    private var historyStore: HistoryStore { HistoryStore(directory: environment.supportDirectory) }

    var isCleaning: Bool { cleanWorker != nil }

    // MARK: History

    /// A history that cannot be read is an error on screen, never an empty list.
    func reloadHistory() {
        do {
            history = try historyStore.load()
            historyFailed = false
        } catch {
            historyFailed = true
        }
    }

    func record(id: UUID) -> CleanupRecord? {
        history.first { $0.id == id } ?? (unsavedRecord?.id == id ? unsavedRecord : nil)
    }

    /// False when the cleanup ran but could not be written to the history: Undo is not available for it.
    func isSaved(_ id: UUID) -> Bool {
        history.contains { $0.id == id }
    }

    // MARK: Selection

    func openReview(_ category: CategoryID) {
        let items = lastReport?.items(in: category) ?? []
        selectedItemIDs = CleanPlan.defaultSelection(for: items)
        cleanupRoute = .review(category)
    }

    func toggle(_ item: ScanItem) {
        guard item.availability.isSelectable else { return }
        if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) } else { selectedItemIDs.insert(item.id) }
    }

    /// Everything ready in the category, or nothing.
    func setAll(_ on: Bool, in category: CategoryID) {
        let ready = (lastReport?.items(in: category) ?? []).filter { $0.availability.isSelectable }
        let ids = Set(ready.map(\.id))
        if on { selectedItemIDs.formUnion(ids) } else { selectedItemIDs.subtract(ids) }
    }

    func selectedItems(in category: CategoryID) -> [ScanItem] {
        (lastReport?.items(in: category) ?? []).filter {
            selectedItemIDs.contains($0.id) && $0.availability.isSelectable
        }
    }

    /// Clicking "Cleanup" in the sidebar while it is open goes back to the cards (never during a cleanup).
    func resetCleanupRoute() {
        guard !isCleaning else { return }
        cleanupRoute = .cards
    }

    // MARK: Cleaning

    /// Opens the confirmation. Nothing is touched until `confirmClean()`.
    func requestClean(_ items: [ScanItem]) {
        guard !isCleaning, !isScanning else { return }
        let ready = items.filter { $0.availability.isSelectable }
        guard !ready.isEmpty else { return }
        pendingPlan = CleanPlan(items: ready)
    }

    func requestCleanSafe() {
        guard let report = lastReport else { return }
        selection = .cleanup
        cleanupRoute = .cards
        requestClean(report.items.filter { $0.safety == .safe })
    }

    func dismissPlan() {
        pendingPlan = nil
    }

    /// Runs the confirmed plan off the main actor. Progress events come in execution order, so they are
    /// matched to items by path.
    func confirmClean() {
        guard let plan = pendingPlan else { return }
        pendingPlan = nil
        guard !isCleaning, !isScanning else { return }
        cleanQueue = plan.executionOrder
        cleanEntries = []
        isStopping = false
        notice = nil
        cleanupRoute = .progress

        let cleaner = Cleaner(environment: environment)
        let items = plan.items
        let (stream, continuation) = AsyncStream.makeStream(of: CleanProgress.self)
        let worker = Task.detached(priority: .userInitiated) {
            await cleaner.clean(items) { continuation.yield($0) }
        }
        cleanWorker = worker
        cleanTask = Task { [weak self] in
            let updates = Task { @MainActor [weak self] in
                for await progress in stream { self?.cleanEntries.append(progress.entry) }
            }
            let record = await worker.value
            continuation.finish()
            await updates.value
            self?.finishClean(record)
        }
    }

    /// Stop: the item in progress finishes, the rest is skipped as "stopped".
    func stopClean() {
        guard isCleaning else { return }
        isStopping = true
        cleanWorker?.cancel()
    }

    func waitForClean() async {
        await cleanTask?.value
    }

    private func finishClean(_ record: CleanupRecord) {
        cleanWorker = nil
        cleanTask = nil
        isStopping = false
        do {
            try historyStore.append(record)
            unsavedRecord = nil
        } catch {
            unsavedRecord = record
        }
        reloadHistory()
        let cleaned = Set(record.entries.filter { $0.status == .done }.map(\.originalPath))
        applyCleanup(removing: cleaned, latest: history.first)
        cleanupRoute = .result(record.id)
    }

    // MARK: Undo and purge

    func undo(_ recordID: UUID) async {
        guard busyRecord == nil else { return }
        busyRecord = recordID
        notice = nil
        let store = historyStore
        let trash = environment.trash
        let result = await Task.detached { Result { try store.undo(recordID: recordID, trash: trash) } }.value
        switch result {
        case .success(let undone): notice = .restored(undone.restored, stayed: undone.failures.count)
        case .failure: notice = .failed
        }
        afterTrashAction()
    }

    func purge(_ recordID: UUID) async {
        guard busyRecord == nil else { return }
        busyRecord = recordID
        notice = nil
        let store = historyStore
        let trash = environment.trash
        let result = await Task.detached { Result { try store.purge(recordID: recordID, trash: trash) } }.value
        switch result {
        case .success(let purged):
            notice = .freed(purged.freedBytes, purged: purged.purged, stayed: purged.failures.count)
        case .failure:
            notice = .failed
        }
        afterTrashAction()
    }

    private func afterTrashAction() {
        reloadHistory()
        applyCleanup(removing: [], latest: history.first)
        busyRecord = nil
    }

    // MARK: Snapshots (fixed states for QA images)

    func freezeCleaning(queue: [ScanItem], done: [CleanupEntry]) {
        cleanQueue = queue
        cleanEntries = done
        isStopping = false
        cleanupRoute = .progress
    }
}
