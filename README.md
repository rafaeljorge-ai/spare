# Spare

Spare keeps your Mac's disk and memory in check, with a focus on developer and AI junk. Free, open source, menu bar app plus CLI.

**Status:** v0.1.0 in development. Current step: see [`docs/planta/STATUS.md`](docs/planta/STATUS.md).

## Why

People who code and use AI on a Mac pile up tens of GB of invisible junk: `npm`, `uv` and `pnpm` caches, `node_modules` of idle projects, downloaded AI models and old runtimes. Generic cleaners (for example CleanMyMac) do not see most of it. Real evidence from the author's Mac on 2026-10-22: disk at 96% (9.2 GB free); CleanMyMac found 4.4 GB of junk, while about 35 GB was recoverable developer and AI junk.

## Features (MVP)

1. Menu bar icon with free space in GB and a panel with Disk, Memory and "Today's recommendation" cards.
2. Alerts when free space drops below your limit (default 15 GB) and when memory pressure is high.
3. "Analyze everything": one scan of disk and memory, with visible progress and a Stop button.
4. Cleanup by category, with total size, a safety badge, and Review and Clean buttons.
5. Review screen: every item with a checkbox, size, badge and explanation.
6. Safe execution: deletes only what regenerates itself, moves the rest to the Trash or runs the tool's official cleanup command, and skips items in use.
7. Result and Undo: free space before and after, a record per category, Undo (restores from the Trash) and "Free now" (empties only what Spare put in the Trash).
8. History of previous cleanups.
9. Largest files: pick a folder, list the 20 largest files above 500 MB, Show in Finder, Move to Trash.
10. Memory: pressure and the 15 heaviest processes, with a Quit button (your own processes only).
11. Settings: alert limit, project folders, idle days, open at login.
12. English and Brazilian Portuguese, following the system language.
13. `spare` CLI with the same engine and JSON output.

## Safety

- Closed catalog: Spare only touches paths listed in its rule catalog or in your configured project folders.
- Symbolic links are never followed outside a rule's path; sizes count only real content.
- A protected list is never a target: nothing outside your home folder, and never Documents, Desktop, Pictures, Movies, Music, `~/Library` root, `.ssh`, `.gnupg`, `.aws`, `.kube`, Keychains or iCloud Drive.
- Items in use are skipped: an open app, a process whose command line uses the path, or a running tool.
- Project folders (`node_modules`, `.venv`, `.next`, `target`) are only listed when the project is idle and has its manifest file.
- Delete only what regenerates; everything else goes to the Trash with a recorded location, so Undo works.
- Emptying the system Trash is the only permanent removal and needs explicit confirmation.
- Quitting a process: only your own, never PID 1 or system processes, never Spare itself, and never `SIGKILL`.

## Build from source

Requires macOS 14+ and Swift 6 (Command Line Tools are enough, Xcode is optional).

```
swift build
scripts/check.sh       # full local gate (runs the tests)
scripts/build-app.sh   # builds dist/Spare.app
```

## CLI usage

```
spare status [--json]      Free disk space and memory
spare scan [--json] [--category ID]   Preview what can be freed (changes nothing)
spare rules                List rule IDs
spare clean --rule ID [--rule ID] [--yes] [--dry-run] [--json]
                           Clean the items of these rules. Without --yes it only previews;
                           --dry-run always previews. Items in use are never cleaned.
spare undo [RECORD_ID] [--dry-run]
                           Restore trashed items of the last (or given) cleanup; an item whose
                           original path is taken stays in the Trash and the reason is printed
spare purge [RECORD_ID] [--yes] [--dry-run]
                           Permanently delete the items Spare itself moved to the Trash (the rest of
                           the Trash is never touched). Without --yes it only previews.
spare history [--json]     Past cleanups
spare memory [--json]      Memory pressure and top consumers (approximate: built from public APIs,
                           shared memory is counted in every process that uses it)
spare quit NAME [--yes] [--dry-run]
                           Ask one of your own apps or tools to quit (SIGTERM). Without --yes it only
                           previews; system processes and Spare itself are refused.
spare help                 Show this help
```

Safe first run: `spare scan`, then `spare clean --rule dev.npx` (preview only), then add `--yes`. Cleanups are
saved in `~/Library/Application Support/Spare/history.json` (folder `0700`, file `0600`).

## Project docs

- [PRD](docs/planta/01-PRD.md)
- [TRD](docs/planta/02-TRD.md)
- [Screens and flows](docs/planta/03-TELAS-E-FLUXOS.md)
- [Data and permissions](docs/planta/04-DADOS-E-PERMISSOES.md)
- [Operations and release](docs/planta/05-OPERACAO-E-RELEASE.md)
- [Status](docs/planta/STATUS.md)
- [Design system](.interface-design/system.md) and the visual prototype (`Prototype/run.sh`)
- [Implementation plan](docs/superpowers/plans/2026-10-22-spare-mvp/00-INDEX.md)

## License

MIT. See [LICENSE](LICENSE).

## Português

Spare mantém o disco e a memória do seu Mac em ordem, com foco no lixo de desenvolvimento e de IA. Gratuito, código aberto, app de barra de menus mais CLI.

**Status:** v0.1.0 em desenvolvimento. Etapa atual: veja [`docs/planta/STATUS.md`](docs/planta/STATUS.md).

### Por quê

Quem programa e usa IA no Mac acumula dezenas de GB de lixo invisível: caches de `npm`, `uv` e `pnpm`, `node_modules` de projetos parados, modelos de IA baixados e runtimes antigos. Limpadores genéricos (por exemplo, o CleanMyMac) não enxergam a maior parte disso. Evidência real do Mac do autor em 2026-10-22: disco a 96% (9,2 GB livres); o CleanMyMac encontrou 4,4 GB de lixo, enquanto cerca de 35 GB eram lixo de desenvolvimento e IA recuperável.

### Funcionalidades (MVP)

1. Ícone na barra de menus com o espaço livre em GB e um painel com os cartões Disco, Memória e "Recomendação de hoje".
2. Alertas quando o espaço livre cai abaixo do seu limite (padrão 15 GB) e quando a pressão de memória fica alta.
3. "Analisar tudo": uma varredura de disco e memória, com progresso visível e botão Parar.
4. Limpeza por categorias, com tamanho total, selo de segurança e botões Revisar e Limpar.
5. Revisão: cada item com caixa de seleção, tamanho, selo e explicação.
6. Execução segura: apaga só o que se regenera, move o resto para a Lixeira ou roda o comando oficial da ferramenta, e pula itens em uso.
7. Resultado e Desfazer: espaço livre antes e depois, registro por categoria, Desfazer (restaura da Lixeira) e "Liberar agora" (apaga só o que o Spare mandou para a Lixeira).
8. Histórico das limpezas anteriores.
9. Maiores arquivos: escolha uma pasta, veja os 20 maiores acima de 500 MB, Mostrar no Finder, Mover para a Lixeira.
10. Memória: pressão e os 15 processos mais pesados, com botão Encerrar (só processos seus).
11. Ajustes: limite do alerta, pastas de projetos, dias de inatividade, abrir ao iniciar sessão.
12. Português (Brasil) e inglês, seguindo o idioma do sistema.
13. CLI `spare` com o mesmo motor e saída JSON.

### Segurança

- Catálogo fechado: o Spare só mexe em caminhos do seu catálogo de regras ou nas pastas de projetos que você configurou.
- Links simbólicos nunca são seguidos para fora do caminho da regra; o tamanho conta só o conteúdo real.
- Uma lista de proteção nunca é alvo: nada fora da sua pasta pessoal, e nunca Documentos, Mesa, Imagens, Filmes, Música, a raiz de `~/Library`, `.ssh`, `.gnupg`, `.aws`, `.kube`, Keychains ou iCloud Drive.
- Itens em uso são pulados: app aberto, processo cuja linha de comando usa o caminho, ou ferramenta em execução.
- Pastas de projeto (`node_modules`, `.venv`, `.next`, `target`) só aparecem quando o projeto está parado e tem o arquivo de manifesto.
- Apagar só o que se regenera; o resto vai para a Lixeira com o local registrado, para o Desfazer funcionar.
- Esvaziar a Lixeira do sistema é a única remoção definitiva e exige confirmação explícita.
- Encerrar processo: só os seus, nunca o PID 1 nem processos do sistema, nunca o próprio Spare, e nunca `SIGKILL`.

### Compilar do código-fonte

Requer macOS 14+ e Swift 6 (as Command Line Tools bastam, o Xcode é opcional).

```
swift build
scripts/check.sh       # gate local completo (roda os testes)
scripts/build-app.sh   # gera dist/Spare.app
```

### Uso da CLI

```
spare status [--json]      Espaço livre em disco
spare scan [--json] [--category ID]   Mostra o que dá para liberar (não altera nada)
spare rules                Lista os IDs das regras
spare clean --rule ID [--rule ID] [--yes] [--dry-run] [--json]
                           Limpa os itens dessas regras. Sem --yes só mostra o que faria;
                           --dry-run sempre só mostra. Itens em uso nunca são limpos.
spare undo [ID_DA_LIMPEZA] [--dry-run]
                           Devolve os itens da última limpeza (ou da informada) ao lugar original;
                           se o lugar original estiver ocupado, o item fica na Lixeira e o motivo é mostrado
spare purge [ID_DA_LIMPEZA] [--yes] [--dry-run]
                           Apaga para sempre só os itens que o próprio Spare mandou para a Lixeira
                           (o resto da Lixeira nunca é tocado). Sem --yes só mostra o que faria.
spare history [--json]     Limpezas anteriores
spare memory [--json]      Pressão de memória e maiores consumidores (aproximado: APIs públicas,
                           memória compartilhada é contada em cada processo que a usa)
spare quit NOME [--yes] [--dry-run]
                           Pede a um app ou ferramenta seu que feche (SIGTERM). Sem --yes só mostra;
                           processos do sistema e o próprio Spare são recusados.
spare help                 Mostra a ajuda
```

Primeiro uso seguro: `spare scan`, depois `spare clean --rule dev.npx` (só prévia), e então acrescente `--yes`.
O histórico fica em `~/Library/Application Support/Spare/history.json` (pasta `0700`, arquivo `0600`).

### Documentação do projeto

Veja a lista na seção "Project docs" acima.

### Licença

MIT. Veja [LICENSE](LICENSE).
