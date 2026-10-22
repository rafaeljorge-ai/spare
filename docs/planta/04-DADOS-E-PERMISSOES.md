# 04 · Dados e permissões: Spare

O Spare não tem servidor, banco de dados, conta de usuário nem telemetria. Nenhum dado sai do Mac.

## Arquivos locais

Pasta: `~/Library/Application Support/Spare/` (criada na primeira execução, permissão `0700`).

| Arquivo | Formato | Conteúdo | Retenção |
|---|---|---|---|
| `settings.json` | JSON (`SpareSettings`) | limite do alerta, raízes de projetos, dias de inatividade, alertas ligados | permanente |
| `history.json` | JSON (`[CleanupRecord]`) | data, itens, caminho original, URL na Lixeira, tamanho, ação, resultado | últimas 100 limpezas |
| `last-scan.json` | JSON (`ScanReport`) | resultado da última varredura (alimenta a Recomendação de hoje) | substituído a cada varredura |

Gravação atômica (`Data.write(options: .atomic)`). Arquivo corrompido é renomeado para `*.corrupt-<timestamp>.json` e o app segue com valores padrão, avisando no log.

### `CleanupRecord`

```json
{
  "id": "UUID",
  "startedAt": "2026-10-22T15:00:00Z",
  "freeBytesBefore": 16106127360,
  "freeBytesAfter": 30064771072,
  "entries": [
    {
      "ruleID": "downloads.installers",
      "originalPath": "/Users/x/Downloads/Instalador.dmg",
      "trashPath": "/Users/x/.Trash/Instalador.dmg",
      "action": "trash",
      "sizeBytes": 6764573491,
      "status": "done",
      "skipReason": null
    }
  ]
}
```

`action`: `delete`, `trash`, `command`, `emptyTrash`. `status`: `done`, `skipped`, `failed`, `restored`, `purged`. `skipReason`: `inUse`, `notFound`, `outsideCatalog`, `protected`, `cancelled`, `toolNotFound`.

## Permissões do macOS

| Recurso | Precisa? | Quando | Como lidamos |
|---|---|---|---|
| Acesso Total ao Disco | Não no MVP | Só seria necessário para `~/Library/Containers` e `Mail` | Fora do escopo; nenhuma regra do MVP depende disso |
| Pasta Downloads | Sim (pedido automático do macOS) | Regra "Instaladores esquecidos" | O macOS pede na primeira varredura; se negado, a categoria "Instaladores esquecidos" simplesmente não aparece |
| Notificações | Sim | Alertas de disco e memória | Pedido na primeira execução; se negado, o ícone da barra continua virando alerta |
| Abrir ao iniciar sessão | Opcional | Ajustes | `SMAppService.mainApp` |
| Encerrar processos | Não precisa de permissão especial | Tela Memória | Só processos do usuário atual |
| Privilégio de administrador | Nunca | | O Spare nunca pede senha |

O app não usa sandbox (requisito para limpar caches de outras ferramentas), por isso é distribuído fora da App Store.

## Privacidade e LGPD

- Nenhuma coleta, nenhum envio, nenhuma análise de uso.
- O histórico guarda caminhos de arquivos locais; o usuário pode apagar tudo em Ajustes ("Limpar histórico").
- `SECURITY.md` explica como reportar falhas.

## Matriz de permissões internas (o que cada parte pode fazer)

| Parte | Lê disco | Move para Lixeira | Roda comando | Encerra processo |
|---|---|---|---|---|
| Scanner | ✅ (só caminhos do catálogo e raízes de projeto) | ❌ | ❌ | ❌ |
| LargeFileFinder | ✅ (pasta escolhida) | ❌ | ❌ | ❌ |
| Cleaner | ✅ | ✅ (só itens validados; apaga direto só ações `delete`) | ✅ (só comandos do catálogo) | ❌ |
| ProcessTerminator | ❌ | ❌ | ❌ | ✅ (só do usuário, nunca protegidos) |
| UI | via motor | via motor, sempre após confirmação | via motor | via motor, sempre após confirmação |
