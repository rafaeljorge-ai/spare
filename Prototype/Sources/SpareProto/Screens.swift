import SwiftUI

// MARK: Overview

struct OverviewScreen: View {
    @ObservedObject var model: ProtoModel

    var body: some View {
        VStack(spacing: 0) {
            headline
                .padding(.top, 56)
            Spacer(minLength: 20)
            ZStack {
                SpareRing(model: model)
                center
            }
            Spacer(minLength: 20)
            footer
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder private var headline: some View {
        VStack(spacing: 6) {
            switch model.phase {
            case .idle:
                Text("Seu Mac tem \(size(model.freeGB)) livres").font(Txt.h1).tracking(-0.3)
                Text("Analise caches, projetos parados e restos de IA em uma única passada.")
                    .font(Txt.body).foregroundStyle(Ink.tertiary)
            case .scanning:
                Text("Analisando…").font(Txt.h1).tracking(-0.3)
                Text(model.currentPath).font(.system(size: 12, design: .monospaced)).foregroundStyle(Ink.muted)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 460)
            case .done:
                Text("Análise concluída").font(Txt.h1).tracking(-0.3)
                Text("Mais \(size(model.reviewGB)) para você revisar com calma.")
                    .font(Txt.body).foregroundStyle(Ink.tertiary)
            }
        }
    }

    @ViewBuilder private var center: some View {
        switch model.phase {
        case .idle:
            ScanButton { model.startScan() }
        case .scanning:
            VStack(spacing: 2) {
                Text("\(Int(model.progress * 100))%").font(Txt.display).monospacedDigit()
                Text("\(model.scanned.count) de \(model.categories.count) categorias").font(Txt.caption).foregroundStyle(Ink.tertiary)
            }
        case .done:
            VStack(spacing: 2) {
                Text(size(model.safeGB)).font(Txt.display).foregroundStyle(Ink.spare).monospacedDigit()
                Text("podem sair com segurança").font(Txt.label).foregroundStyle(Ink.secondary)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .idle:
            HStack(spacing: 12) {
                Stat(title: "DISCO", value: size(model.totalGB - model.freeGB), detail: "em uso de \(size(model.totalGB))")
                Stat(title: "MEMÓRIA", value: "Normal", detail: "pressão em 50%")
                Stat(title: "ÚLTIMA LIMPEZA", value: "Nunca", detail: "faça a primeira análise")
            }
        case .scanning:
            HStack(spacing: 8) {
                ForEach(model.categories) { category in
                    let done = model.scanned.contains(category.id)
                    Tile(symbol: done ? "checkmark" : category.symbol, tint: done ? category.tint : Ink.surface2, side: 30)
                        .opacity(done ? 1 : 0.6)
                }
                Spacer().frame(width: 16)
                Button("Parar") { model.stopScan() }.buttonStyle(QuietButton())
            }
        case .done:
            VStack(spacing: 16) {
                legend
                HStack(spacing: 10) {
                    Button("Revisar tudo") { model.route = .cleanup }.buttonStyle(QuietButton())
                    Button("Limpar o que é seguro") { model.cleanSafe() }.buttonStyle(PrimaryButton())
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Swatch(color: Ink.spare, label: "Seguro \(size(model.safeGB))")
            Swatch(color: Ink.review, label: "Revisar \(size(model.reviewGB))")
            Swatch(color: Ink.used, label: "Em uso")
            Swatch(color: Ink.track, label: "Livre \(size(model.freeGB))")
        }
    }
}

private struct Swatch: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(Txt.caption).foregroundStyle(Ink.secondary).monospacedDigit()
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Ink.muted)
            Text(value).font(Txt.figure).monospacedDigit()
            Text(detail).font(Txt.caption).foregroundStyle(Ink.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
    }
}

// MARK: Cleanup cards

struct CleanupScreen: View {
    @ObservedObject var model: ProtoModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Limpeza", subtitle: "\(size(model.safeGB)) seguros e \(size(model.reviewGB)) para revisar em \(model.categories.count) categorias")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(model.categories) { CategoryCard(model: model, category: $0) }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct CategoryCard: View {
    @ObservedObject var model: ProtoModel
    let category: Category

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Tile(symbol: category.symbol, tint: category.tint, side: 36)
                    Spacer()
                    Badge(safety: category.safety)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name).font(Txt.h3)
                    Text(category.blurb).font(Txt.caption).foregroundStyle(Ink.tertiary).lineLimit(2, reservesSpace: true)
                }
                HStack {
                    Text(size(category.gb)).font(Txt.figure).monospacedDigit()
                    Spacer()
                    Button("Revisar") {
                        model.selectDefaults(in: category.id)
                        model.route = .review(category.id)
                    }
                    .buttonStyle(QuietButton())
                    if category.safety == .safe {
                        Button("Limpar") {
                            model.selectDefaults(in: category.id)
                            model.confirming = true
                        }
                        .buttonStyle(PrimaryButton())
                    }
                }
            }
        }
    }
}

// MARK: Review

struct ReviewScreen: View {
    @ObservedObject var model: ProtoModel
    let categoryID: String

    var body: some View {
        let category = model.category(categoryID)!
        VStack(spacing: 0) {
            ScreenHeader(title: category.name, subtitle: category.blurb) { model.route = .cleanup }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(category.items) { item in
                        row(item)
                        if item.id != category.items.last?.id { Rectangle().fill(Ink.line).frame(height: 1).padding(.leading, 46) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
                .padding(.horizontal, 32)
            }
            footer
        }
    }

    private func row(_ item: Item) -> some View {
        let busy = item.inUseBy != nil
        return Button { model.toggle(item) } label: {
            HStack(spacing: 14) {
                Checkbox(on: model.selected.contains(item.id), enabled: !busy)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(Txt.label)
                    Text(item.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 16)
                Text(item.age).font(Txt.caption).foregroundStyle(Ink.tertiary).frame(width: 90, alignment: .trailing)
                status(item)
                    .frame(width: 130, alignment: .trailing)
                Text(size(item.gb)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .contentShape(Rectangle())
            .opacity(busy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func status(_ item: Item) -> some View {
        if let app = item.inUseBy {
            Label("Em uso por \(app)", systemImage: "lock.fill").font(Txt.caption).foregroundStyle(Ink.busy)
        } else {
            Text("Pronto").font(Txt.caption).foregroundStyle(Ink.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            Text("Selecionados: \(model.selected.count) itens · \(size(model.selectedGB))").font(Txt.label).foregroundStyle(Ink.secondary).monospacedDigit()
            Spacer()
            Button("Limpar selecionados") { model.confirming = true }.buttonStyle(PrimaryButton()).disabled(model.selected.isEmpty)
        }
        .padding(.horizontal, 32)
        .frame(height: 68)
        .background(Ink.night.opacity(0.35))
        .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: 1) }
    }
}

// MARK: Confirm

struct ConfirmSheet: View {
    @ObservedObject var model: ProtoModel

    var body: some View {
        let ids = model.selected
        let trashIDs = Set(model.categories.filter { $0.safety == .review }.flatMap(\.items).map(\.id))
        let trashGB = model.allItems.filter { ids.contains($0.id) && trashIDs.contains($0.id) }.reduce(0) { $0 + $1.gb }
        VStack(alignment: .leading, spacing: 18) {
            Text("Limpar \(ids.count) itens (\(size(model.selectedGB)))?").font(Txt.h2)
            Label("Caches e restos que se recriam sozinhos são apagados de vez para liberar espaço agora.", systemImage: "bolt.fill")
                .font(Txt.body).foregroundStyle(Ink.secondary)
            if trashGB > 0 {
                Label("\(size(trashGB)) vão para a Lixeira e podem ser desfeitos.", systemImage: "trash")
                    .font(Txt.body).foregroundStyle(Ink.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { model.confirming = false }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("Limpar") { model.performClean() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Ink.night)
        .foregroundStyle(Ink.primary)
    }
}

// MARK: Result

struct ResultScreen: View {
    @ObservedObject var model: ProtoModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Ink.spare)
            Text("Limpeza concluída").font(Txt.h1)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(size(model.freeGB - model.lastFreedGB)).foregroundStyle(Ink.tertiary)
                Image(systemName: "arrow.right").font(.system(size: 22, weight: .semibold)).foregroundStyle(Ink.muted)
                Text(size(model.freeGB)).foregroundStyle(Ink.spare)
                Text("livres").font(Txt.h2).foregroundStyle(Ink.secondary)
            }
            .font(Txt.display)
            .monospacedDigit()
            if model.lastTrashedGB > 0 {
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "trash.fill").foregroundStyle(Ink.review)
                        Text("\(size(model.lastTrashedGB)) estão na Lixeira. O espaço volta quando saírem de lá.").font(Txt.body).foregroundStyle(Ink.secondary)
                        Spacer()
                        Button("Desfazer") {}.buttonStyle(QuietButton())
                        Button("Liberar agora") {}.buttonStyle(QuietButton(tint: Ink.review))
                    }
                }
                .frame(maxWidth: 620)
            }
            HStack(spacing: 10) {
                Button("Ver histórico") { model.route = .history }.buttonStyle(QuietButton())
                Button("OK") { model.route = .overview }.buttonStyle(PrimaryButton())
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: Large files, memory, history, settings

struct LargeFilesScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Maiores arquivos", subtitle: "Na sua pasta pessoal, maiores que 500 MB")
            VStack(spacing: 0) {
                ForEach(Mock.bigFiles, id: \.0) { file in
                    HStack(spacing: 14) {
                        Tile(symbol: "doc.fill", tint: .orange, side: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.0).font(Txt.label)
                            Text(file.1).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.muted).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text("aberto \(file.3)").font(Txt.caption).foregroundStyle(Ink.tertiary)
                        Text(size(file.2)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 70, alignment: .trailing)
                        Image(systemName: "magnifyingglass").foregroundStyle(Ink.tertiary).frame(width: 28)
                        Image(systemName: "trash").foregroundStyle(Ink.tertiary).frame(width: 28)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}

struct MemoryScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Memória", subtitle: "11,8 GB usados de 16 GB · atualiza a cada 5 s")
            HStack(alignment: .top, spacing: 20) {
                Card {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(Ink.track, lineWidth: 12)
                            Circle().trim(from: 0, to: 0.5).stroke(Ink.spare, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("50%").font(Txt.display).monospacedDigit()
                                Text("pressão").font(Txt.caption).foregroundStyle(Ink.tertiary)
                            }
                        }
                        .frame(width: 170, height: 170)
                        Text("Normal").font(Txt.h3).foregroundStyle(Ink.spare)
                    }
                    .frame(width: 210)
                }
                VStack(spacing: 0) {
                    ForEach(Mock.processes, id: \.0) { process in
                        HStack(spacing: 12) {
                            Tile(symbol: "app.fill", tint: process.2, side: 28)
                            Text(process.0).font(Txt.label)
                            Spacer()
                            Text(size(process.1)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                            Button("Encerrar") {}.buttonStyle(QuietButton(tint: Ink.busy))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}

struct HistoryScreen: View {
    @ObservedObject var model: ProtoModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Histórico", subtitle: "Tudo o que o Spare limpou, com desfazer enquanto estiver na Lixeira")
            VStack(spacing: 10) {
                entry(date: "Hoje, 14:32", freed: max(model.lastFreedGB, 21.4), items: 14, undo: true)
                entry(date: "15 out, 09:10", freed: 6.8, items: 5, undo: false)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func entry(date: String, freed: Double, items: Int, undo: Bool) -> some View {
        Card {
            HStack(spacing: 14) {
                Tile(symbol: "checkmark", tint: .green, side: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(date).font(Txt.label)
                    Text("\(items) itens").font(Txt.caption).foregroundStyle(Ink.tertiary)
                }
                Spacer()
                Text(size(freed)).font(Txt.figure).foregroundStyle(Ink.spare).monospacedDigit()
                Button("Desfazer") {}.buttonStyle(QuietButton()).disabled(!undo).opacity(undo ? 1 : 0.4)
            }
        }
    }
}

struct SettingsScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Ajustes", subtitle: "Tudo fica só no seu Mac. Sem conta, sem internet.")
            VStack(spacing: 0) {
                setting("Avisar quando o espaço livre ficar abaixo de", value: "15 GB")
                setting("Avisar quando a memória ficar alta", value: "Ligado")
                setting("Pastas de projetos", value: "~/Projetos, ~/dev")
                setting("Projeto parado após", value: "30 dias")
                setting("Abrir o Spare ao ligar o Mac", value: "Ligado")
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.surface1))
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func setting(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(Txt.body)
            Spacer()
            Text(value).font(Txt.label).foregroundStyle(Ink.secondary)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Ink.muted)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}
