import Foundation
import Testing
@testable import SpareCore

@Suite struct CleanPlanTests {
    func item(_ ruleID: String, _ name: String, size: Int64, inUse: String? = nil) -> ScanItem {
        let rule = RuleCatalog.standard.rule(id: ruleID)!
        return ScanItem(ruleID: ruleID, category: rule.category, url: URL(fileURLWithPath: "/h/\(name)"),
                        sizeBytes: size, safety: rule.safety, inUseBy: inUse)
    }

    @Test func summarizesWhatWillHappen() {
        let plan = CleanPlan(items: [
            item("downloads.installers", "a.dmg", size: 100),
            item("apps.logs", "Logs/x", size: 50),
            item("dev.npm", "npm", size: 30),
            item("system.trash", ".Trash", size: 20),
        ], catalog: .standard)

        #expect(plan.trashCount == 1)
        #expect(plan.trashBytes == 100)
        #expect(plan.deleteCount == 1)
        #expect(plan.deleteBytes == 50)
        #expect(plan.commandCount == 1)
        #expect(plan.emptiesTrash)
        #expect(plan.totalBytes == 200)
    }

    @Test func defaultSelectionIsSafeAndFree() {
        let items = [
            item("apps.logs", "safe", size: 1),
            item("ai.whisper", "review", size: 1),
            item("apps.caches", "busy", size: 1, inUse: "Slack"),
            item("dev.npx", "unknown", size: 1, inUse: "unknown"),
            item("dev.pip", "pip", size: 1, inUse: "unknown"),
        ]

        #expect(CleanPlan.defaultSelection(for: items) == ["/h/safe"])
    }

    @Test func aPathListedTwiceCountsOnce() {
        let plan = CleanPlan(items: [
            item("apps.logs", "same", size: 40),
            item("apps.logs", "same", size: 40),
        ])

        #expect(plan.items.count == 1)
        #expect(plan.deleteCount == 1)
        #expect(plan.totalBytes == 40)
    }

    @Test func emptyingTheTrashComesFirstInExecutionOrder() {
        let plan = CleanPlan(items: [
            item("apps.logs", "a", size: 1),
            item("system.trash", ".Trash", size: 1),
            item("downloads.installers", "b.dmg", size: 1),
        ])

        #expect(plan.executionOrder.map(\.id) == ["/h/.Trash", "/h/a", "/h/b.dmg"])
        #expect(plan.items.map(\.id) == ["/h/a", "/h/.Trash", "/h/b.dmg"])
    }

    @Test func outcomeSeparatesTrashedFromFreedNow() {
        func entry(_ path: String, _ action: ActionKind, _ size: Int64, _ status: EntryStatus) -> CleanupEntry {
            CleanupEntry(ruleID: "x", category: .logs, originalPath: path,
                         trashPath: action == .trash ? "/t/\(path)" : nil, action: action, sizeBytes: size, status: status)
        }
        let record = CleanupRecord(
            startedAt: Date(), finishedAt: Date(), freeBytesBefore: 1, freeBytesAfter: 2,
            entries: [
                entry("/a", .delete, 100, .done),
                entry("/b", .trash, 40, .done),
                entry("/c", .delete, 7, .skipped),
                entry("/d", .command, 9, .failed),
            ], cancelled: false)

        let outcome = CleanOutcome(record)

        #expect(outcome.cleanedCount == 2)
        #expect(outcome.cleanedBytes == 140)
        #expect(outcome.trashedBytes == 40)
        #expect(outcome.freedBytes == 100)
        #expect(outcome.skippedCount == 1)
        #expect(outcome.failedCount == 1)
    }
}
