# Task 9: App shell, settings, recommendation and "Analyze everything"

Turns the skeleton app into the real shell: persisted settings, the "Today's recommendation" logic, an `@Observable` app model, the menu bar panel (disk card, memory card, recommendation, Analyze everything), the main window with its sidebar, and the Overview screen running a live scan with Stop. Read `docs/planta/03-TELAS-E-FLUXOS.md` (T1, T2) first.

**Files:**
- Create: `Sources/SpareCore/Settings/SpareSettings.swift`, `Sources/SpareCore/Settings/SettingsStore.swift`, `Sources/SpareCore/Settings/ScanReportStore.swift`, `Sources/SpareCore/Insights/Recommendation.swift`
- Modify: `Sources/SpareCore/Support/SpareEnvironment.swift` (add `live(home:settings:)`)
- Replace: `Sources/SpareApp/SpareApp.swift`
- Create: `Sources/SpareApp/AppModel.swift`, `Sources/SpareApp/AppSection.swift`, `Sources/SpareApp/MainWindowController.swift`, `Sources/SpareApp/Views/MenuPanel.swift`, `Sources/SpareApp/Views/MainView.swift`, `Sources/SpareApp/Views/OverviewView.swift`, `Sources/SpareApp/Views/CategoryText.swift`
- Modify: `Localization/pt-BR.lproj/Localizable.strings`
- Test: `Tests/SpareCoreTests/SettingsTests.swift`, `Tests/SpareCoreTests/RecommendationTests.swift`
- Modify: `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: everything in `SpareCore` from Tasks 1 to 8.
- Produces (core):
  - `SpareSettings: Codable, Sendable, Equatable { diskAlertThresholdGB: Int = 15; memoryAlertsEnabled: Bool = true; projectRootPaths: [String]; projectIdleDays: Int = 30 }`, `static func defaults(home:)`, tolerant decoding (missing keys use defaults).
  - `SettingsStore(directory:)`: `load(home:) -> SpareSettings`, `save(_:) throws`.
  - `ScanReportStore(directory:)`: `load() -> ScanReport?`, `save(_:) throws` (file `last-scan.json`).
  - `enum Recommendation: Equatable, Sendable { case lowDisk(freeBytes: Int64), reclaimable(bytes: Int64), highMemory, allGood }`, `static func compute(disk:thresholdGB:lastScan:memory:) -> Recommendation`. Constant `Recommendation.reclaimableThreshold: Int64 = 10_000_000_000`.
  - `SpareEnvironment.live(home: URL, settings: SpareSettings) -> SpareEnvironment`.
- Produces (app):
  - `enum AppSection: String, CaseIterable, Identifiable { overview, cleanup, largeFiles, memory, history, settings }` with `title: LocalizedStringKey`, `symbol: String`.
  - `@MainActor @Observable final class AppModel` with: `settings`, `disk: DiskSpace?`, `memory: MemorySnapshot?`, `lastReport: ScanReport?`, `scanState: ScanState`, `scanTotals: [CategoryID: Int64]`, `finishedCategories: Set<CategoryID>`, `selection: AppSection?`, `menuTitle: String`, `menuSymbol: String`, `recommendation: Recommendation`, `environment: SpareEnvironment`, methods `refreshDisk()`, `refreshMemory()`, `startScan()`, `cancelScan()`, `show(_ section: AppSection)`, `saveSettings()`.
  - `enum ScanState { case idle, scanning(ScanProgress?), finished(ScanReport) }`.
  - `MainWindowController.shared.show(model:)`.
  - `extension CategoryID { var title: LocalizedStringKey; var explanation: LocalizedStringKey; var symbol: String }` and `extension Safety { var title: LocalizedStringKey }` in `CategoryText.swift`. `static let displayOrder: [CategoryID]`.
  - Launch argument `--show <section rawValue>` opens the main window on that section (used for QA screenshots).

- [ ] **Step 1: Write the failing core tests**

`Tests/SpareCoreTests/SettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct SettingsTests {
    @Test func defaultsUseExistingProjectFolders() throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.directory("Projetos")

        let settings = SpareSettings.defaults(home: home.url)

        #expect(settings.diskAlertThresholdGB == 15)
        #expect(settings.memoryAlertsEnabled)
        #expect(settings.projectIdleDays == 30)
        #expect(settings.projectRootPaths == [home.path("Projetos").path])
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(SpareSettings.self, from: Data(#"{"diskAlertThresholdGB": 20}"#.utf8))

        #expect(decoded.diskAlertThresholdGB == 20)
        #expect(decoded.projectIdleDays == 30)
        #expect(decoded.memoryAlertsEnabled)
    }

    @Test func storeRoundTripsAndSurvivesCorruption() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = SettingsStore(directory: home.path("support"))
        var settings = SpareSettings.defaults(home: home.url)
        settings.diskAlertThresholdGB = 25

        try store.save(settings)
        #expect(store.load(home: home.url).diskAlertThresholdGB == 25)

        try "not json".write(to: home.path("support/settings.json"), atomically: true, encoding: .utf8)
        #expect(store.load(home: home.url).diskAlertThresholdGB == 15)
    }

    @Test func lastScanStoreRoundTripsAndToleratesCorruption() throws {
        let home = try TempHome()
        defer { home.remove() }
        let store = ScanReportStore(directory: home.path("support"))
        let report = ScanReport(items: [], startedAt: Date(), finishedAt: Date(), freeBytesBefore: 5, cancelled: false)

        try store.save(report)
        #expect(store.load()?.freeBytesBefore == 5)

        try "{".write(to: home.path("support/last-scan.json"), atomically: true, encoding: .utf8)
        #expect(store.load() == nil)
    }

    @Test func liveEnvironmentUsesSettings() throws {
        let home = try TempHome()
        defer { home.remove() }
        var settings = SpareSettings.defaults(home: home.url)
        settings.projectRootPaths = [home.path("Work").path]
        settings.projectIdleDays = 45

        let environment = SpareEnvironment.live(home: home.url, settings: settings)

        #expect(environment.projectRoots.map(\.path) == [home.path("Work").path])
        #expect(environment.projectIdleDays == 45)
    }
}
```

`Tests/SpareCoreTests/RecommendationTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore

@Suite struct RecommendationTests {
    let roomy = DiskSpace(freeBytes: 80_000_000_000, totalBytes: 228_000_000_000)
    let tight = DiskSpace(freeBytes: 9_000_000_000, totalBytes: 228_000_000_000)
    let calm = MemorySnapshot(totalBytes: 16, usedBytes: 8, compressedBytes: 0, level: .normal)
    let busy = MemorySnapshot(totalBytes: 16, usedBytes: 15, compressedBytes: 4, level: .warning)

    func report(safeBytes: Int64) -> ScanReport {
        let item = ScanItem(ruleID: "dev.npm", category: .devCaches, url: URL(fileURLWithPath: "/x"),
                            sizeBytes: safeBytes, safety: .safe)
        return ScanReport(items: [item], startedAt: Date(), finishedAt: Date(), freeBytesBefore: nil, cancelled: false)
    }

    @Test func lowDiskWinsOverEverything() {
        #expect(Recommendation.compute(disk: tight, thresholdGB: 15, lastScan: report(safeBytes: 20_000_000_000), memory: busy)
                == .lowDisk(freeBytes: 9_000_000_000))
    }

    @Test func reclaimableWhenLastScanFoundMoreThanTenGB() {
        #expect(Recommendation.compute(disk: roomy, thresholdGB: 15, lastScan: report(safeBytes: 23_000_000_000), memory: busy)
                == .reclaimable(bytes: 23_000_000_000))
    }

    @Test func highMemoryNext() {
        #expect(Recommendation.compute(disk: roomy, thresholdGB: 15, lastScan: report(safeBytes: 1), memory: busy) == .highMemory)
    }

    @Test func allGoodOtherwise() {
        #expect(Recommendation.compute(disk: roomy, thresholdGB: 15, lastScan: nil, memory: calm) == .allGood)
        #expect(Recommendation.compute(disk: nil, thresholdGB: 15, lastScan: nil, memory: nil) == .allGood)
    }
}
```

Run: `swift test --filter "SettingsTests|RecommendationTests"` → FAIL.

- [ ] **Step 2: Implement the core pieces**

`Sources/SpareCore/Settings/SpareSettings.swift`:

```swift
import Foundation

public struct SpareSettings: Codable, Sendable, Equatable {
    public var diskAlertThresholdGB: Int = 15
    public var memoryAlertsEnabled: Bool = true
    public var projectRootPaths: [String] = []
    public var projectIdleDays: Int = 30

    public init() {}

    public static func defaults(home: URL) -> SpareSettings {
        var settings = SpareSettings()
        settings.projectRootPaths = ProjectScanner.defaultRoots(home: home).map(\.path)
        return settings
    }

    enum CodingKeys: String, CodingKey {
        case diskAlertThresholdGB, memoryAlertsEnabled, projectRootPaths, projectIdleDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SpareSettings()
        diskAlertThresholdGB = try container.decodeIfPresent(Int.self, forKey: .diskAlertThresholdGB) ?? fallback.diskAlertThresholdGB
        memoryAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryAlertsEnabled) ?? fallback.memoryAlertsEnabled
        projectRootPaths = try container.decodeIfPresent([String].self, forKey: .projectRootPaths) ?? fallback.projectRootPaths
        projectIdleDays = try container.decodeIfPresent(Int.self, forKey: .projectIdleDays) ?? fallback.projectIdleDays
    }
}
```

`Sources/SpareCore/Settings/SettingsStore.swift`:

```swift
import Foundation

public struct SettingsStore: Sendable {
    let file: JSONFileStore<SpareSettings>

    public init(directory: URL) {
        file = JSONFileStore(url: directory.appendingPathComponent("settings.json"))
    }

    public func load(home: URL) -> SpareSettings {
        file.load() ?? .defaults(home: home)
    }

    public func save(_ settings: SpareSettings) throws {
        try file.save(settings)
    }
}
```

Note: when `settings.json` exists but has no `projectRootPaths`, decoding yields `[]`; that is the user's explicit choice and is respected.

`Sources/SpareCore/Settings/ScanReportStore.swift`:

```swift
import Foundation

public struct ScanReportStore: Sendable {
    let file: JSONFileStore<ScanReport>

    public init(directory: URL) {
        file = JSONFileStore(url: directory.appendingPathComponent("last-scan.json"))
    }

    public func load() -> ScanReport? { file.load() }

    public func save(_ report: ScanReport) throws { try file.save(report) }
}
```

`Sources/SpareCore/Insights/Recommendation.swift`:

```swift
import Foundation

public enum Recommendation: Equatable, Sendable {
    case lowDisk(freeBytes: Int64)
    case reclaimable(bytes: Int64)
    case highMemory
    case allGood

    public static let reclaimableThreshold: Int64 = 10_000_000_000

    public static func compute(
        disk: DiskSpace?, thresholdGB: Int, lastScan: ScanReport?, memory: MemorySnapshot?
    ) -> Recommendation {
        if let disk, disk.freeBytes < Int64(thresholdGB) * 1_000_000_000 {
            return .lowDisk(freeBytes: disk.freeBytes)
        }
        if let bytes = lastScan?.safeReclaimableBytes, bytes > reclaimableThreshold {
            return .reclaimable(bytes: bytes)
        }
        if let memory, memory.level != .normal {
            return .highMemory
        }
        return .allGood
    }
}
```

`SpareEnvironment`:

```swift
    public static func live(home: URL, settings: SpareSettings) -> SpareEnvironment {
        var environment = live(home: home)
        environment.projectRoots = settings.projectRootPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        environment.projectIdleDays = settings.projectIdleDays
        return environment
    }
```

Also make the CLI honor settings: in `Sources/spare/main.swift`, load `SettingsStore(directory: SpareEnvironment.live(home: home).supportDirectory).load(home: home)` and build with `.live(home:settings:)` (keep the `SPARE_TRASH_DIR` override from Task 6).

Run: `swift test` → PASS.

- [ ] **Step 3: App model**

`Sources/SpareApp/AppSection.swift`:

```swift
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, cleanup, largeFiles, memory, history, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: LocalizedStringKey("Overview")
        case .cleanup: LocalizedStringKey("Cleanup")
        case .largeFiles: LocalizedStringKey("Large Files")
        case .memory: LocalizedStringKey("Memory")
        case .history: LocalizedStringKey("History")
        case .settings: LocalizedStringKey("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .cleanup: "sparkles"
        case .largeFiles: "doc.text.magnifyingglass"
        case .memory: "memorychip"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}
```

`Sources/SpareApp/AppModel.swift`:

```swift
import AppKit
import Observation
import SpareCore
import SwiftUI

enum ScanState {
    case idle
    case scanning(ScanProgress?)
    case finished(ScanReport)
}

@MainActor
@Observable
final class AppModel {
    let home: URL
    var settings: SpareSettings
    var disk: DiskSpace?
    var memory: MemorySnapshot?
    var lastReport: ScanReport?
    var scanState: ScanState = .idle
    var scanTotals: [CategoryID: Int64] = [:]
    var finishedCategories: Set<CategoryID> = []
    var selection: AppSection? = .overview

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var lastProgressUpdate = Date.distantPast
    @ObservationIgnored let settingsStore: SettingsStore
    @ObservationIgnored let reportStore: ScanReportStore

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.resolvingSymlinksInPath()
        let support = SpareEnvironment.live(home: self.home).supportDirectory
        settingsStore = SettingsStore(directory: support)
        reportStore = ScanReportStore(directory: support)
        settings = settingsStore.load(home: self.home)
        lastReport = reportStore.load()
        refreshDisk()
        refreshMemory()
        startMonitoring()
        handleLaunchArguments()
    }

    var environment: SpareEnvironment {
        .live(home: home, settings: settings)
    }

    // MARK: Monitoring

    func refreshDisk() {
        disk = DiskMonitor.space(at: home)
    }

    func refreshMemory() {
        memory = MemoryMonitor.snapshot()
    }

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshDisk()
                self?.refreshMemory()
            }
        }
    }

    var menuTitle: String {
        guard let disk else { return "Spare" }
        return "\(ByteFormat.gigabytes(disk.freeBytes)) GB"
    }

    var menuSymbol: String {
        guard let disk else { return "internaldrive" }
        return disk.freeBytes < Int64(settings.diskAlertThresholdGB) * 1_000_000_000
            ? "exclamationmark.triangle.fill" : "internaldrive"
    }

    var recommendation: Recommendation {
        Recommendation.compute(disk: disk, thresholdGB: settings.diskAlertThresholdGB,
                               lastScan: lastReport, memory: memory)
    }

    // MARK: Scan

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    func startScan() {
        guard !isScanning else { return }
        scanTotals = [:]
        finishedCategories = []
        scanState = .scanning(nil)
        let scanner = Scanner(environment: environment)
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let report = await scanner.scan { progress in
                Task { @MainActor [weak self] in self?.apply(progress) }
            }
            await self?.finishScan(report)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func apply(_ progress: ScanProgress) {
        if let item = progress.item {
            scanTotals[item.category, default: 0] += item.sizeBytes
        }
        if let category = progress.finishedCategory {
            finishedCategories.insert(category)
        }
        let now = Date()
        if now.timeIntervalSince(lastProgressUpdate) > 0.1 || progress.finishedCategory != nil {
            lastProgressUpdate = now
            if isScanning { scanState = .scanning(progress) }
        }
    }

    private func finishScan(_ report: ScanReport) {
        lastReport = report
        scanState = .finished(report)
        finishedCategories = Set(CategoryID.allCases)
        try? reportStore.save(report)
        refreshDisk()
    }

    // MARK: Navigation and settings

    func show(_ section: AppSection) {
        selection = section
        MainWindowController.shared.show(model: self)
    }

    func saveSettings() {
        try? settingsStore.save(settings)
    }

    private func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--show"), index + 1 < arguments.count,
              let section = AppSection(rawValue: arguments[index + 1])
        else { return }
        Task { @MainActor in self.show(section) }
    }
}
```

- [ ] **Step 4: Window controller and app entry**

`Sources/SpareApp/MainWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView().environment(model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Spare"
            window.setContentSize(NSSize(width: 900, height: 600))
            window.minSize = NSSize(width: 760, height: 480)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

`Sources/SpareApp/SpareApp.swift` (replace):

```swift
import SpareCore
import SwiftUI

@main
struct SpareApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
        } label: {
            Label(model.menuTitle, systemImage: model.menuSymbol)
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: Shared category texts**

`Sources/SpareApp/Views/CategoryText.swift`:

```swift
import SpareCore
import SwiftUI

extension CategoryID {
    static let displayOrder: [CategoryID] = [
        .projectLeftovers, .devCaches, .aiTools, .appCaches, .installers, .logs, .trash,
    ]

    var title: LocalizedStringKey {
        switch self {
        case .devCaches: LocalizedStringKey("Developer caches")
        case .projectLeftovers: LocalizedStringKey("Idle project leftovers")
        case .aiTools: LocalizedStringKey("AI tools")
        case .appCaches: LocalizedStringKey("App caches")
        case .logs: LocalizedStringKey("Logs")
        case .installers: LocalizedStringKey("Forgotten installers")
        case .trash: LocalizedStringKey("Trash")
        case .largeFiles: LocalizedStringKey("Large files")
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .devCaches: LocalizedStringKey("Package manager caches. They rebuild themselves when needed.")
        case .projectLeftovers: LocalizedStringKey("Dependencies of projects untouched for a while. Reinstall with one command.")
        case .aiTools: LocalizedStringKey("Downloaded models and runtimes. Review: they download again if you use them.")
        case .appCaches: LocalizedStringKey("Temporary data of closed apps. They rebuild themselves.")
        case .logs: LocalizedStringKey("Old diagnostic logs.")
        case .installers: LocalizedStringKey("Installers in Downloads older than 30 days. Go to the Trash.")
        case .trash: LocalizedStringKey("Emptying the Trash cannot be undone.")
        case .largeFiles: LocalizedStringKey("Files you picked on the Large Files screen.")
        }
    }

    var symbol: String {
        switch self {
        case .devCaches: "hammer"
        case .projectLeftovers: "shippingbox"
        case .aiTools: "brain"
        case .appCaches: "app.dashed"
        case .logs: "doc.plaintext"
        case .installers: "arrow.down.app"
        case .trash: "trash"
        case .largeFiles: "doc"
        }
    }
}

extension Safety {
    var title: LocalizedStringKey {
        switch self {
        case .safe: LocalizedStringKey("Safe")
        case .review: LocalizedStringKey("Review")
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        }
    }
}
```

- [ ] **Step 6: Menu panel**

`Sources/SpareApp/Views/MenuPanel.swift`:

```swift
import AppKit
import SpareCore
import SwiftUI

struct MenuPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            diskCard
            memoryCard
            recommendationCard
            Button {
                model.show(.overview)
                model.startScan()
            } label: {
                Label("Analyze everything", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isScanning)
            Divider()
            HStack {
                Button("Open Spare") { model.show(.overview) }
                Spacer()
                Button("Settings") { model.show(.settings) }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            model.refreshDisk()
            model.refreshMemory()
        }
    }

    private var diskCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if let disk = model.disk {
                    Text("\(ByteFormat.string(disk.freeBytes)) free of \(ByteFormat.string(disk.totalBytes))")
                        .font(.headline.monospacedDigit())
                    ProgressView(value: disk.usedFraction)
                } else {
                    Text("Reading disk...").foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Free up") { model.show(.cleanup) }
                }
            }
        } label: {
            Label("Disk", systemImage: "internaldrive")
        }
    }

    private var memoryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if let memory = model.memory {
                    Text("\(ByteFormat.string(memory.usedBytes)) used of \(ByteFormat.string(memory.totalBytes))")
                        .font(.headline.monospacedDigit())
                    HStack {
                        Text(memory.level.title)
                            .foregroundStyle(memory.level.color)
                        Spacer()
                        Button("View") { model.show(.memory) }
                    }
                } else {
                    Text("Reading memory...").foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Memory", systemImage: "memorychip")
        }
    }

    @ViewBuilder
    private var recommendationCard: some View {
        GroupBox {
            HStack(alignment: .top) {
                switch model.recommendation {
                case .lowDisk(let free):
                    Text("Only \(ByteFormat.string(free)) left. Analyze to free space.")
                    Spacer()
                    Button("Analyze") {
                        model.show(.overview)
                        model.startScan()
                    }
                case .reclaimable(let bytes):
                    Text("You can free \(ByteFormat.string(bytes)) safely.")
                    Spacer()
                    Button("Review") { model.show(.cleanup) }
                case .highMemory:
                    Text("Memory is high. See what is using it.")
                    Spacer()
                    Button("View") { model.show(.memory) }
                case .allGood:
                    Text("All good here.")
                    Spacer()
                }
            }
        } label: {
            Label("Today's recommendation", systemImage: "lightbulb")
        }
    }
}

extension MemoryPressureLevel {
    var title: LocalizedStringKey {
        switch self {
        case .normal: LocalizedStringKey("Pressure: normal")
        case .warning: LocalizedStringKey("Pressure: attention")
        case .critical: LocalizedStringKey("Pressure: high")
        }
    }

    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}
```

- [ ] **Step 7: Main window and Overview**

`Sources/SpareApp/Views/MainView.swift`:

```swift
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(AppSection.allCases, selection: $model.selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            switch model.selection ?? .overview {
            case .overview: OverviewView()
            default:
                ContentUnavailableView("Coming in the next update", systemImage: "hammer")
            }
        }
    }
}
```

(Tasks 10 and 11 replace the `default` branch with the real screens.)

`Sources/SpareApp/Views/OverviewView.swift`:

```swift
import SpareCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            switch model.scanState {
            case .idle:
                idle
            case .scanning(let progress):
                scanning(progress)
            case .finished(let report):
                finished(report)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Overview")
    }

    private var idle: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Analyze disk and memory in a single pass.")
                .font(.title3)
            Button("Analyze everything") { model.startScan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func scanning(_ progress: ScanProgress?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analyzing...")
                .font(.title2.bold())
            categoryList
            Text(verbatim: progress?.currentPath ?? "")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Spacer()
                Button("Stop") { model.cancelScan() }
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: 560)
    }

    private var categoryList: some View {
        VStack(spacing: 8) {
            ForEach(CategoryID.displayOrder, id: \.self) { category in
                HStack {
                    Label(category.title, systemImage: category.symbol)
                    Spacer()
                    if model.finishedCategories.contains(category) {
                        Text(verbatim: ByteFormat.string(model.scanTotals[category] ?? 0))
                            .monospacedDigit()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func finished(_ report: ScanReport) -> some View {
        VStack(spacing: 16) {
            if report.cancelled {
                Label("Analysis interrupted, partial results", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text("You can free \(ByteFormat.string(report.safeReclaimableBytes)) safely")
                .font(.largeTitle.bold())
            Text("Plus \(ByteFormat.string(report.reviewBytes)) to review")
                .foregroundStyle(.secondary)
            categoryList
                .frame(maxWidth: 560)
            HStack {
                Button("Analyze again") { model.startScan() }
                Button("Review all") { model.show(.cleanup) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
    }
}
```

Note: the "Clean what's safe" button of the spec T2 is added in Task 10, where the cleaning flow exists.

- [ ] **Step 8: Translations**

Append to `Localization/pt-BR.lproj/Localizable.strings` (every literal introduced above):

```
"Overview" = "Visão geral";
"Cleanup" = "Limpeza";
"Large Files" = "Maiores arquivos";
"Memory" = "Memória";
"History" = "Histórico";
"Settings" = "Ajustes";
"Developer caches" = "Caches de desenvolvimento";
"Idle project leftovers" = "Restos de projetos parados";
"AI tools" = "Ferramentas de IA";
"App caches" = "Caches de apps";
"Logs" = "Logs";
"Forgotten installers" = "Instaladores esquecidos";
"Trash" = "Lixeira";
"Large files" = "Arquivos grandes";
"Package manager caches. They rebuild themselves when needed." = "Caches de gerenciadores de pacotes. Se regeneram sozinhos quando precisar.";
"Dependencies of projects untouched for a while. Reinstall with one command." = "Dependências de projetos parados há um tempo. Reinstala com um comando.";
"Downloaded models and runtimes. Review: they download again if you use them." = "Modelos e runtimes baixados. Revise: baixam de novo se você usar.";
"Temporary data of closed apps. They rebuild themselves." = "Dados temporários de apps fechados. Se regeneram sozinhos.";
"Old diagnostic logs." = "Registros antigos de diagnóstico.";
"Installers in Downloads older than 30 days. Go to the Trash." = "Instaladores em Downloads com mais de 30 dias. Vão para a Lixeira.";
"Emptying the Trash cannot be undone." = "Esvaziar a Lixeira não pode ser desfeito.";
"Files you picked on the Large Files screen." = "Arquivos que você escolheu na tela Maiores arquivos.";
"Safe" = "Seguro";
"Review" = "Revisar";
"Analyze everything" = "Analisar tudo";
"Open Spare" = "Abrir o Spare";
"Quit" = "Sair";
"%@ free of %@" = "%@ livres de %@";
"Reading disk..." = "Lendo o disco...";
"Free up" = "Liberar";
"Disk" = "Disco";
"%@ used of %@" = "%@ em uso de %@";
"View" = "Ver";
"Reading memory..." = "Lendo a memória...";
"Only %@ left. Analyze to free space." = "Restam só %@. Analise para liberar espaço.";
"Analyze" = "Analisar";
"You can free %@ safely." = "Você pode liberar %@ com segurança.";
"Memory is high. See what is using it." = "Memória alta. Veja o que está pesando.";
"All good here." = "Tudo certo por aqui.";
"Today's recommendation" = "Recomendação de hoje";
"Pressure: normal" = "Pressão: normal";
"Pressure: attention" = "Pressão: atenção";
"Pressure: high" = "Pressão: alta";
"Coming in the next update" = "Chega na próxima atualização";
"Analyze disk and memory in a single pass." = "Analise o disco e a memória em uma única passada.";
"Analyzing..." = "Analisando...";
"Stop" = "Parar";
"Analysis interrupted, partial results" = "Análise interrompida, resultados parciais";
"You can free %@ safely" = "Você pode liberar %@ com segurança";
"Plus %@ to review" = "Mais %@ para revisar";
"Analyze again" = "Analisar de novo";
"Review all" = "Revisar tudo";
```

Remove the now unused `"Quit Spare"` and `"Free space"` entries only if no source uses them (the check script ignores extra keys, so leaving them is harmless).

Run: `python3 scripts/check-strings.py` → `strings ok`.

- [ ] **Step 9: Manual verification**

Run: `scripts/build-app.sh && open dist/Spare.app --args --show overview`

Expected, checked by taking screenshots (`screencapture -x /tmp/spare-overview.png`, then view the image):
1. Menu bar shows the drive icon (or the warning icon when below 15 GB) and the free GB.
2. The main window opens on Overview, in Portuguese when the system language is pt-BR.
3. "Analisar tudo" runs: categories show spinners, then sizes with green checks; the current path updates; "Parar" stops with "Análise interrompida".
4. After finishing, `~/Library/Application Support/Spare/last-scan.json` exists and the panel recommendation changes to "Você pode liberar X com segurança." when above 10 GB.
5. Clicking the menu bar item shows the panel with the Disk, Memory and Recommendation cards.

Quit the app afterwards (`osascript -e 'quit app "Spare"'` or `pkill -x Spare`).

- [ ] **Step 10: Docs, gates, commit**

CHANGELOG `Added: menu bar panel, main window, Analyze everything with live progress`; STATUS. `scripts/check.sh` green. Attach the screenshots to the PR description.

```bash
git add -A
git commit -m "feat(app): add menu panel and Analyze everything

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
