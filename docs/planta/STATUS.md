# STATUS: Spare

**Etapa atual:** 5 · QA final e release v0.1.0 (Task 12 em andamento)

| Etapa | Situação |
|---|---|
| 1 · Discovery e entrevista | 🟢 concluída em 2026-10-22 |
| 2 · Telas e fluxos | 🟢 definidos em texto (`03-TELAS-E-FLUXOS.md`); estética fica para depois, por decisão do Rafael |
| 3 · Planta + plano | 🟢 documentos escritos; plano em `docs/superpowers/plans/` |
| 4 · Construção por fatias | 🟢 Tasks 1 a 11 mergeadas. Histórico: Task 3 (sobras de projetos ociosos) concluída (revisão aplicada: ociosidade medida na raiz do repositório e datas de criação contam); Task 4 (detecção de itens em uso, inclusive pacotes npx por argumentos e cwd) concluída; Task 5 (limpeza protegida: guardas refeitas item a item, uma listagem de processos por execução, ociosidade do projeto remedida na raiz do repositório) concluída; Task 6 (histórico, desfazer, liberar agora e comandos `clean`/`undo`/`purge`/`history`; desfazer e liberar só agem no item exato que o Spare mandou para a Lixeira) concluída; Task 7 (maiores arquivos: busca somente leitura com fts, sem seguir links nem sair do volume, pula pacotes e ~/Library por padrão, N maiores, envio à Lixeira com histórico e Desfazer) concluída; Task 8 (memória: `spare memory`, `status` com memória; `ProcessTerminator` no core, por pid, sem comando de CLI; números aproximados) concluída; Task 9 (casca do app: item e painel da barra de menus, janela 1000 x 660 só escura, Visão geral com Analisar tudo e Parar reais, descoberta de projetos cancelável, configurações e recomendação no core, `--snapshot` e `scripts/snapshot.sh`) concluída; Task 10 (fluxo de limpeza no app: cartões com selo Seguro/Revisar, revisão por categoria, confirmação que separa "apagado de vez" e "vai para a Lixeira", progresso com Parar, resultado com Desfazer e Liberar agora, tela Histórico; o Cleaner roda fora da main actor e nada roda sem confirmação) concluída; Task 11 (telas Maiores arquivos, Memória e Ajustes, alertas de disco e memória pelo UserNotifications com cooldown persistido, Abrir ao iniciar sessão; encerrar app com bundle é gracioso, SIGTERM só sem bundle; PID reciclado nunca recebe sinal; confirmação lista PIDs e comandos com segredos mascarados; um único `ps` a cada 15 s para painel e tela) concluída; próximo: Task 12 |
| 5 · QA final e release v0.1.0 | 🟡 ícone do app, `scripts/build-dmg.sh` (dmg e sha256), QA na pasta falsa com prints em `docs/img/`, README com guia de instalação, relatório em `docs/qa/` e ficha em `docs/releases/` prontos; faltam a rodada no Mac real (`PENDING_REAL_RUN`), a tag e a Release |

**Pendência v0.2:** gravar o histórico item a item durante a limpeza (hoje o registro é salvo no fim; sair pelo app espera o item atual e salva, mas crash ou kill ainda perdem o desfazer dos itens já movidos para a Lixeira).

**Próximo passo:** rodada no Mac real (só categorias `safe` que se regeneram), depois merge, tag `v0.1.0` e GitHub Release.
