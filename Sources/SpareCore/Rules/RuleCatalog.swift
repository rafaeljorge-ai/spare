import Foundation

public struct RuleCatalog: Sendable {
    public let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public func rule(id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    /// The closed list of everything Spare is allowed to clean.
    public static let standard = RuleCatalog(rules: [
        // Developer caches
        Rule(id: "dev.npm", category: .devCaches, kind: .path(".npm/_cacache"), safety: .safe,
             action: .command(executable: "npm", arguments: ["cache", "clean", "--force"])),
        Rule(id: "dev.npx", category: .devCaches,
             kind: .children(parent: ".npm/_npx", excludingPrefixes: [], extensions: nil, minAgeDays: nil),
             safety: .review, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "dev.pnpm", category: .devCaches, kind: .path("Library/pnpm/store"), safety: .safe,
             action: .command(executable: "pnpm", arguments: ["store", "prune"])),
        Rule(id: "dev.yarn", category: .devCaches, kind: .path("Library/Caches/Yarn"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["yarn"])),
        Rule(id: "dev.uv", category: .devCaches, kind: .path(".cache/uv"), safety: .safe,
             action: .command(executable: "uv", arguments: ["cache", "clean"])),
        Rule(id: "dev.pip", category: .devCaches, kind: .path("Library/Caches/pip"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["pip", "pip3"])),
        Rule(id: "dev.cargo", category: .devCaches, kind: .path(".cargo/registry/cache"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["cargo"])),
        Rule(id: "dev.homebrew", category: .devCaches, kind: .path("Library/Caches/Homebrew"), safety: .safe,
             action: .command(executable: "brew", arguments: ["cleanup", "--prune=all"])),
        Rule(id: "dev.xcodeDerivedData", category: .devCaches,
             kind: .path("Library/Developer/Xcode/DerivedData"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["Xcode", "xcodebuild"])),
        Rule(id: "dev.preCommit", category: .devCaches, kind: .path(".cache/pre-commit"), safety: .safe,
             action: .delete, inUse: InUseHint(processNames: ["pre-commit"])),
        Rule(id: "dev.playwright", category: .devCaches, kind: .path("Library/Caches/ms-playwright"),
             safety: .review, action: .delete, inUse: InUseHint(checkCommandLines: true)),

        // AI tools
        Rule(id: "ai.huggingface", category: .aiTools, kind: .path(".cache/huggingface"), safety: .review,
             action: .trash, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "ai.whisper", category: .aiTools, kind: .path(".cache/whisper"), safety: .review,
             action: .trash, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "ai.ollama", category: .aiTools, kind: .path(".ollama/models"), safety: .review,
             action: .trash, inUse: InUseHint(processNames: ["ollama", "Ollama"])),
        Rule(id: "ai.lmstudio", category: .aiTools, kind: .path(".lmstudio/models"), safety: .review,
             action: .trash, inUse: InUseHint(processNames: ["LM Studio", "lms"])),
        Rule(id: "ai.codexRuntimes", category: .aiTools,
             kind: .children(parent: ".cache/codex-runtimes", excludingPrefixes: [], extensions: nil, minAgeDays: nil),
             safety: .review, action: .trash, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "ai.claudeVM", category: .aiTools,
             kind: .path("Library/Application Support/Claude/vm_bundles"), safety: .review,
             action: .trash, inUse: InUseHint(processNames: ["Claude"])),

        // Project leftovers (found by ProjectScanner in Task 3)
        Rule(id: "project.nodeModules", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: "node_modules", manifests: ["package.json"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "project.venv", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: ".venv",
                                    manifests: ["pyproject.toml", "requirements.txt", "setup.py"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "project.next", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: ".next", manifests: ["package.json"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),
        Rule(id: "project.rustTarget", category: .projectLeftovers,
             kind: .projectArtifact(directoryName: "target", manifests: ["Cargo.toml"]),
             safety: .safe, action: .delete, inUse: InUseHint(checkCommandLines: true)),

        // Common junk
        Rule(id: "apps.caches", category: .appCaches,
             kind: .children(parent: "Library/Caches", excludingPrefixes: ["com.apple."], extensions: nil, minAgeDays: nil),
             safety: .safe, action: .delete, inUse: InUseHint(checkOwningApp: true)),
        Rule(id: "apps.logs", category: .logs,
             kind: .children(parent: "Library/Logs", excludingPrefixes: [], extensions: nil, minAgeDays: nil),
             safety: .safe, action: .delete),
        Rule(id: "downloads.installers", category: .installers,
             kind: .children(parent: "Downloads", excludingPrefixes: [], extensions: ["dmg", "pkg", "iso", "xip"], minAgeDays: 30),
             safety: .safe, action: .trash),
        Rule(id: "system.trash", category: .trash, kind: .path(".Trash"), safety: .review, action: .emptyTrash),
    ])
}
