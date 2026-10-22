# 02 · TRD: Spare

## Stack

| Item | Escolha | Motivo |
|---|---|---|
| Linguagem | Swift 6 (modo de linguagem 6, concorrência estrita) | Nativo, leve, acesso direto a disco, Lixeira e processos |
| Interface | SwiftUI (`MenuBarExtra` estilo janela + `Window`) | Barra de menus nativa a partir do macOS 13 |
| Estado | `Observation` (`@Observable`) | Exige macOS 14, que é o mínimo suportado |
| Build | Swift Package Manager (sem projeto Xcode) | Validado em 2026-10-22: compila e testa só com Command Line Tools |
| Testes | Swift Testing (`import Testing`) | Roda com `swift test` sem Xcode |
| Empacotamento | `scripts/build-app.sh` monta `Spare.app`; `scripts/make-dmg.sh` gera o `.dmg` com `hdiutil` | Sem dependências externas |
| Assinatura | Ad-hoc (`codesign --sign -`) | Obrigatório em Apple Silicon; sem custo |
| CI | GitHub Actions `macos-latest` rodando `swift build` e `swift test` | Gratuito para repositório público; CI local é o gate oficial |
| Licença | MIT | Igual ao Codenotch; nenhum código de terceiros GPL |

Sem dependências de terceiros no MVP.

## Estrutura do pacote

```
Package.swift
Sources/
  SpareCore/        # motor: nenhuma dependência de SwiftUI
    Disk/           # DiskMonitor (espaço livre)
    Rules/          # Rule, Category, Safety, RuleCatalog
    Scan/           # Scanner, ProjectScanner, LargeFileFinder, SizeCalculator
    Clean/          # Cleaner, TrashService, CommandRunner, InUseGuard
    History/        # HistoryStore, CleanupRecord, Undo
    Memory/         # MemoryMonitor, ProcessLister, ProcessTerminator
    Settings/       # SpareSettings (Codable)
    Support/        # Environment (home, raízes, relógio), ByteFormatter
  spare/            # CLI: subcomandos finos chamando o SpareCore
  SpareApp/         # app SwiftUI: telas, ViewModels, notificações
    Resources/      # en.lproj e pt-BR.lproj (Localizable.strings), Info.plist de referência
Tests/
  SpareCoreTests/   # unidade e integração com pastas temporárias
  spareCLITests/    # executa o binário contra um HOME falso
scripts/
  build-app.sh, make-dmg.sh, check.sh
```

## Contratos do motor (SpareCore)

```swift
public struct SpareEnvironment: Sendable {   // tudo que toca o sistema é injetável
  public var home: URL
  public var projectRoots: [URL]
  public var now: @Sendable () -> Date
  public var runningProcesses: @Sendable () -> [RunningProcess]
  public var commandRunner: CommandRunning
  public var trash: TrashService
}

public enum Safety: String, Codable { case safe, review }
public enum CleanAction: Codable { case trash; case command(executable: String, arguments: [String]) }

public struct Rule: Codable, Identifiable {     // uma regra do catálogo
  public let id: String                         // ex.: "dev.npm"
  public let category: CategoryID
  public let paths: [String]                    // relativos ao home, glob simples permitido no último nível
  public let safety: Safety
  public let action: CleanAction
  public let inUseHint: InUseHint               // processos/apps que impedem a limpeza
  public let explanationKey: String             // chave de tradução
}

public struct ScanItem: Codable, Identifiable { id, ruleID, url, sizeBytes, safety, inUse: Bool, lastModified }
public struct ScanReport: Codable { items, totalsByCategory, freeBytesBefore, startedAt, finishedAt, cancelled }

public final class Scanner { func scan(progress: (ScanProgress) -> Void) async throws -> ScanReport }   // cancelável
public final class Cleaner { func clean(_ items: [ScanItem], progress:) async throws -> CleanupRecord }  // cancelável
public final class HistoryStore { func all() -> [CleanupRecord]; func undo(_ recordID) throws -> UndoResult }
public struct DiskMonitor { func freeBytes() throws -> Int64 }   // volumeAvailableCapacityForImportantUsageKey
public struct MemoryMonitor { func snapshot() -> MemorySnapshot } // pressão + processos ordenados por memória
```

## Regras de segurança (invariantes testadas)

1. **Catálogo fechado:** o `Cleaner` recusa qualquer `ScanItem` cujo caminho resolvido (após seguir links simbólicos) não esteja dentro de um caminho de regra do catálogo ou de uma raiz de projetos configurada.
2. **Links simbólicos:** nunca seguir link simbólico para fora do caminho da regra; o tamanho conta só o conteúdo real dentro dele.
3. **Lista de proteção absoluta:** nada fora do `home` é alvo (isso cobre `/private` e volumes externos); `/System`, `/Library`, `/Applications`, `/usr`, `/bin`, `/sbin`, `/opt`, o próprio `home`, `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Movies`, `~/Music`, `~/Library` (raiz), `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/Library/Keychains`, `~/Library/Mobile Documents` nunca são alvo de regra, mesmo que uma regra tente. Na tela Maiores arquivos (escolha explícita do usuário), só credenciais (`.ssh`, `.gnupg`, `.aws`, `.kube`, `Keychains`) ficam bloqueadas.
4. **Em uso:** item é pulado se (a) o app dono do cache está aberto (bundle id no nome da pasta e `NSRunningApplication`), (b) a linha de comando de algum processo do usuário contém o caminho do item (ex.: servidores MCP rodando de `~/.npm/_npx`), ou (c) a ferramenta da regra está rodando (ex.: `uv`, `npm`, `pnpm`).
5. **Projetos:** `node_modules`, `.venv`, `.next`, `target` só entram se a pasta do projeto (pai) não teve arquivo modificado fora dessas pastas há N dias (padrão 30) e contém o arquivo de manifesto correspondente (`package.json`, `pyproject.toml` ou `requirements.txt`, `next.config.*`, `Cargo.toml`).
6. **Apagar só o que se regenera:** ação `delete` apenas para dados que se regeneram sozinhos (caches, logs, dependências de projetos parados). Ação `trash` (instaladores, modelos de IA, VM do Claude, arquivos grandes) usa `FileManager.trashItem(at:resultingItemURL:)` e grava a URL resultante para o Desfazer; "Liberar agora" apaga da Lixeira apenas os itens que o Spare mandou para lá. Ação `command` só quando a ferramenta tem limpeza oficial (`npm cache clean --force`, `uv cache clean`, `pnpm store prune`, `brew cleanup --prune=all`) e não passa por verificação de uso (a ferramenta controla seus próprios bloqueios).
7. **Lixeira do sistema:** esvaziar a Lixeira é a única remoção definitiva; exige confirmação explícita com o texto "Isso não pode ser desfeito".
8. **Encerrar processo:** só processos do usuário atual, nunca PID 1, nunca processos de `/System` ou `/usr`, nunca o próprio Spare; apps com interface usam `NSRunningApplication.terminate()` (encerramento educado); demais recebem `SIGTERM`, nunca `SIGKILL`.

## Medição de tamanho

`SizeCalculator` soma `totalFileAllocatedSize` via `FileManager.enumerator` com `URLResourceKey`s pré-buscadas, sem seguir links, contando cada inode uma vez (hardlinks do `pnpm` e do `uv` não podem ser contados duas vezes). Executa em `TaskGroup` com no máximo 4 tarefas simultâneas. Verifica cancelamento a cada 1.000 arquivos.

## Monitoramento

- Disco: `volumeAvailableCapacityForImportantUsageKey` do volume do `home`, a cada 60 s e após cada limpeza.
- Memória: pressão via `host_statistics64` (`vm_statistics64`): `(wired + compressed) / total`; nível alto acima de 80% ou quando o kernel sinaliza pressão via `DispatchSource.makeMemoryPressureSource`. Processos via `ps -axo pid=,rss=,user=,comm=` filtrando pelo usuário atual.
- Alertas: `UNUserNotificationCenter`, no máximo um alerta de disco a cada 6 horas enquanto continuar abaixo do limite.

## CLI

```
spare status [--json]                 # espaço livre e pressão de memória
spare scan [--json] [--category ID]   # prévia, nunca altera nada
spare clean --rule ID... [--yes]      # sem --yes só mostra o que faria
spare undo [RECORD_ID]                # restaura a última limpeza (ou a indicada)
spare history [--json]
spare large [PATH] [--min-mb 500] [--json]
spare memory [--json]
```

A variável `SPARE_HOME` substitui o `home` (usada nos testes de CLI e no QA).

## Qualidade (gates locais)

`scripts/check.sh` roda: `swift build -c release`, `swift test`, checagem de formatação (`swift format lint --strict` se disponível na toolchain), e `scripts/build-app.sh` para garantir que o bundle monta. Todo PR exige o gate verde.

## Riscos técnicos

| Risco | Mitigação |
|---|---|
| macOS pede permissão ao ler Downloads, Documentos ou Área de Trabalho | Varredura do MVP evita Documentos e Área de Trabalho; Downloads só para instaladores; texto explicando o pedido de permissão |
| Notificações e "abrir ao iniciar sessão" com assinatura ad-hoc | Validar no QA final; se `SMAppService` falhar, mostrar instrução manual |
| Contagem dupla com hardlinks | Conjunto de inodes vistos por varredura; teste dedicado |
| Concorrência estrita do Swift 6 | Motor com tipos `Sendable`; UI em `@MainActor` |
