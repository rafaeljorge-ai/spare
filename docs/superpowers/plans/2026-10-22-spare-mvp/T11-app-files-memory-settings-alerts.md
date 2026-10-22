# Task 11: Large Files, Memory and Settings screens, alerts and login item

Completes every screen of the spec: Large Files (T8), Memory (T9), Settings (T11), plus disk and memory notifications and "Open at login". Read `docs/planta/03-TELAS-E-FLUXOS.md` (T8, T9, T11) first.

**Files:**
- Create: `Sources/SpareCore/Insights/AlertPolicy.swift`
- Create: `Sources/SpareApp/AlertCenter.swift`, `Sources/SpareApp/LoginItem.swift`, `Sources/SpareApp/AppModel+Tools.swift`
- Create: `Sources/SpareApp/Views/LargeFilesView.swift`, `Sources/SpareApp/Views/MemoryView.swift`, `Sources/SpareApp/Views/SettingsView.swift`
- Modify: `Sources/SpareApp/AppModel.swift` (stored properties, alert evaluation in the monitor loop, `SPARE_HOME` already added in Task 10), `Sources/SpareApp/Views/MainView.swift` (no more placeholder)
- Modify: `Localization/pt-BR.lproj/Localizable.strings`
- Test: `Tests/SpareCoreTests/AlertPolicyTests.swift`
- Modify: `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `AppModel`, `LargeFileFinder`, `LargeFile`, `LargeFileCleaner`, `HistoryStore`, `MemoryMonitor.topConsumers`, `MemoryConsumer`, `ProcessTerminator`, `ProcessLister.live`, `SpareSettings`, `ProjectScanner.defaultRoots`.
- Produces:
  - Core: `AlertPolicy` with `static let diskCooldown: TimeInterval = 6 * 3600`, `static let memoryCooldown: TimeInterval = 3600`, `static func shouldAlertDisk(freeBytes:thresholdGB:lastAlert:now:) -> Bool`, `static func shouldAlertMemory(level:enabled:lastAlert:now:) -> Bool` (alerts only on `.critical`).
  - App: `AlertCenter` (`requestAuthorization()`, `evaluate(disk:memory:settings:)`), `LoginItem` (`isEnabled`, `setEnabled(_:) throws`).
  - App model additions: `largeFolder: URL`, `largeMinMB: Int`, `largeFiles: [LargeFile]`, `isSearchingLarge: Bool`, `consumers: [MemoryConsumer]`, `findLargeFiles()`, `trashLargeFile(_:)`, `refreshConsumers()`, `terminate(_:)`.

- [ ] **Step 1: Write the failing alert policy tests**

`Tests/SpareCoreTests/AlertPolicyTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore

@Suite struct AlertPolicyTests {
    let now = Date()

    @Test func diskAlertsBelowThresholdWithCooldown() {
        #expect(AlertPolicy.shouldAlertDisk(freeBytes: 9_000_000_000, thresholdGB: 15, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertDisk(freeBytes: 20_000_000_000, thresholdGB: 15, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertDisk(freeBytes: 9_000_000_000, thresholdGB: 15,
                                             lastAlert: now.addingTimeInterval(-3600), now: now))
        #expect(AlertPolicy.shouldAlertDisk(freeBytes: 9_000_000_000, thresholdGB: 15,
                                            lastAlert: now.addingTimeInterval(-7 * 3600), now: now))
    }

    @Test func memoryAlertsOnlyWhenCriticalEnabledAndCooledDown() {
        #expect(AlertPolicy.shouldAlertMemory(level: .critical, enabled: true, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertMemory(level: .warning, enabled: true, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertMemory(level: .critical, enabled: false, lastAlert: nil, now: now))
        #expect(!AlertPolicy.shouldAlertMemory(level: .critical, enabled: true,
                                               lastAlert: now.addingTimeInterval(-60), now: now))
    }
}
```

Run: `swift test --filter AlertPolicyTests` → FAIL.

- [ ] **Step 2: Implement `AlertPolicy`**

`Sources/SpareCore/Insights/AlertPolicy.swift`:

```swift
import Foundation

public enum AlertPolicy {
    public static let diskCooldown: TimeInterval = 6 * 3600
    public static let memoryCooldown: TimeInterval = 3600

    public static func shouldAlertDisk(freeBytes: Int64, thresholdGB: Int, lastAlert: Date?, now: Date) -> Bool {
        guard freeBytes < Int64(thresholdGB) * 1_000_000_000 else { return false }
        guard let lastAlert else { return true }
        return now.timeIntervalSince(lastAlert) >= diskCooldown
    }

    public static func shouldAlertMemory(level: MemoryPressureLevel, enabled: Bool, lastAlert: Date?, now: Date) -> Bool {
        guard enabled, level == .critical else { return false }
        guard let lastAlert else { return true }
        return now.timeIntervalSince(lastAlert) >= memoryCooldown
    }
}
```

Run: `swift test --filter AlertPolicyTests` → PASS.

- [ ] **Step 3: Alerts and login item**

`Sources/SpareApp/AlertCenter.swift`:

```swift
import Foundation
import SpareCore
import UserNotifications

/// Local notifications. Disabled when not running from a bundle (swift run), where
/// UNUserNotificationCenter would crash.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    private var lastDiskAlert: Date?
    private var lastMemoryAlert: Date?
    var onOpen: (() -> Void)?

    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(disk: DiskSpace?, memory: MemorySnapshot?, settings: SpareSettings) {
        guard isAvailable else { return }
        let now = Date()
        if let disk, AlertPolicy.shouldAlertDisk(freeBytes: disk.freeBytes, thresholdGB: settings.diskAlertThresholdGB,
                                                 lastAlert: lastDiskAlert, now: now) {
            lastDiskAlert = now
            post(id: "disk",
                 title: String(localized: "Your Mac is running out of space"),
                 body: String(localized: "Only \(ByteFormat.string(disk.freeBytes)) left. Open Spare to free space."))
        }
        if let memory, AlertPolicy.shouldAlertMemory(level: memory.level, enabled: settings.memoryAlertsEnabled,
                                                     lastAlert: lastMemoryAlert, now: now) {
            lastMemoryAlert = now
            post(id: "memory",
                 title: String(localized: "Memory is under pressure"),
                 body: String(localized: "Open Spare to see what is using it."))
        }
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in self.onOpen?() }
        completionHandler()
    }
}
```

`check-strings.py` must also catch `String(localized:`: add `String\(localized:` handling by extending `CALLS` with `|String\(localized:` is not a call-name form; instead add a second pattern in the script:

```python
LOCALIZED_STRING = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')
```

and run it over the same files, feeding matches into the same key set.

`Sources/SpareApp/LoginItem.swift`:

```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

In `AppModel`: add `@ObservationIgnored let alerts = AlertCenter()`; in `init` call `alerts.onOpen = { [weak self] in self?.show(.overview) }` and `alerts.requestAuthorization()`; in the monitoring loop after refreshing, call `alerts.evaluate(disk: disk, memory: memory, settings: settings)` (also once right after `init` refreshes).

- [ ] **Step 4: Tools on the app model**

Stored properties in `AppModel`:

```swift
    var largeFolder: URL
    var largeMinMB = 500
    var largeFiles: [LargeFile] = []
    var isSearchingLarge = false
    var consumers: [MemoryConsumer] = []
    @ObservationIgnored var largeTask: Task<Void, Never>?
```

(`largeFolder = self.home` in `init`.)

`Sources/SpareApp/AppModel+Tools.swift`:

```swift
import AppKit
import SpareCore

extension AppModel {
    func findLargeFiles() {
        largeTask?.cancel()
        isSearchingLarge = true
        let folder = largeFolder
        let minBytes = Int64(largeMinMB) * 1_000_000
        largeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let files = LargeFileFinder.find(in: folder, minBytes: minBytes)
            await MainActor.run { [weak self] in
                self?.largeFiles = files
                self?.isSearchingLarge = false
            }
        }
    }

    func trashLargeFile(_ file: LargeFile) {
        let record = LargeFileCleaner(environment: environment).trash([file])
        try? historyStore.append(record)
        if record.entries.first?.status == .done {
            largeFiles.removeAll { $0.id == file.id }
        }
        reloadHistory()
        refreshDisk()
    }

    func refreshConsumers() {
        let processes = ProcessLister.live()
        consumers = MemoryMonitor.topConsumers(processes: processes, currentUID: getuid(),
                                               ownPID: ProcessInfo.processInfo.processIdentifier)
        refreshMemory()
    }

    func terminate(_ consumer: MemoryConsumer) {
        if consumer.isApp, let bundleID = consumer.appBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.terminate()
        } else {
            ProcessTerminator.terminate(consumer, processes: ProcessLister.live(), currentUID: getuid(),
                                        ownPID: ProcessInfo.processInfo.processIdentifier)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.refreshConsumers()
        }
    }
}
```

- [ ] **Step 5: Screens**

`Sources/SpareApp/Views/LargeFilesView.swift`:

```swift
import AppKit
import SpareCore
import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingTrash: LargeFile?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    chooseFolder()
                } label: {
                    Label(model.largeFolder.lastPathComponent, systemImage: "folder")
                }
                Stepper(value: $model.largeMinMB, in: 100...100_000, step: 100) {
                    Text("Bigger than \(String(model.largeMinMB)) MB")
                        .monospacedDigit()
                }
                Spacer()
                Button("Search") { model.findLargeFiles() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSearchingLarge)
            }
            if model.isSearchingLarge {
                ProgressView().frame(maxWidth: .infinity)
            }
            List(model.largeFiles) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: file.url.lastPathComponent)
                        Text(verbatim: file.url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if let opened = file.lastOpened {
                        Text(verbatim: opened.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: ByteFormat.string(file.sizeBytes))
                        .monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    Button {
                        pendingTrash = file
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Move to Trash")
                }
            }
        }
        .padding(24)
        .navigationTitle("Large Files")
        .confirmationDialog("Move this file to the Trash?", isPresented: Binding(
            get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }
        ), presenting: pendingTrash) { file in
            Button("Move to Trash", role: .destructive) { model.trashLargeFile(file) }
        } message: { file in
            Text(verbatim: file.url.path)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.largeFolder
        if panel.runModal() == .OK, let url = panel.url {
            model.largeFolder = url
        }
    }
}
```

`Sources/SpareApp/Views/MemoryView.swift`:

```swift
import SpareCore
import SwiftUI

struct MemoryView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingTerminate: MemoryConsumer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let memory = model.memory {
                HStack(alignment: .firstTextBaseline) {
                    Text(memory.level.title)
                        .font(.title2.bold())
                        .foregroundStyle(memory.level.color)
                    Spacer()
                    Text("\(ByteFormat.string(memory.usedBytes)) used of \(ByteFormat.string(memory.totalBytes))")
                        .monospacedDigit()
                }
                ProgressView(value: memory.usedFraction)
            }
            Text("Approximate: memory shared between processes is counted for each one.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List(model.consumers) { consumer in
                HStack {
                    Image(systemName: consumer.isApp ? "app" : "terminal")
                    Text(verbatim: consumer.name)
                    if consumer.pids.count > 1 {
                        Text("\(String(consumer.pids.count)) processes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: ByteFormat.string(consumer.bytes))
                        .monospacedDigit()
                    Button("Quit") { pendingTerminate = consumer }
                }
            }
        }
        .padding(24)
        .navigationTitle("Memory")
        .task {
            while !Task.isCancelled {
                model.refreshConsumers()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .confirmationDialog("Quit this app?", isPresented: Binding(
            get: { pendingTerminate != nil }, set: { if !$0 { pendingTerminate = nil } }
        ), presenting: pendingTerminate) { consumer in
            Button("Quit", role: .destructive) { model.terminate(consumer) }
        } message: { consumer in
            Text("\(consumer.name) will be asked to quit. Unsaved work may be lost.")
        }
    }
}
```

`Sources/SpareApp/Views/SettingsView.swift`:

```swift
import AppKit
import SpareCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Alerts") {
                Stepper(value: $model.settings.diskAlertThresholdGB, in: 5...200) {
                    Text("Warn when free space is below \(String(model.settings.diskAlertThresholdGB)) GB")
                }
                Toggle("Warn when memory is under pressure", isOn: $model.settings.memoryAlertsEnabled)
            }
            Section("Projects") {
                ForEach(model.settings.projectRootPaths, id: \.self) { path in
                    HStack {
                        Text(verbatim: path)
                        Spacer()
                        Button {
                            model.settings.projectRootPaths.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add folder") { addFolder() }
                Stepper(value: $model.settings.projectIdleDays, in: 7...365, step: 7) {
                    Text("A project is idle after \(String(model.settings.projectIdleDays)) days without changes")
                }
            }
            Section("General") {
                Toggle("Open Spare at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            openAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(verbatim: loginError).font(.caption).foregroundStyle(.red)
                }
                Button("Clear history") {
                    try? model.historyStore.clear()
                    model.reloadHistory()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url,
           !model.settings.projectRootPaths.contains(url.path) {
            model.settings.projectRootPaths.append(url.path)
        }
    }
}
```

`MainView` detail switch (final, no placeholder):

```swift
            switch model.selection ?? .overview {
            case .overview: OverviewView()
            case .cleanup: CleanupView()
            case .largeFiles: LargeFilesView()
            case .memory: MemoryView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
```

Remove the `"Coming in the next update"` key from the strings file.

- [ ] **Step 6: Translations**

Run `python3 scripts/check-strings.py` and translate every missing key. Expected new keys (complete list for this task):

```
"Your Mac is running out of space" = "Seu Mac está ficando sem espaço";
"Only %@ left. Open Spare to free space." = "Restam só %@. Abra o Spare para liberar espaço.";
"Memory is under pressure" = "A memória está sob pressão";
"Open Spare to see what is using it." = "Abra o Spare para ver o que está pesando.";
"Bigger than %@ MB" = "Maior que %@ MB";
"Search" = "Procurar";
"Move to Trash" = "Mover para a Lixeira";
"Move this file to the Trash?" = "Mover este arquivo para a Lixeira?";
"Approximate: memory shared between processes is counted for each one." = "Aproximado: memória compartilhada entre processos é contada para cada um.";
"%@ processes" = "%@ processos";
"Quit this app?" = "Encerrar este app?";
"%@ will be asked to quit. Unsaved work may be lost." = "%@ será encerrado. Trabalho não salvo pode ser perdido.";
"Alerts" = "Alertas";
"Warn when free space is below %@ GB" = "Avisar quando o espaço livre ficar abaixo de %@ GB";
"Warn when memory is under pressure" = "Avisar quando a memória estiver sob pressão";
"Projects" = "Projetos";
"Add folder" = "Adicionar pasta";
"A project is idle after %@ days without changes" = "Um projeto fica parado após %@ dias sem alterações";
"General" = "Geral";
"Open Spare at login" = "Abrir o Spare ao iniciar sessão";
"Clear history" = "Limpar histórico";
```

- [ ] **Step 7: Manual verification**

`scripts/build-app.sh`, then for each of `largeFiles`, `memory`, `settings`: `open dist/Spare.app --args --show <section>` and screenshot. Check:
1. Large Files: search on the home with 1000 MB finds the biggest files (for example the Claude VM image); Show in Finder works; Move to Trash on a throwaway file created for the test (`mkfile 600m ~/Downloads/spare-test.bin`) moves it and History shows an entry with Undo.
2. Memory: list refreshes every 5 s; Quit on a throwaway app (`open -a TextEdit`) closes it after confirmation.
3. Settings: changes persist in `~/Library/Application Support/Spare/settings.json`; the open-at-login toggle either works or shows the error text (record which in the PR).
4. Notification: temporarily set the threshold above the current free space (Settings), wait for the next monitor tick or relaunch, and confirm the notification; set it back.

- [ ] **Step 8: Docs, gates, commit**

CHANGELOG `Added: Large Files, Memory and Settings screens; disk and memory notifications; open at login`; STATUS. `scripts/check.sh` green; screenshots in the PR.

```bash
git add -A
git commit -m "feat(app): add files, memory, settings and alerts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
