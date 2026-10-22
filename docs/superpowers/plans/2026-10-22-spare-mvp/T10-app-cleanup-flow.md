# Task 10: Cleanup flow and History in the app

The full cleaning journey in the window: category cards, per-category review with checkboxes, confirmation sheet, live progress with Stop, result with before and after, Undo and "Free it now" (purge), plus the History screen. Read `docs/planta/03-TELAS-E-FLUXOS.md` (T3 to T7, T10) first.

**Files:**
- Create: `Sources/SpareApp/AppModel+Cleanup.swift`
- Create: `Sources/SpareApp/Views/CleanupView.swift`, `Sources/SpareApp/Views/CategoryCard.swift`, `Sources/SpareApp/Views/ReviewView.swift`, `Sources/SpareApp/Views/ConfirmCleanSheet.swift`, `Sources/SpareApp/Views/CleanProgressView.swift`, `Sources/SpareApp/Views/CleanResultView.swift`, `Sources/SpareApp/Views/HistoryView.swift`, `Sources/SpareApp/Views/EntryText.swift`
- Modify: `Sources/SpareApp/AppModel.swift` (stored properties listed below), `Sources/SpareApp/Views/MainView.swift`, `Sources/SpareApp/Views/OverviewView.swift` (add "Clean what's safe")
- Modify: `Localization/pt-BR.lproj/Localizable.strings`
- Test: `Tests/SpareCoreTests/CleanPlanTests.swift`
- Create: `Sources/SpareCore/Clean/CleanPlan.swift`
- Modify: `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `AppModel` (Task 9), `Cleaner`, `HistoryStore`, `ScanReport.removing(paths:)`, `RuleCatalog`, `CleanupRecord`, `EntryStatus`, `SkipReason`, `CategoryID.title/explanation/symbol/displayOrder`, `Safety.title/color`.
- Produces:
  - Core: `struct CleanPlan: Sendable, Equatable { items: [ScanItem]; trashCount: Int; trashBytes: Int64; deleteCount: Int; deleteBytes: Int64; commandCount: Int; emptiesTrash: Bool; totalBytes: Int64 }` with `init(items:catalog:)`, and `CleanPlan.defaultSelection(for: [ScanItem]) -> Set<String>` (safe and not in use).
  - App model additions: `enum CleanupRoute: Equatable { cards, review(CategoryID), progress, result(UUID) }`; properties `cleanupRoute`, `selectedItemIDs: Set<String>`, `pendingPlan: CleanPlan?`, `cleanEntries: [CleanupEntry]`, `cleanTotal: Int`, `history: [CleanupRecord]`; methods `openReview(_:)`, `requestClean(_ items:)`, `requestCleanSafe()`, `confirmClean()`, `cancelClean()`, `undo(_ recordID: UUID)`, `purge(_ recordID: UUID)`, `reloadHistory()`, `record(id:) -> CleanupRecord?`.

- [ ] **Step 1: Write the failing plan tests**

`Tests/SpareCoreTests/CleanPlanTests.swift`:

```swift
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
        ]

        #expect(CleanPlan.defaultSelection(for: items) == ["/h/safe"])
    }
}
```

Run: `swift test --filter CleanPlanTests` → FAIL.

- [ ] **Step 2: Implement `CleanPlan`**

`Sources/SpareCore/Clean/CleanPlan.swift`:

```swift
import Foundation

/// What a confirmation dialog needs to tell the user before cleaning.
public struct CleanPlan: Sendable, Equatable {
    public let items: [ScanItem]
    public private(set) var trashCount = 0
    public private(set) var trashBytes: Int64 = 0
    public private(set) var deleteCount = 0
    public private(set) var deleteBytes: Int64 = 0
    public private(set) var commandCount = 0
    public private(set) var emptiesTrash = false

    public init(items: [ScanItem], catalog: RuleCatalog = .standard) {
        self.items = items
        for item in items {
            switch catalog.rule(id: item.ruleID)?.action {
            case .trash:
                trashCount += 1
                trashBytes += item.sizeBytes
            case .delete:
                deleteCount += 1
                deleteBytes += item.sizeBytes
            case .command:
                commandCount += 1
            case .emptyTrash:
                emptiesTrash = true
            case nil:
                break
            }
        }
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    public static func defaultSelection(for items: [ScanItem]) -> Set<String> {
        Set(items.filter { $0.safety == .safe && $0.inUseBy == nil }.map(\.id))
    }
}
```

Run: `swift test --filter CleanPlanTests` → PASS.

- [ ] **Step 3: App model cleanup state**

Add to `AppModel` (stored properties must live in the class body, not in an extension):

```swift
    var cleanupRoute: CleanupRoute = .cards
    var selectedItemIDs: Set<String> = []
    var pendingPlan: CleanPlan?
    var cleanEntries: [CleanupEntry] = []
    var cleanTotal = 0
    var history: [CleanupRecord] = []
    @ObservationIgnored var cleanTask: Task<Void, Never>?
```

and in `init`, after `lastReport = reportStore.load()`: `history = HistoryStore(directory: support).load()`.

`Sources/SpareApp/AppModel+Cleanup.swift`:

```swift
import SpareCore
import SwiftUI

enum CleanupRoute: Equatable {
    case cards
    case review(CategoryID)
    case progress
    case result(UUID)
}

extension AppModel {
    var historyStore: HistoryStore { HistoryStore(directory: environment.supportDirectory) }

    var isCleaning: Bool { cleanupRoute == .progress }

    func reloadHistory() {
        history = historyStore.load()
    }

    func record(id: UUID) -> CleanupRecord? {
        history.first { $0.id == id }
    }

    func openReview(_ category: CategoryID) {
        let items = lastReport?.items(in: category) ?? []
        selectedItemIDs = CleanPlan.defaultSelection(for: items)
        cleanupRoute = .review(category)
    }

    func requestClean(_ items: [ScanItem]) {
        let free = items.filter { $0.inUseBy == nil }
        guard !free.isEmpty else { return }
        pendingPlan = CleanPlan(items: free)
    }

    func requestCleanSafe() {
        guard let report = lastReport else { return }
        selection = .cleanup
        requestClean(report.items.filter { $0.safety == .safe && $0.inUseBy == nil })
    }

    func confirmClean() {
        guard let plan = pendingPlan else { return }
        pendingPlan = nil
        cleanEntries = []
        cleanTotal = plan.items.count
        cleanupRoute = .progress
        let cleaner = Cleaner(environment: environment)
        let items = plan.items
        cleanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let record = await cleaner.clean(items) { progress in
                Task { @MainActor [weak self] in self?.cleanEntries.append(progress.entry) }
            }
            await self?.finishClean(record)
        }
    }

    func cancelClean() {
        cleanTask?.cancel()
    }

    private func finishClean(_ record: CleanupRecord) {
        try? historyStore.append(record)
        let cleaned = Set(record.entries.filter { $0.status == .done }.map(\.originalPath))
        if let report = lastReport {
            lastReport = report.removing(paths: cleaned)
            if let updated = lastReport { try? reportStore.save(updated) }
        }
        reloadHistory()
        refreshDisk()
        cleanupRoute = .result(record.id)
    }

    func undo(_ recordID: UUID) {
        _ = try? historyStore.undo(recordID: recordID, trash: environment.trash)
        reloadHistory()
        refreshDisk()
    }

    func purge(_ recordID: UUID) {
        _ = try? historyStore.purge(recordID: recordID)
        reloadHistory()
        refreshDisk()
    }
}
```

`finishClean` is called from the detached task with `await self?.finishClean(record)`; since `AppModel` is `@MainActor`, extension methods are main-actor isolated. Keep `finishClean` non-private (`func`) if the compiler rejects private access from the closure.

- [ ] **Step 4: Views**

`Sources/SpareApp/Views/CleanupView.swift`:

```swift
import SpareCore
import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.cleanupRoute {
            case .cards: cards
            case .review(let category): ReviewView(category: category)
            case .progress: CleanProgressView()
            case .result(let id): CleanResultView(recordID: id)
            }
        }
        .navigationTitle("Cleanup")
        .sheet(item: $model.pendingPlan) { plan in
            ConfirmCleanSheet(plan: plan)
        }
    }

    @ViewBuilder
    private var cards: some View {
        if let report = model.lastReport {
            let visible = CategoryID.displayOrder.filter { !report.items(in: $0).isEmpty }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("You can free \(ByteFormat.string(report.safeReclaimableBytes)) safely")
                            .font(.title.bold())
                        Spacer()
                        Button("Clean what's safe") { model.requestCleanSafe() }
                            .buttonStyle(.borderedProminent)
                            .disabled(report.safeReclaimableBytes == 0)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(visible, id: \.self) { category in
                            CategoryCard(category: category, items: report.items(in: category))
                        }
                    }
                    let empty = CategoryID.displayOrder.count - visible.count
                    if empty > 0 {
                        Text("\(String(empty)) categories with nothing to clean")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView {
                Label("No analysis yet", systemImage: "magnifyingglass")
            } description: {
                Text("Run an analysis to see what can be freed.")
            } actions: {
                Button("Analyze everything") {
                    model.selection = .overview
                    model.startScan()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

extension CleanPlan: Identifiable {
    public var id: String { items.map(\.id).joined(separator: "|") }
}
```

`Sources/SpareApp/Views/CategoryCard.swift`:

```swift
import SpareCore
import SwiftUI

struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID
    let items: [ScanItem]

    private var safety: Safety { items.allSatisfy { $0.safety == .safe } ? .safe : .review }
    private var freeItems: [ScanItem] { items.filter { $0.inUseBy == nil } }
    private var total: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(category.title, systemImage: category.symbol)
                        .font(.headline)
                    Spacer()
                    Text(safety.title)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(safety.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(safety.color)
                }
                Text(verbatim: ByteFormat.string(total))
                    .font(.title2.bold().monospacedDigit())
                Text(category.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Review") { model.openReview(category) }
                    if safety == .safe {
                        Button("Clean") { model.requestClean(freeItems) }
                            .buttonStyle(.borderedProminent)
                            .disabled(freeItems.isEmpty)
                    }
                }
            }
            .padding(6)
        }
    }
}
```

`Sources/SpareApp/Views/ReviewView.swift`:

```swift
import AppKit
import SpareCore
import SwiftUI

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    let category: CategoryID

    private var items: [ScanItem] { model.lastReport?.items(in: category) ?? [] }
    private var selected: [ScanItem] { items.filter { model.selectedItemIDs.contains($0.id) } }
    private var selectedSize: String { ByteFormat.string(selected.reduce(0) { $0 + $1.sizeBytes }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.cleanupRoute = .cards
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            Label(category.title, systemImage: category.symbol)
                .font(.title2.bold())
            Text(category.explanation)
                .foregroundStyle(.secondary)
            List(items) { item in
                row(item)
            }
            HStack {
                Text("Selected: \(String(selected.count)) items, \(selectedSize)")
                    .monospacedDigit()
                Spacer()
                Button("Clean selected") { model.requestClean(selected) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(24)
    }

    private func row(_ item: ScanItem) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: binding(for: item)) { EmptyView() }
                .toggleStyle(.checkbox)
                .disabled(item.inUseBy != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: RuleDisplay.name(for: item))
                Text(verbatim: item.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let user = item.inUseBy {
                Text("In use by: \(user)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let date = item.lastModified {
                Text(verbatim: date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: ByteFormat.string(item.sizeBytes))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
    }

    private func binding(for item: ScanItem) -> Binding<Bool> {
        Binding(
            get: { model.selectedItemIDs.contains(item.id) },
            set: { isOn in
                if isOn { model.selectedItemIDs.insert(item.id) } else { model.selectedItemIDs.remove(item.id) }
            })
    }
}

enum RuleDisplay {
    static let names: [String: String] = [
        "dev.npm": "npm", "dev.pnpm": "pnpm", "dev.yarn": "Yarn", "dev.uv": "uv", "dev.pip": "pip",
        "dev.cargo": "Cargo", "dev.homebrew": "Homebrew", "dev.xcodeDerivedData": "Xcode DerivedData",
        "dev.preCommit": "pre-commit", "dev.playwright": "Playwright", "ai.huggingface": "Hugging Face",
        "ai.whisper": "Whisper", "ai.ollama": "Ollama", "ai.lmstudio": "LM Studio", "ai.claudeVM": "Claude VM",
        "system.trash": "Trash",
    ]

    /// Tool name for single-path rules; folder name (with project for leftovers) otherwise.
    static func name(for item: ScanItem) -> String {
        if item.category == .projectLeftovers {
            let project = item.url.deletingLastPathComponent().lastPathComponent
            return "\(project)/\(item.url.lastPathComponent)"
        }
        return names[item.ruleID] ?? item.url.lastPathComponent
    }
}
```

`Sources/SpareApp/Views/ConfirmCleanSheet.swift`:

```swift
import SpareCore
import SwiftUI

struct ConfirmCleanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: CleanPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clean \(String(plan.items.count)) items (\(ByteFormat.string(plan.totalBytes)))?")
                .font(.title3.bold())
            if plan.deleteCount + plan.commandCount > 0 {
                Label("Caches and leftovers that rebuild themselves are removed for good to free space now.",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            if plan.trashCount > 0 {
                Label("\(String(plan.trashCount)) items (\(ByteFormat.string(plan.trashBytes))) go to the Trash and can be undone.",
                      systemImage: "trash")
            }
            if plan.emptiesTrash {
                Label("Emptying the Trash cannot be undone.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clean") {
                    // confirmClean reads pendingPlan; dismissing first would nil it through the binding.
                    model.confirmClean()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
```

`Sources/SpareApp/Views/CleanProgressView.swift`:

```swift
import SpareCore
import SwiftUI

struct CleanProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleaning...")
                .font(.title2.bold())
            ProgressView(value: Double(model.cleanEntries.count), total: Double(max(model.cleanTotal, 1)))
            List(model.cleanEntries) { entry in
                EntryRow(entry: entry)
            }
            HStack {
                Spacer()
                Button("Stop") { model.cancelClean() }
                    .controlSize(.large)
            }
        }
        .padding(24)
    }
}
```

`Sources/SpareApp/Views/EntryText.swift`:

```swift
import SpareCore
import SwiftUI

struct EntryRow: View {
    let entry: CleanupEntry

    var body: some View {
        HStack {
            Image(systemName: entry.statusSymbol)
                .foregroundStyle(entry.statusColor)
            VStack(alignment: .leading) {
                Text(verbatim: (entry.originalPath as NSString).lastPathComponent)
                if let reason = entry.reasonText {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(verbatim: ByteFormat.string(entry.sizeBytes))
                .monospacedDigit()
        }
    }
}

extension CleanupEntry {
    var statusSymbol: String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .failed: "xmark.octagon.fill"
        case .restored: "arrow.uturn.backward.circle"
        case .purged: "flame"
        }
    }

    var statusColor: Color {
        switch status {
        case .done, .restored: .green
        case .skipped: .secondary
        case .failed: .red
        case .purged: .orange
        }
    }

    var reasonText: LocalizedStringKey? {
        // Keep interpolations simple (no nested quotes) so scripts/check-strings.py can read the key.
        let info = detail ?? ""
        switch skipReason {
        case .inUse: LocalizedStringKey("In use by: \(info)")
        case .notFound: LocalizedStringKey("Already gone")
        case .outsideCatalog, .protected: LocalizedStringKey("Protected, not touched")
        case .cancelled: LocalizedStringKey("Stopped")
        case .toolNotFound: LocalizedStringKey("Tool not installed")
        case nil:
            if status == .failed { return LocalizedStringKey("Failed: \(info)") }
            if status == .restored { return LocalizedStringKey("Restored") }
            if status == .purged { return LocalizedStringKey("Deleted from the Trash") }
            if action == .trash { return LocalizedStringKey("In the Trash") }
            return nil
        }
    }
}
```

`Sources/SpareApp/Views/CleanResultView.swift`:

```swift
import SpareCore
import SwiftUI

struct CleanResultView: View {
    @Environment(AppModel.self) private var model
    let recordID: UUID

    var body: some View {
        if let record = model.record(id: recordID) {
            VStack(alignment: .leading, spacing: 16) {
                (record.cancelled ? Text("Cleanup stopped") : Text("Cleanup complete"))
                    .font(.largeTitle.bold())
                if let before = record.freeBytesBefore, let after = record.freeBytesAfter {
                    Text("\(ByteFormat.string(before)) → \(ByteFormat.string(after)) free")
                        .font(.title.monospacedDigit())
                }
                Text("Cleaned \(ByteFormat.string(record.cleanedBytes))")
                    .foregroundStyle(.secondary)
                if record.trashedBytes > 0 {
                    GroupBox {
                        HStack {
                            Text("\(ByteFormat.string(record.trashedBytes)) are in the Trash. Space is freed when they leave it.")
                            Spacer()
                            Button("Undo") { model.undo(record.id) }
                            Button("Free it now") { model.purge(record.id) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                List(record.entries) { entry in
                    EntryRow(entry: entry)
                }
                HStack {
                    Button("View history") { model.selection = .history }
                    Spacer()
                    Button("OK") { model.cleanupRoute = .cards }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        } else {
            ProgressView()
        }
    }
}
```

The arrow `→` is allowed (it is not a dash). Its key in the strings file is `"%@ → %@ free"`.

`Sources/SpareApp/Views/HistoryView.swift`:

```swift
import SpareCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: UUID?

    var body: some View {
        HSplitView {
            List(model.history, selection: $selectedID) { record in
                VStack(alignment: .leading) {
                    Text(verbatim: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("Cleaned \(ByteFormat.string(record.cleanedBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(record.id)
            }
            .frame(minWidth: 220, maxWidth: 280)

            if let id = selectedID, let record = model.record(id: id) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(verbatim: record.startedAt.formatted(date: .complete, time: .shortened))
                            .font(.headline)
                        Spacer()
                        if !record.undoableEntries.isEmpty {
                            Button("Undo") { model.undo(record.id) }
                            Button("Free it now") { model.purge(record.id) }
                        }
                    }
                    List(record.entries) { entry in
                        EntryRow(entry: entry)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Select a cleanup", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("History")
        .onAppear { model.reloadHistory() }
    }
}
```

`MainView` detail switch:

```swift
            switch model.selection ?? .overview {
            case .overview: OverviewView()
            case .cleanup: CleanupView()
            case .history: HistoryView()
            default:
                ContentUnavailableView("Coming in the next update", systemImage: "hammer")
            }
```

`OverviewView.finished`: add `Button("Clean what's safe") { model.requestCleanSafe() }` next to "Review all" (disabled when `report.safeReclaimableBytes == 0`). Because the confirmation sheet lives in `CleanupView`, `requestCleanSafe()` already switches `selection` to `.cleanup` before setting `pendingPlan`.

- [ ] **Step 5: Translations**

Append to `pt-BR.lproj/Localizable.strings` every new literal. Run `python3 scripts/check-strings.py`; it prints each missing key. Required translations (complete list as of this task):

```
"Clean what's safe" = "Limpar o que é seguro";
"%@ categories with nothing to clean" = "%@ categorias sem nada para limpar";
"No analysis yet" = "Nenhuma análise ainda";
"Run an analysis to see what can be freed." = "Faça uma análise para ver o que pode ser liberado.";
"Clean" = "Limpar";
"Back" = "Voltar";
"Selected: %@ items, %@" = "Selecionados: %@ itens, %@";
"Clean selected" = "Limpar selecionados";
"In use by: %@" = "Em uso por: %@";
"Show in Finder" = "Mostrar no Finder";
"Clean %@ items (%@)?" = "Limpar %@ itens (%@)?";
"Caches and leftovers that rebuild themselves are removed for good to free space now." = "Caches e restos que se regeneram sozinhos são apagados de vez para liberar espaço agora.";
"%@ items (%@) go to the Trash and can be undone." = "%@ itens (%@) vão para a Lixeira e podem ser desfeitos.";
"Cancel" = "Cancelar";
"Cleaning..." = "Limpando...";
"Already gone" = "Já não existia";
"Protected, not touched" = "Protegido, não foi tocado";
"Stopped" = "Interrompido";
"Tool not installed" = "Ferramenta não instalada";
"Failed: %@" = "Falhou: %@";
"Restored" = "Restaurado";
"Deleted from the Trash" = "Apagado da Lixeira";
"In the Trash" = "Na Lixeira";
"Cleanup stopped" = "Limpeza interrompida";
"Cleanup complete" = "Limpeza concluída";
"%@ → %@ free" = "%@ → %@ livres";
"Cleaned %@" = "Liberado: %@";
"%@ are in the Trash. Space is freed when they leave it." = "%@ estão na Lixeira. O espaço volta quando saírem de lá.";
"Undo" = "Desfazer";
"Free it now" = "Liberar agora";
"View history" = "Ver histórico";
"OK" = "OK";
"Select a cleanup" = "Selecione uma limpeza";
```

- [ ] **Step 6: Manual verification on a fake home (never the real one first)**

1. Create a fake home with `scripts/qa-fake-home.sh --keep` (add a `--keep` flag in this task that skips the final cleanup and prints the path).
2. Launch the bundled app against it: `HOME` cannot be overridden for SwiftUI apps reliably, so add support for a `SPARE_HOME` environment variable in `AppModel.init` (`ProcessInfo.processInfo.environment["SPARE_HOME"]`) and a `SPARE_TRASH_DIR` override that swaps `environment.trash` for `DirectoryTrash` (both only read at launch, documented as developer options in CONTRIBUTING).
3. `SPARE_HOME=<fake> SPARE_TRASH_DIR=<fake>/.Trash dist/Spare.app/Contents/MacOS/Spare --show overview`, run Analyze everything, open Cleanup, review a category, clean, check progress, result, Undo, Free it now, History. Screenshot each state with `screencapture -x`.
4. Expected: only fake-home files change; the real home is untouched (`spare scan` on the real home before and after gives the same totals within normal drift).

- [ ] **Step 7: Docs, gates, commit**

CHANGELOG `Added: cleanup flow (cards, review, confirm, progress, result, undo, free now) and History`; STATUS; CONTRIBUTING (developer env vars). `scripts/check.sh` green; screenshots in the PR.

```bash
git add -A
git commit -m "feat(app): add cleanup flow and history screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
