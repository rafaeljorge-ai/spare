# 03 · Telas, fluxos e rotas: Spare

Direção: funcional antes de estético. Componentes nativos do SwiftUI, cores e fontes do sistema, modo claro e escuro automáticos. Nenhuma ilustração customizada no MVP.

## Mapa de rotas

```
Barra de menus (ícone + "15 GB")
└── Painel (MenuBarExtra, estilo janela, 340 px)
    ├── Cartão Disco ─────────── [Liberar] → Janela › Limpeza
    ├── Cartão Memória ───────── [Ver]     → Janela › Memória
    ├── Recomendação de hoje ─── [Ação]    → rota da recomendação
    ├── [Analisar tudo]                    → Janela › Visão geral (varredura iniciada)
    └── Rodapé: [Abrir Spare] [Ajustes] [Sair]

Janela principal (900 × 600, barra lateral)
├── Visão geral      (Analisar tudo)
├── Limpeza          (cartões → Revisão → Progresso → Resultado)
├── Maiores arquivos
├── Memória
├── Histórico
└── Ajustes          (também via ⌘,)
```

## Telas

### T1 · Painel da barra de menus
- **Título do ícone:** espaço livre arredondado ("15 GB"). Fica laranja abaixo do limite e vermelho abaixo de 5 GB.
- **Cartão Disco:** "Macintosh HD · 15 GB livres de 228 GB" + barra de uso + botão **Liberar**.
- **Cartão Memória:** "Pressão: 50%" + nível (Normal, Atenção, Alta) + botão **Ver**.
- **Recomendação de hoje:** uma frase e um botão, escolhida por prioridade: (1) disco abaixo do limite → "Há pouco espaço. Analise para liberar." [Analisar]; (2) última análise com mais de 10 GB seguros → "Você pode liberar 23 GB com segurança." [Revisar]; (3) memória alta → "Memória alta. Veja o que está pesando." [Ver]; (4) nada → "Tudo certo por aqui." sem botão.
- **Estados:** carregando (traço no lugar dos números), erro de leitura (mensagem curta + "Tentar de novo").

### T2 · Visão geral (Analisar tudo)
- Estado inicial: frase "Analise o disco e a memória em uma única passada." + botão **Analisar tudo**.
- Em andamento: cartões das categorias aparecem em lista; cada um mostra "Analisando…", depois o tamanho e um ✓. Linha de progresso com o caminho sendo lido agora (truncado no meio). Botão **Parar**.
- Concluído: manchete "Você pode liberar **X GB**" (soma dos itens 🟢 Seguro fora de uso) + "Mais Y GB para revisar". Botões **Revisar tudo** e **Limpar o que é seguro**.
- Parado: mostra o parcial com o aviso "Análise interrompida, resultados parciais".

### T3 · Limpeza: cartões
- Um cartão por categoria: nome, tamanho, selo (🟢 Seguro / 🟡 Revisar), uma frase explicativa, botões **Revisar** e **Limpar** (Limpar só aparece em categorias 🟢).
- Categorias vazias ficam ocultas; rodapé "N categorias sem nada para limpar".

### T4 · Revisão (por categoria)
- Tabela: caixa de seleção, nome amigável, caminho (cinza, truncado), tamanho, última modificação, situação (Em uso, Pronto).
- Itens em uso aparecem desmarcados e desabilitados com o motivo ("Em uso por: Claude").
- 🟢 marcados por padrão; 🟡 desmarcados por padrão.
- Rodapé: "Selecionados: 7 itens · 12,4 GB" + **Limpar selecionados**.
- Ações por linha: Mostrar no Finder.

### T5 · Confirmação
- Folha modal: "Mover 7 itens (12,4 GB) para a Lixeira?" e, quando houver ação por comando, segunda linha "2 caches serão limpos pela própria ferramenta e se regeneram sozinhos". Botões **Cancelar** e **Limpar**. Para a Lixeira do sistema: "Esvaziar a Lixeira? Isso não pode ser desfeito."

### T6 · Progresso
- Lista dos itens com estado (aguardando, limpando, ✓, pulado com motivo, erro). Botão **Parar** (termina o item atual e para).

### T7 · Resultado
- Manchete "Limpeza concluída". Linha grande "15 GB → 28 GB livres".
- Registro por categoria com tamanho e ✓ (ou motivo de pulo). Botões **Desfazer** (some se nada foi para a Lixeira), **Ver registro completo** (→ Histórico), **OK**.

### T8 · Maiores arquivos
- Seletor de pasta (padrão: pasta pessoal) + campo "Maior que [500] MB" + **Procurar**.
- Lista dos 20 maiores: nome, caminho, tamanho, última abertura. Ações: Mostrar no Finder, Mover para a Lixeira (com confirmação).

### T9 · Memória
- Topo: pressão atual e nível, memória usada de total.
- Lista dos 15 processos do usuário que mais consomem: nome, memória, botão **Encerrar** (confirmação: "Encerrar Chrome? Trabalho não salvo pode ser perdido."). Atualiza a cada 5 s enquanto a tela está aberta.

### T10 · Histórico
- Lista de limpezas: data, total liberado, número de itens. Detalhe com itens e botão **Desfazer** para os que ainda estão na Lixeira (verifica se o arquivo ainda existe lá).

### T11 · Ajustes
- Avisar quando o espaço livre ficar abaixo de [15] GB.
- Avisar quando a memória ficar alta (liga/desliga).
- Pastas de projetos: lista editável (padrão: as que existirem entre `~/Projetos`, `~/Projects`, `~/dev`, `~/Developer`, `~/code`).
- Projeto parado após [30] dias sem alteração.
- Abrir o Spare ao iniciar sessão (liga/desliga).

## Fluxos principais

1. **Disco quase cheio:** notificação "Restam 9 GB no seu Mac" → clique abre Visão geral → Analisar tudo → Limpar o que é seguro → Confirmação → Progresso → Resultado com antes e depois.
2. **Revisar com calma:** Painel → Liberar → cartões → Revisar (categoria) → desmarcar itens → Limpar selecionados → Confirmação → Progresso → Resultado.
3. **Arrependimento:** Resultado → Desfazer, ou Histórico → limpeza → Desfazer → itens voltam para o lugar original (se o destino já existir, o item fica na Lixeira e a tela avisa).
4. **Memória pesada:** notificação ou cartão Memória → Ver → Encerrar processo → confirmação.

## Textos e idiomas

Todos os textos via `Localizable.strings` em `pt-BR` e `en`. Tamanhos com `ByteCountFormatter` (estilo arquivo) no idioma do sistema. Termos fixos: "Seguro", "Revisar", "Em uso", "Lixeira", "Desfazer" (en: Safe, Review, In use, Trash, Undo).
