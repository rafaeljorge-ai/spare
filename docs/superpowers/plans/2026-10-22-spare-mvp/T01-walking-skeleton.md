# Task 1: Walking skeleton

Ponta a ponta mínima: o motor lê o espaço livre, a CLI mostra, o app de barra de menus mostra, o bundle `.app` monta e assina, os gates e o CI rodam, e o repositório já nasce documentado.

**Files:**
- Create: `Package.swift`, `VERSION`, `.gitignore`, `LICENSE`, `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`
- Create: `Packaging/Info.plist`, `Localization/en.lproj/Localizable.strings`, `Localization/pt-BR.lproj/Localizable.strings`
- Create: `scripts/check.sh`, `scripts/build-app.sh`, `scripts/check-strings.py`, `.github/workflows/ci.yml`
- Create: `Sources/SpareCore/Support/SpareEnvironment.swift`, `Sources/SpareCore/Support/ByteFormat.swift`, `Sources/SpareCore/Disk/DiskMonitor.swift`
- Create: `Sources/SpareCLI/SpareCLI.swift`, `Sources/spare/main.swift`
- Create: `Sources/SpareApp/SpareApp.swift`
- Create: `Sources/SpareTestSupport/TempHome.swift`, `Sources/SpareTestSupport/OutputCapture.swift`, `Sources/SpareTestSupport/TestEnvironment.swift`
- Test: `Tests/SpareCoreTests/DiskMonitorTests.swift`, `Tests/SpareCoreTests/ByteFormatTests.swift`, `Tests/SpareCLITests/StatusCommandTests.swift`
- Modify: `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct DiskSpace: Codable, Sendable, Equatable { freeBytes: Int64; totalBytes: Int64; usedFraction: Double }`
  - `public enum DiskMonitor { static func space(at: URL) -> DiskSpace? }`
  - `public enum ByteFormat { static func string(_: Int64) -> String; static func gigabytes(_: Int64) -> Int }`
  - `public struct SpareEnvironment: Sendable { home: URL; projectRoots: [URL]; projectIdleDays: Int; now: @Sendable () -> Date; diskSpace: @Sendable (URL) -> DiskSpace?; static func live(home: URL) -> SpareEnvironment }` with a memberwise-style `init` whose every parameter except `home` has a default. Later tasks add properties, always with defaults, and extend `live(home:)`.
  - `public struct SpareCLI: Sendable { init(environment:write:); func run(_ arguments: [String]) async -> Int32 }`
  - Test support: `TempHome`, `OutputCapture`, `SpareEnvironment.test(home:)`.

- [ ] **Step 1: Create the package manifest and support files**

`Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Spare",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spare", targets: ["spare"]),
        .executable(name: "SpareApp", targets: ["SpareApp"]),
    ],
    targets: [
        .target(name: "SpareCore"),
        .target(name: "SpareCLI", dependencies: ["SpareCore"]),
        .executableTarget(name: "spare", dependencies: ["SpareCLI", "SpareCore"]),
        .executableTarget(name: "SpareApp", dependencies: ["SpareCore"]),
        .target(name: "SpareTestSupport", dependencies: ["SpareCore"]),
        .testTarget(name: "SpareCoreTests", dependencies: ["SpareCore", "SpareTestSupport"]),
        .testTarget(name: "SpareCLITests", dependencies: ["SpareCLI", "SpareCore", "SpareTestSupport"]),
    ]
)
```

`VERSION`:

```
0.1.0
```

`.gitignore`:

```
.build/
dist/
.swiftpm/
*.xcodeproj
xcuserdata/
.DS_Store
```

`LICENSE`: standard MIT text, `Copyright (c) 2026 Rafael Jorge`.

- [ ] **Step 2: Write the test support helpers**

`Sources/SpareTestSupport/TempHome.swift`:

```swift
import Foundation

/// A throwaway home folder under the system temp dir. Paths are symlink-resolved
/// (`/var` becomes `/private/var`) so comparisons with resolved paths match.
public struct TempHome: Sendable {
    public let url: URL

    public init() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        url = base.appendingPathComponent("spare-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func path(_ relativePath: String) -> URL {
        url.appendingPathComponent(relativePath)
    }

    @discardableResult
    public func file(_ relativePath: String, bytes: Int = 4096, modified: Date? = nil) throws -> URL {
        let file = path(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: file)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        return file
    }

    @discardableResult
    public func directory(_ relativePath: String, modified: Date? = nil) throws -> URL {
        let dir = path(relativePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: dir.path)
        }
        return dir
    }

    public func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relativePath).path)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

public func daysAgo(_ days: Double) -> Date {
    Date().addingTimeInterval(-days * 86_400)
}
```

`Sources/SpareTestSupport/OutputCapture.swift`:

```swift
import Foundation

/// Collects CLI output lines in tests.
public final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    public init() {}

    public var write: @Sendable (String) -> Void {
        { [self] line in
            lock.lock()
            lines.append(line)
            lock.unlock()
        }
    }

    public var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
```

`Sources/SpareTestSupport/TestEnvironment.swift`:

```swift
import Foundation
import SpareCore

extension SpareEnvironment {
    /// Environment for tests: fake home, fixed disk numbers, no real side effects.
    /// Later tasks extend this with fake trash, command runner and processes.
    public static func test(
        home: URL,
        projectRoots: [URL] = [],
        disk: DiskSpace? = DiskSpace(freeBytes: 10_000_000_000, totalBytes: 100_000_000_000)
    ) -> SpareEnvironment {
        SpareEnvironment(
            home: home,
            projectRoots: projectRoots,
            diskSpace: { _ in disk }
        )
    }
}
```

- [ ] **Step 3: Write the failing tests**

`Tests/SpareCoreTests/DiskMonitorTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore
import SpareTestSupport

@Suite struct DiskMonitorTests {
    @Test func readsFreeAndTotalSpaceOfTheVolume() throws {
        let home = try TempHome()
        defer { home.remove() }

        let space = try #require(DiskMonitor.space(at: home.url))

        #expect(space.totalBytes > 0)
        #expect(space.freeBytes > 0)
        #expect(space.freeBytes <= space.totalBytes)
        #expect(space.usedFraction >= 0 && space.usedFraction <= 1)
    }

    @Test func returnsNilForMissingPath() {
        #expect(DiskMonitor.space(at: URL(fileURLWithPath: "/definitely/not/here")) == nil)
    }
}
```

`Tests/SpareCoreTests/ByteFormatTests.swift`:

```swift
import Testing
@testable import SpareCore

@Suite struct ByteFormatTests {
    @Test func roundsToWholeDecimalGigabytes() {
        #expect(ByteFormat.gigabytes(15_400_000_000) == 15)
        #expect(ByteFormat.gigabytes(15_600_000_000) == 16)
        #expect(ByteFormat.gigabytes(0) == 0)
    }

    @Test func formatsHumanReadableSizes() {
        #expect(ByteFormat.string(0).isEmpty == false)
        #expect(ByteFormat.string(1_500_000_000).contains("1"))
    }
}
```

`Tests/SpareCLITests/StatusCommandTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCLI
import SpareCore
import SpareTestSupport

@Suite struct StatusCommandTests {
    @Test func statusJSONReportsDiskSpace() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url), write: output.write)

        let code = await cli.run(["status", "--json"])

        #expect(code == 0)
        struct Status: Decodable { let disk: DiskSpace }
        let status = try JSONDecoder().decode(Status.self, from: Data(output.text.utf8))
        #expect(status.disk.freeBytes == 10_000_000_000)
        #expect(status.disk.totalBytes == 100_000_000_000)
    }

    @Test func statusTextIsHumanReadable() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url), write: output.write)

        let code = await cli.run(["status"])

        #expect(code == 0)
        #expect(output.text.contains("Free:"))
    }

    @Test func unknownCommandFailsWithUsage() async throws {
        let home = try TempHome()
        defer { home.remove() }
        let output = OutputCapture()
        let cli = SpareCLI(environment: .test(home: home.url), write: output.write)

        let code = await cli.run(["explode"])

        #expect(code == 64)
        #expect(output.text.contains("USAGE"))
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `swift test`
Expected: build FAILS (types `DiskMonitor`, `SpareEnvironment`, `SpareCLI` not found).

- [ ] **Step 5: Implement the engine pieces**

`Sources/SpareCore/Disk/DiskMonitor.swift`:

```swift
import Foundation

public struct DiskSpace: Codable, Sendable, Equatable {
    public let freeBytes: Int64
    public let totalBytes: Int64

    public init(freeBytes: Int64, totalBytes: Int64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - freeBytes) / Double(totalBytes)
    }
}

public enum DiskMonitor {
    /// Free space as the system reports it for "important" usage (what Finder shows).
    public static func space(at url: URL) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity
        else { return nil }
        return DiskSpace(freeBytes: free, totalBytes: Int64(total))
    }
}
```

`Sources/SpareCore/Support/ByteFormat.swift`:

```swift
import Foundation

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func gigabytes(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_000_000_000).rounded())
    }
}
```

`Sources/SpareCore/Support/SpareEnvironment.swift`:

```swift
import Foundation

/// Everything the engine needs from the outside world. Tests replace each piece.
public struct SpareEnvironment: Sendable {
    public var home: URL
    public var projectRoots: [URL]
    public var projectIdleDays: Int
    public var now: @Sendable () -> Date
    public var diskSpace: @Sendable (URL) -> DiskSpace?

    public init(
        home: URL,
        projectRoots: [URL] = [],
        projectIdleDays: Int = 30,
        now: @escaping @Sendable () -> Date = { Date() },
        diskSpace: @escaping @Sendable (URL) -> DiskSpace? = { DiskMonitor.space(at: $0) }
    ) {
        self.home = home
        self.projectRoots = projectRoots
        self.projectIdleDays = projectIdleDays
        self.now = now
        self.diskSpace = diskSpace
    }

    /// Real environment for the CLI and the app.
    public static func live(home: URL) -> SpareEnvironment {
        SpareEnvironment(home: home.resolvingSymlinksInPath())
    }
}
```

- [ ] **Step 6: Implement the CLI**

`Sources/SpareCLI/SpareCLI.swift`:

```swift
import Foundation
import SpareCore

public struct SpareCLI: Sendable {
    public let environment: SpareEnvironment
    let write: @Sendable (String) -> Void

    public init(environment: SpareEnvironment, write: @escaping @Sendable (String) -> Void) {
        self.environment = environment
        self.write = write
    }

    public static let usage = """
        spare: keep your Mac's disk and memory in check

        USAGE:
          spare status [--json]      Free disk space
          spare help                 Show this help
        """

    public func run(_ arguments: [String]) async -> Int32 {
        var args = arguments
        let json = args.contains("--json")
        args.removeAll { $0 == "--json" }
        guard let command = args.first else {
            write(Self.usage)
            return 0
        }
        switch command {
        case "status":
            return status(json: json)
        case "help", "--help", "-h":
            write(Self.usage)
            return 0
        default:
            write("Unknown command: \(command)\n\n\(Self.usage)")
            return 64
        }
    }

    func status(json: Bool) -> Int32 {
        guard let disk = environment.diskSpace(environment.home) else {
            write("Could not read disk space")
            return 1
        }
        if json {
            write(Self.encode(StatusOutput(disk: disk)))
        } else {
            write("Free: \(ByteFormat.string(disk.freeBytes)) of \(ByteFormat.string(disk.totalBytes))")
        }
        return 0
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct StatusOutput: Codable {
    let disk: DiskSpace
}
```

`Sources/spare/main.swift`:

```swift
import Foundation
import SpareCLI
import SpareCore

let variables = ProcessInfo.processInfo.environment
let home = variables["SPARE_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser
let cli = SpareCLI(environment: .live(home: home), write: { print($0) })
let code = await cli.run(Array(CommandLine.arguments.dropFirst()))
exit(code)
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests in `DiskMonitorTests`, `ByteFormatTests`, `StatusCommandTests` PASS.

Then: `swift run spare status` prints `Free: … of …` for the real disk.

- [ ] **Step 8: Minimal menu bar app**

`Sources/SpareApp/SpareApp.swift`:

```swift
import AppKit
import SpareCore
import SwiftUI

@main
struct SpareApp: App {
    @State private var freeTitle = SpareApp.currentTitle()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Free space")
                    .font(.headline)
                Text(verbatim: freeTitle)
                    .font(.title2.monospacedDigit())
                Divider()
                Button("Quit Spare") { NSApp.terminate(nil) }
            }
            .padding(16)
            .frame(width: 240)
            .onAppear { freeTitle = SpareApp.currentTitle() }
        } label: {
            Label(freeTitle, systemImage: "internaldrive")
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }

    static func currentTitle() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let space = DiskMonitor.space(at: home) else { return "Spare" }
        return "\(ByteFormat.gigabytes(space.freeBytes)) GB"
    }
}
```

Note: `Label(freeTitle, …)` with a `String` variable is not localized (correct: it is a number).

- [ ] **Step 9: Localization files and the strings gate**

`Localization/en.lproj/Localizable.strings`:

```
/* English is the development language: keys are the English text. */
```

`Localization/pt-BR.lproj/Localizable.strings`:

```
"Free space" = "Espaço livre";
"Quit Spare" = "Sair do Spare";
```

`scripts/check-strings.py` (make executable):

```python
#!/usr/bin/env python3
"""Fail if a UI string literal in Sources/SpareApp has no pt-BR translation."""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CALLS = (
    r"(?:Text|Button|Label|Toggle|Section|ContentUnavailableView|LocalizedStringKey|"
    r"navigationTitle|help|confirmationDialog|Stepper|Picker|TextField|GroupBox|LabeledContent)"
)
PATTERN = re.compile(CALLS + r'\(\s*"((?:[^"\\]|\\.)*)"')
INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")


def source_keys():
    keys = set()
    for source in (ROOT / "Sources/SpareApp").rglob("*.swift"):
        for match in PATTERN.finditer(source.read_text(encoding="utf-8")):
            key = INTERPOLATION.sub("%@", match.group(1)).replace('\\"', '"')
            if key.strip():
                keys.add(key)
    return keys


def translations():
    path = ROOT / "Localization/pt-BR.lproj/Localizable.strings"
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def main():
    keys = source_keys()
    missing = sorted(keys - set(translations()))
    if missing:
        print("Missing pt-BR translations:")
        for key in missing:
            print(f"  {key!r}")
        sys.exit(1)
    print(f"strings ok ({len(keys)} keys)")


main()
```

Run: `python3 scripts/check-strings.py`
Expected: `strings ok (2 keys)`.

- [ ] **Step 10: App bundle script and Info.plist**

`Packaging/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Spare</string>
    <key>CFBundleIdentifier</key><string>ai.rafaeljorge.spare</string>
    <key>CFBundleName</key><string>Spare</string>
    <key>CFBundleDisplayName</key><string>Spare</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key><string>__VERSION__</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
```

`scripts/build-app.sh` (make executable):

```bash
#!/usr/bin/env bash
# Builds dist/Spare.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
APP=dist/Spare.app

swift build -c release --product SpareApp
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SpareApp" "$APP/Contents/MacOS/Spare"
sed "s/__VERSION__/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"
cp -R Localization/*.lproj "$APP/Contents/Resources/"

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "$APP"
```

Run: `scripts/build-app.sh && open dist/Spare.app`
Expected: the menu bar shows a drive icon with `NN GB`; clicking it shows "Espaço livre" (system in pt-BR) and the quit button works. Quit it afterwards.

- [ ] **Step 11: Gate script and CI**

`scripts/check.sh` (make executable):

```bash
#!/usr/bin/env bash
# Official local gate. Every PR must pass this.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build"
swift build
echo "==> swift test"
swift test
echo "==> localized strings"
python3 scripts/check-strings.py
echo "==> app bundle"
scripts/build-app.sh > /dev/null
echo "OK: all gates passed"
```

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
jobs:
  check:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Swift version
        run: swift --version
      - name: Gates
        run: scripts/check.sh
```

Run: `scripts/check.sh`
Expected: ends with `OK: all gates passed`.

- [ ] **Step 12: Repository documentation**

`README.md` (bilingual, English first, then `## Português`). Required sections, real content, no placeholders:
1. One-line pitch: "Spare keeps your Mac's disk and memory in check, with a focus on developer and AI junk. Free, open source, menu bar app plus CLI."
2. Status: "v0.1.0 in development" and a link to `docs/planta/STATUS.md`.
3. Why: the evidence paragraph from `docs/planta/01-PRD.md` (Problema).
4. Features (MVP list F1 to F13 in plain words).
5. Safety: the 8 invariants from `docs/planta/02-TRD.md` summarized in plain language.
6. Build from source: `swift build`, `swift test`, `scripts/check.sh`, `scripts/build-app.sh`.
7. CLI usage block (currently `spare status`), updated by later tasks.
8. Project docs: links to every file in `docs/planta/` and the plan index.
9. License: MIT.
10. `## Português`: same content in pt-BR.

`CONTRIBUTING.md`: how to run gates, branch and PR rite (from `docs/planta/05-OPERACAO-E-RELEASE.md`), commit convention, the localization rule from Global Constraints, and "add a cleanup rule = add a `Rule` to `RuleCatalog.standard` plus a test with a fake home".

`SECURITY.md`: what Spare can delete, the invariants, and how to report a vulnerability privately via GitHub Security Advisories on `rafaeljorge-ai/spare`.

`CHANGELOG.md`:

```markdown
# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog. Versioning: SemVer.

## [Unreleased]

### Added
- Walking skeleton: disk monitor, `spare status`, menu bar app showing free space, local gates and CI.
```

Update `docs/planta/STATUS.md`: Etapa 4 em andamento, Task 1 concluída, próximo: Task 2.

- [ ] **Step 13: Gates and commit**

Run: `scripts/check.sh` (green), then:

```bash
git add -A
git commit -m "feat(core): add walking skeleton with disk status

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
