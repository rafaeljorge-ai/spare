import SwiftUI

enum Route: Hashable {
    case overview, cleanup, review(String), result, largeFiles, memory, history, settings
}

enum Safety { case safe, review }

struct Item: Identifiable {
    let id: String
    let name: String
    let path: String
    let gb: Double
    let age: String
    var inUseBy: String? = nil
}

struct Category: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let symbol: String
    let tint: Color
    let safety: Safety
    let items: [Item]

    var gb: Double { items.reduce(0) { $0 + $1.gb } }
}

enum ScanPhase { case idle, scanning, done }

@MainActor
final class ProtoModel: ObservableObject {
    @Published var route: Route = .overview
    @Published var phase: ScanPhase = .idle
    @Published var progress: Double = 0
    @Published var scanned: Set<String> = []
    @Published var currentPath = ""
    @Published var selected: Set<String> = []
    @Published var confirming = false
    @Published var freeGB = 15.4
    @Published var lastFreedGB = 0.0
    @Published var lastTrashedGB = 0.0

    let totalGB = 245.1
    let categories = Mock.categories
    private var scanTask: Task<Void, Never>?

    var safeGB: Double { categories.filter { $0.safety == .safe }.flatMap(\.items).filter { $0.inUseBy == nil }.reduce(0) { $0 + $1.gb } }
    var reviewGB: Double { categories.filter { $0.safety == .review }.reduce(0) { $0 + $1.gb } }
    var selectedGB: Double { allItems.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.gb } }
    var allItems: [Item] { categories.flatMap(\.items) }

    func category(_ id: String) -> Category? { categories.first { $0.id == id } }

    func startScan() {
        phase = .scanning
        progress = 0
        scanned = []
        scanTask = Task {
            for (index, category) in categories.enumerated() {
                for item in category.items {
                    currentPath = item.path
                    try? await Task.sleep(for: .milliseconds(140))
                    if Task.isCancelled { return }
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    scanned.insert(category.id)
                    progress = Double(index + 1) / Double(categories.count)
                }
            }
            withAnimation(.easeOut(duration: 0.5)) { phase = .done }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        withAnimation { phase = scanned.isEmpty ? .idle : .done }
    }

    func selectDefaults(in categoryID: String? = nil) {
        let pool = categoryID.flatMap { category($0) }.map { [$0] } ?? categories
        selected = Set(pool.filter { $0.safety == .safe }.flatMap(\.items).filter { $0.inUseBy == nil }.map(\.id))
    }

    func cleanSafe() {
        selectDefaults()
        confirming = true
    }

    func toggle(_ item: Item) {
        guard item.inUseBy == nil else { return }
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    func performClean() {
        let chosen = allItems.filter { selected.contains($0.id) }
        let trashedIDs = Set(categories.filter { $0.safety == .review }.flatMap(\.items).map(\.id))
        lastTrashedGB = chosen.filter { trashedIDs.contains($0.id) }.reduce(0) { $0 + $1.gb }
        lastFreedGB = chosen.reduce(0) { $0 + $1.gb } - lastTrashedGB
        freeGB += lastFreedGB
        confirming = false
        route = .result
    }

    /// Fixed states for screenshots.
    func freezeScanning() {
        phase = .scanning
        progress = 0.55
        scanned = Set(categories.prefix(4).map(\.id))
        currentPath = "~/.npm/_npx/eb65ac700b3c4dc9/node_modules"
    }

    func freezeDone() {
        phase = .done
        progress = 1
        scanned = Set(categories.map(\.id))
    }
}

enum Mock {
    static let categories: [Category] = [
        Category(id: "projects", name: "Projetos parados", blurb: "node_modules de projetos sem mexer há 30 dias. Voltam com npm install.", symbol: "shippingbox.fill", tint: .green, safety: .safe, items: [
            Item(id: "p1", name: "agentia-wa", path: "~/Projetos/agentia-wa/node_modules", gb: 1.9, age: "há 47 dias"),
            Item(id: "p2", name: "mavikos-ads", path: "~/Projetos/mavikos-ads/node_modules", gb: 1.6, age: "há 62 dias"),
            Item(id: "p3", name: "imobai", path: "~/Projetos/imobai/node_modules", gb: 1.4, age: "há 38 dias"),
            Item(id: "p4", name: "estetiqo-agy", path: "~/Projetos/estetiqo-agy/node_modules", gb: 1.2, age: "há 33 dias"),
            Item(id: "p5", name: "Mais 41 projetos", path: "~/Projetos, ~/dev", gb: 8.3, age: "30 a 210 dias"),
        ]),
        Category(id: "devcaches", name: "Caches de programação", blurb: "npm, pnpm, uv, cargo e pre-commit. Baixam de novo quando precisar.", symbol: "hammer.fill", tint: .blue, safety: .safe, items: [
            Item(id: "d1", name: "pnpm store", path: "~/Library/pnpm/store", gb: 1.31, age: "hoje"),
            Item(id: "d2", name: "pre-commit", path: "~/.cache/pre-commit", gb: 0.78, age: "há 3 dias"),
            Item(id: "d3", name: "npm", path: "~/.npm/_cacache", gb: 0.49, age: "hoje"),
            Item(id: "d4", name: "cargo", path: "~/.cargo/registry/cache", gb: 0.14, age: "há 20 dias"),
            Item(id: "d5", name: "uv", path: "~/.cache/uv", gb: 0.11, age: "hoje"),
        ]),
        Category(id: "appcaches", name: "Caches de apps", blurb: "Arquivos temporários que os apps recriam sozinhos.", symbol: "square.stack.3d.up.fill", tint: .indigo, safety: .safe, items: [
            Item(id: "a1", name: "Google Chrome", path: "~/Library/Caches/Google", gb: 1.6, age: "hoje", inUseBy: "Chrome"),
            Item(id: "a2", name: "Spotify", path: "~/Library/Caches/com.spotify.client", gb: 1.1, age: "ontem"),
            Item(id: "a3", name: "Outros 38 apps", path: "~/Library/Caches", gb: 1.3, age: "variado"),
        ]),
        Category(id: "logs", name: "Logs", blurb: "Registros antigos de apps e do sistema do usuário.", symbol: "doc.text.fill", tint: .gray, safety: .safe, items: [
            Item(id: "l1", name: "Logs do usuário", path: "~/Library/Logs", gb: 0.21, age: "variado"),
        ]),
        Category(id: "npx", name: "Ferramentas do npx", blurb: "Pacotes baixados pelo npx. Vários são servidores MCP em uso.", symbol: "terminal.fill", tint: .orange, safety: .review, items: [
            Item(id: "n1", name: "eb65ac70", path: "~/.npm/_npx/eb65ac700b3c4dc9", gb: 0.31, age: "hoje", inUseBy: "Claude"),
            Item(id: "n2", name: "c943b712", path: "~/.npm/_npx/c943b712072b77c4", gb: 0.22, age: "há 12 dias"),
            Item(id: "n3", name: "0e6c276d", path: "~/.npm/_npx/0e6c276d240787e3", gb: 0.22, age: "há 40 dias"),
            Item(id: "n4", name: "Mais 21 pacotes", path: "~/.npm/_npx", gb: 1.65, age: "variado"),
        ]),
        Category(id: "ai", name: "Modelos de IA", blurb: "Hugging Face e Whisper. Baixar de novo pode demorar.", symbol: "brain.head.profile", tint: .purple, safety: .review, items: [
            Item(id: "m1", name: "Hugging Face", path: "~/.cache/huggingface", gb: 1.5, age: "há 21 dias"),
            Item(id: "m2", name: "Whisper", path: "~/.cache/whisper", gb: 0.93, age: "há 55 dias"),
        ]),
        Category(id: "browsers", name: "Navegadores de teste", blurb: "Navegadores do Playwright usados em testes automáticos.", symbol: "safari.fill", tint: .teal, safety: .review, items: [
            Item(id: "b1", name: "ms-playwright", path: "~/Library/Caches/ms-playwright", gb: 2.84, age: "há 9 dias"),
        ]),
        Category(id: "installers", name: "Instaladores", blurb: "Arquivos .dmg e .pkg em Downloads com mais de 14 dias.", symbol: "arrow.down.circle.fill", tint: .pink, safety: .review, items: [
            Item(id: "i1", name: "Docker.dmg", path: "~/Downloads/Docker.dmg", gb: 0.62, age: "há 70 dias"),
            Item(id: "i2", name: "Cursor-arm64.dmg", path: "~/Downloads/Cursor-arm64.dmg", gb: 0.23, age: "há 45 dias"),
        ]),
    ]

    static let processes: [(String, Double, Color)] = [
        ("Claude", 3.1, .orange), ("Google Chrome", 2.4, .yellow), ("Cursor", 1.9, .blue),
        ("Docker (Colima)", 1.6, .cyan), ("Codex", 0.9, .gray), ("Slack", 0.6, .purple),
    ]

    static let bigFiles: [(String, String, Double, String)] = [
        ("Claude VM", "~/Library/Application Support/Claude/vm_bundles", 11.0, "hoje"),
        ("gravacao-aula-03.mov", "~/Movies/gravacao-aula-03.mov", 4.2, "há 90 dias"),
        ("llama3.1-8b.gguf", "~/.ollama/models/blobs", 4.7, "há 33 dias"),
        ("backup-supabase.sql", "~/Downloads/backup-supabase.sql", 1.3, "há 120 dias"),
        ("Xcode_16.xip", "~/Downloads/Xcode_16.xip", 1.1, "há 200 dias"),
    ]
}
