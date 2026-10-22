# Task 4: Process listing and in-use detection

Lists the user's running processes once per scan and marks items that something is using right now (an MCP server running from `~/.npm/_npx`, Claude using its VM, an open app using its cache). Marked items are never selected by default and are re-checked by the cleaner in Task 5.

**Files:**
- Create: `Sources/SpareCore/Processes/RunningProcess.swift`, `Sources/SpareCore/Processes/ProcessLister.swift`, `Sources/SpareCore/Processes/InUseGuard.swift`
- Modify: `Sources/SpareCore/Support/SpareEnvironment.swift` (add `processes`), `Sources/SpareCore/Scan/Scanner.swift` (set `inUseBy`)
- Modify: `Sources/SpareTestSupport/TestEnvironment.swift` (add `processes:` parameter)
- Test: `Tests/SpareCoreTests/ProcessListerTests.swift`, `Tests/SpareCoreTests/InUseGuardTests.swift`, add a case to `ScannerTests.swift`
- Modify: `CHANGELOG.md`, `docs/planta/STATUS.md`

**Interfaces:**
- Consumes: `Rule`, `InUseHint`, `RuleKind`, `CleanAction`, `Scanner`, `ScanItem.inUseBy`.
- Produces:
  - `public struct RunningProcess: Codable, Sendable, Hashable { pid: Int32; uid: UInt32; rssBytes: Int64; executablePath: String; commandLine: String; appBundlePath: String?; appBundleID: String?; name: String }`
  - `ProcessLister.parse(comm: String, args: String) -> [RunningProcess]` (pure), `ProcessLister.live() -> [RunningProcess]`
  - `InUseGuard(processes: [RunningProcess])` with `reason(rule: Rule, url: URL) -> String?` (process display name, or nil when free)
  - `SpareEnvironment.processes: @Sendable () -> [RunningProcess]` (default `{ [] }`; `live(home:)` uses `ProcessLister.live`)
  - `SpareEnvironment.test(home:projectRoots:disk:processes:)`

- [ ] **Step 1: Write the failing parser tests**

`Tests/SpareCoreTests/ProcessListerTests.swift`:

```swift
import Testing
@testable import SpareCore

@Suite struct ProcessListerTests {
    let comm = """
      101   501  204800 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      102   501   51200 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper (Renderer)
      200   501   10240 /opt/homebrew/bin/node
      300     0    4096 /usr/sbin/syslogd
    """
    let args = """
      101   /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      102   /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
      200   node /Users/x/.npm/_npx/abc123/node_modules/.bin/mcp-server --stdio
      300   /usr/sbin/syslogd
    """

    @Test func parsesPidUidMemoryAndPaths() {
        let list = ProcessLister.parse(comm: comm, args: args)

        #expect(list.count == 4)
        let chrome = list.first { $0.pid == 101 }!
        #expect(chrome.uid == 501)
        #expect(chrome.rssBytes == 204_800 * 1024)
        #expect(chrome.executablePath == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        #expect(chrome.appBundlePath == "/Applications/Google Chrome.app")
        #expect(chrome.name == "Google Chrome")
    }

    @Test func helpersBelongToTheOutermostApp() {
        let helper = ProcessLister.parse(comm: comm, args: args).first { $0.pid == 102 }!

        #expect(helper.appBundlePath == "/Applications/Google Chrome.app")
        #expect(helper.name == "Google Chrome")
    }

    @Test func plainExecutablesUseTheirFileName() {
        let node = ProcessLister.parse(comm: comm, args: args).first { $0.pid == 200 }!

        #expect(node.name == "node")
        #expect(node.appBundlePath == nil)
        #expect(node.commandLine.contains(".npm/_npx/abc123"))
    }

    @Test func ignoresMalformedLines() {
        #expect(ProcessLister.parse(comm: "garbage\n\n  12 x y\n", args: "").isEmpty)
    }

    @Test func liveListingContainsThisProcess() {
        let list = ProcessLister.live()
        #expect(list.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
    }
}
```

(`ProcessInfo` needs `import Foundation` at the top of the file; add it.)

Run: `swift test --filter ProcessListerTests` → FAIL.

- [ ] **Step 2: Implement the process model and lister**

`Sources/SpareCore/Processes/RunningProcess.swift`:

```swift
import Foundation

public struct RunningProcess: Codable, Sendable, Hashable {
    public let pid: Int32
    public let uid: UInt32
    public let rssBytes: Int64
    public let executablePath: String
    public let commandLine: String
    /// Outermost `.app` bundle containing the executable, if any.
    public let appBundlePath: String?
    public var appBundleID: String?
    /// App name for app processes (helpers included), else the executable file name.
    public let name: String

    public init(pid: Int32, uid: UInt32, rssBytes: Int64, executablePath: String, commandLine: String,
                appBundlePath: String?, appBundleID: String?, name: String) {
        self.pid = pid
        self.uid = uid
        self.rssBytes = rssBytes
        self.executablePath = executablePath
        self.commandLine = commandLine
        self.appBundlePath = appBundlePath
        self.appBundleID = appBundleID
        self.name = name
    }

    /// Name of the script for interpreter-run tools: `node /x/bin/npm install` -> "npm".
    public var scriptName: String? {
        let tokens = commandLine.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count > 1 else { return nil }
        return (String(tokens[1]) as NSString).lastPathComponent
    }

    public var executableName: String {
        (executablePath as NSString).lastPathComponent
    }
}
```

`Sources/SpareCore/Processes/ProcessLister.swift`:

```swift
import Foundation

public enum ProcessLister {
    /// Parses `ps -axww -o pid=,uid=,rss=,comm=` and `ps -axww -o pid=,args=` output.
    public static func parse(comm: String, args: String) -> [RunningProcess] {
        var argsByPID: [Int32: String] = [:]
        for line in args.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            argsByPID[pid] = String(trimmed[space...].drop { $0 == " " })
        }

        var result: [RunningProcess] = []
        for line in comm.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]), let uid = UInt32(fields[1]), let rssKB = Int64(fields[2])
            else { continue }
            let path = String(fields[3])
            guard path.hasPrefix("/") else { continue }
            let appPath = outermostAppPath(in: path)
            let name = appPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                ?? (path as NSString).lastPathComponent
            result.append(RunningProcess(
                pid: pid, uid: uid, rssBytes: rssKB * 1024, executablePath: path,
                commandLine: argsByPID[pid] ?? path, appBundlePath: appPath, appBundleID: nil, name: name))
        }
        return result
    }

    static func outermostAppPath(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    public static func live() -> [RunningProcess] {
        let comm = run(["-axww", "-o", "pid=,uid=,rss=,comm="])
        let args = run(["-axww", "-o", "pid=,args="])
        var bundleIDs: [String: String] = [:]
        return parse(comm: comm, args: args).map { process in
            var copy = process
            if let appPath = process.appBundlePath {
                if bundleIDs[appPath] == nil {
                    bundleIDs[appPath] = Bundle(path: appPath)?.bundleIdentifier ?? ""
                }
                copy.appBundleID = bundleIDs[appPath].flatMap { $0.isEmpty ? nil : $0 }
            }
            return copy
        }
    }

    static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
```

Run: `swift test --filter ProcessListerTests` → PASS.

- [ ] **Step 3: Write the failing in-use tests**

`Tests/SpareCoreTests/InUseGuardTests.swift`:

```swift
import Foundation
import Testing
@testable import SpareCore

@Suite struct InUseGuardTests {
    func process(_ name: String, path: String, args: String? = nil, app: String? = nil, bundleID: String? = nil) -> RunningProcess {
        RunningProcess(pid: 10, uid: 501, rssBytes: 1, executablePath: path, commandLine: args ?? path,
                       appBundlePath: app, appBundleID: bundleID, name: name)
    }
    let catalog = RuleCatalog.standard

    @Test func blocksByExecutableName() {
        let guardian = InUseGuard(processes: [process("Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude",
                                                       app: "/Applications/Claude.app")])
        let rule = catalog.rule(id: "ai.claudeVM")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Library/Application Support/Claude/vm_bundles")) == "Claude")
    }

    @Test func blocksByScriptNameForInterpreterTools() {
        let guardian = InUseGuard(processes: [process("node", path: "/opt/homebrew/bin/node",
                                                       args: "node /opt/homebrew/bin/yarn install")])

        #expect(guardian.reason(rule: catalog.rule(id: "dev.yarn")!, url: URL(fileURLWithPath: "/Users/x/Library/Caches/Yarn")) == "node")
    }

    @Test func blocksWhenACommandLineUsesThePath() {
        let guardian = InUseGuard(processes: [process("node", path: "/opt/homebrew/bin/node",
                                                       args: "node /Users/x/.npm/_npx/abc123/node_modules/.bin/mcp")])
        let rule = catalog.rule(id: "dev.npx")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc123")) == "node")
        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/.npm/_npx/abc1")) == nil)
    }

    @Test func projectArtifactsCheckTheProjectFolder() {
        let guardian = InUseGuard(processes: [process("node", path: "/opt/homebrew/bin/node",
                                                       args: "node /Users/x/Projetos/app/server.js")])
        let rule = catalog.rule(id: "project.nodeModules")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Projetos/app/node_modules")) == "node")
        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Projetos/app2/node_modules")) == nil)
    }

    @Test func blocksAppCachesOfRunningApps() {
        let guardian = InUseGuard(processes: [process("Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack",
                                                       app: "/Applications/Slack.app", bundleID: "com.tinyspeck.slackmacgap")])
        let rule = catalog.rule(id: "apps.caches")!

        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Library/Caches/com.tinyspeck.slackmacgap")) == "Slack")
        #expect(guardian.reason(rule: rule, url: URL(fileURLWithPath: "/Users/x/Library/Caches/com.other.app")) == nil)
    }

    @Test func officialCommandRulesAreNeverBlocked() {
        let guardian = InUseGuard(processes: [process("uv", path: "/opt/homebrew/bin/uv", args: "uv run server.py")])

        #expect(guardian.reason(rule: catalog.rule(id: "dev.uv")!, url: URL(fileURLWithPath: "/Users/x/.cache/uv")) == nil)
    }
}
```

Run: `swift test --filter InUseGuardTests` → FAIL.

- [ ] **Step 4: Implement `InUseGuard`**

`Sources/SpareCore/Processes/InUseGuard.swift`:

```swift
import Foundation

public struct InUseGuard: Sendable {
    public let processes: [RunningProcess]

    public init(processes: [RunningProcess]) {
        self.processes = processes
    }

    /// Display name of what is using the item, or nil when it is free to clean.
    public func reason(rule: Rule, url: URL) -> String? {
        if case .command = rule.action { return nil }  // the tool handles its own locks
        let hint = rule.inUse

        if !hint.processNames.isEmpty {
            let names = Set(hint.processNames.map { $0.lowercased() })
            if let match = processes.first(where: {
                names.contains($0.executableName.lowercased()) || names.contains($0.scriptName?.lowercased() ?? "")
            }) {
                return match.name
            }
        }

        if hint.checkCommandLines {
            let target: String
            if case .projectArtifact = rule.kind {
                target = url.deletingLastPathComponent().path
            } else {
                target = url.path
            }
            if let match = processes.first(where: {
                $0.commandLine.contains(target + "/") || $0.commandLine.hasSuffix(target)
                    || $0.commandLine.contains(target + " ") || $0.executablePath.hasPrefix(target + "/")
            }) {
                return match.name
            }
        }

        if hint.checkOwningApp {
            let folder = url.lastPathComponent
            if let match = processes.first(where: { $0.appBundleID == folder }) {
                return match.name
            }
        }
        return nil
    }
}
```

Run: `swift test --filter InUseGuardTests` → PASS.

- [ ] **Step 5: Wire into the environment and scanner**

`SpareEnvironment`: add `public var processes: @Sendable () -> [RunningProcess]` with init parameter `processes: @escaping @Sendable () -> [RunningProcess] = { [] }`; in `live(home:)` pass `processes: { ProcessLister.live() }`.

`SpareEnvironment.test(...)`: add parameter `processes: [RunningProcess] = []` and pass `processes: { processes }`.

`Scanner.scan`: before the task group, `let inUse = InUseGuard(processes: environment.processes())`; in the result loop, set the flag before appending:

```swift
                if var item {
                    if let rule = catalog.rule(id: item.ruleID) {
                        item.inUseBy = inUse.reason(rule: rule, url: item.url)
                    }
                    items.append(item)
                }
```

(Adjust the following `progress(...)` call to pass the updated item.)

Add to `ScannerTests.swift`:

```swift
    @Test func marksItemsInUse() async throws {
        let home = try TempHome()
        defer { home.remove() }
        try home.file(".npm/_npx/abc/node_modules/mcp/index.js", bytes: 10_000)
        try home.file(".npm/_npx/def/node_modules/old/index.js", bytes: 10_000)
        let mcp = RunningProcess(pid: 9, uid: 501, rssBytes: 1, executablePath: "/opt/homebrew/bin/node",
                                 commandLine: "node \(home.path(".npm/_npx/abc").path)/node_modules/mcp/index.js",
                                 appBundlePath: nil, appBundleID: nil, name: "node")

        let report = await Scanner(environment: .test(home: home.url, processes: [mcp])).scan(categories: [.devCaches])
        let byName = Dictionary(uniqueKeysWithValues: report.items.map { ($0.url.lastPathComponent, $0.inUseBy) })

        #expect(byName["abc"] == .some("node"))
        #expect(byName["def"] == .some(nil))
        #expect(report.reviewBytes < 20_000)
    }
```

- [ ] **Step 6: Run, docs, gates, commit**

Run: `swift test` → PASS. Manual smoke: `swift run spare scan --category devCaches` shows `[in use: node]` next to `_npx` entries of running MCP servers.

CHANGELOG `Added: in-use detection (running processes, apps and MCP servers)`; STATUS. `scripts/check.sh` green.

```bash
git add -A
git commit -m "feat(core): flag items used by running processes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```
