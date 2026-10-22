# 01 · PRD: Spare

## Visão

Spare é um app gratuito e open source (MIT) para macOS que mantém o disco e a memória do Mac sob controle, com foco em quem trabalha com IA e vibecoding. Fica na barra de menus, avisa antes de o disco estourar e libera espaço com segurança: tudo passa pela Lixeira e pode ser desfeito.

## Problema

Quem usa IA e programa no Mac acumula dezenas de GB de lixo invisível: caches de `npm`, `uv`, `pnpm`, `node_modules` de projetos parados, modelos de IA baixados e runtimes antigos. Limpadores genéricos (ex.: CleanMyMac) não enxergam a maior parte disso. Evidência real do Mac do autor em 2026-10-22: disco a 96% (9,2 GB livres); CleanMyMac encontrou 4,4 GB de lixo, enquanto cerca de 35 GB eram lixo de desenvolvimento e IA recuperável.

## Público

1. Primário: o próprio autor (Rafael Jorge), dev assistido por IA, MacBook com 228 GB.
2. Secundário: qualquer pessoa no macOS 14+ que programa ou usa ferramentas de IA localmente.

## Princípios

1. **Funcional antes de estético.** Interface nativa e limpa do macOS; sem ilustrações 3D nem fundos animados.
2. **Leve.** Fica aberto o dia todo sem pesar (meta: menos de 60 MB de RAM e CPU perto de 0% em repouso).
3. **Seguro por padrão.** Só toca no que está no catálogo de regras; prévia antes de qualquer ação; Lixeira em vez de apagar; nunca mexe no que está em uso.
4. **Linguagem de usuário.** Cada item explica em uma frase o que é e o que acontece se for removido.

## Escopo do MVP (v0.1.0)

| ID | Função | Resumo |
|---|---|---|
| F1 | Barra de menus | Ícone com espaço livre em GB; painel com cartões Disco, Memória e "Recomendação de hoje" |
| F2 | Alertas | Notificação quando o espaço livre cai abaixo do limite (padrão 15 GB) e quando a pressão de memória fica alta |
| F3 | Analisar tudo | Uma varredura de disco e memória com progresso visível (o que está sendo lido agora) e botão Parar |
| F4 | Limpeza por categorias | Cartões por categoria com tamanho total, selo de segurança e botões Revisar e Limpar |
| F5 | Revisão | Lista de itens da categoria com caixa de seleção, tamanho, selo e explicação |
| F6 | Execução segura | Move para a Lixeira ou roda o comando oficial da ferramenta; pula itens em uso; progresso com Parar |
| F7 | Resultado e Desfazer | Antes e depois do espaço livre, registro por categoria, Desfazer (restaura da Lixeira) |
| F8 | Histórico | Lista das limpezas anteriores com o que foi feito e o que ainda pode ser desfeito |
| F9 | Maiores arquivos | Escolher pasta (padrão: pasta pessoal), listar os 20 maiores arquivos acima de 500 MB, Mostrar no Finder, Mover para a Lixeira |
| F10 | Memória | Pressão de memória e os 15 processos que mais consomem, com botão Encerrar (só processos do usuário) |
| F11 | Ajustes | Limite do alerta, pastas de projetos, dias de inatividade, abrir ao iniciar sessão |
| F12 | Idiomas | Português (Brasil) e inglês, seguindo o idioma do sistema |
| F13 | CLI `spare` | Mesmas funções do motor pelo terminal (`status`, `scan`, `clean`, `undo`, `history`, `large`, `memory`), com saída JSON |

## Categorias de limpeza do MVP

| Categoria | Exemplos | Selo padrão |
|---|---|---|
| Caches de desenvolvimento | npm, pnpm, Yarn, uv, pip, Cargo, Homebrew, Xcode DerivedData | 🟢 Seguro |
| Restos de projetos parados | `node_modules`, `.venv`, `.next`, `target` em projetos sem alteração há 30+ dias | 🟢 Seguro |
| Ferramentas de IA | cache do Hugging Face, modelos Whisper, cache do `npx`, runtimes antigos do Codex | 🟡 Revisar |
| Caches de apps | `~/Library/Caches/*` de apps fechados | 🟢 Seguro |
| Logs | `~/Library/Logs` | 🟢 Seguro |
| Instaladores esquecidos | `.dmg`, `.pkg` em Downloads com 30+ dias | 🟢 Seguro |
| Lixeira | `~/.Trash` | 🟡 Revisar (esvaziar é definitivo) |

## Fora do MVP (decisão consciente)

Antivírus, atualizador de apps, desinstalador, duplicados e fotos parecidas, limpeza de nuvem, Docker, itens de início e segundo plano (v2), "Mover para o SSD externo" (v2), nota de "saúde do Mac", cartões de bateria, CPU e rede.

## Critérios de sucesso

1. No Mac do autor, "Analisar tudo" encontra pelo menos 20 GB recuperáveis com segurança em menos de 60 segundos.
2. Nenhum item fora do catálogo é tocado; testes automatizados provam isso com pastas falsas.
3. Toda remoção por Lixeira pode ser desfeita pelo app.
4. App pronto em `.dmg` no GitHub Releases, instalável no macOS 14+ seguindo o README.

## Distribuição

GitHub Releases com `.dmg` assinado ad-hoc (sem conta Apple Developer paga). O README explica o passo "Abrir Mesmo Assim" em Ajustes do Sistema. Notarização fica para quando houver tração.
