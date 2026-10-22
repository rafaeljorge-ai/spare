# 05 · Operação e release: Spare

Este projeto é um app de desktop: não há Docker, Coolify nem servidor. A "operação" é build, empacotamento e publicação.

## Requisitos de desenvolvimento

- macOS 14+ e Command Line Tools com Swift 6 (`xcode-select --install`). Xcode é opcional.
- `gh` (GitHub CLI) para PRs e releases.

## Comandos

| Objetivo | Comando |
|---|---|
| Compilar | `swift build` |
| Testar | `swift test` |
| Gate completo local | `scripts/check.sh` |
| Montar o app | `scripts/build-app.sh` → `dist/Spare.app` |
| Gerar o instalador | `scripts/make-dmg.sh` → `dist/Spare-<versão>.dmg` |
| Rodar a CLI | `swift run spare status` |

## `build-app.sh`

1. `swift build -c release --arch arm64 --arch x86_64` (binário universal; se a toolchain não suportar, cai para a arquitetura local e avisa).
2. Monta `dist/Spare.app/Contents/{MacOS,Resources,Info.plist}`; copia `Localizable.strings` e o ícone.
3. `Info.plist`: `CFBundleIdentifier=ai.rafaeljorge.spare`, `LSUIElement=true` (sem ícone no Dock), `LSMinimumSystemVersion=14.0`, versão vinda de `VERSION`.
4. `codesign --force --deep --sign - dist/Spare.app` e `codesign --verify`.

## `make-dmg.sh`

`hdiutil create -volname Spare -srcfolder <staging com Spare.app e atalho para /Applications> -ov -format UDZO dist/Spare-<versão>.dmg`, depois `shasum -a 256` gravado ao lado.

## Versionamento e release

- SemVer no arquivo `VERSION`; tag `vX.Y.Z`; `CHANGELOG.md` no formato Keep a Changelog.
- Release: `gh release create vX.Y.Z dist/Spare-X.Y.Z.dmg dist/Spare-X.Y.Z.dmg.sha256 --notes-file <trecho do CHANGELOG>`.
- O README traz o passo a passo de instalação sem notarização: abrir o `.dmg`, arrastar para Aplicativos, tentar abrir, ir em Ajustes do Sistema › Privacidade e Segurança › Abrir Mesmo Assim.

## CI (GitHub Actions)

`.github/workflows/ci.yml`: em cada `pull_request` roda só o barato (gitleaks e checagem de `.env` versionado, em `ubuntu-latest`, cerca de 1 minuto). O gate completo (`scripts/check.sh` em `macos-latest`) roda apenas em `workflow_dispatch`, manual. Seguindo a política do projeto, o gate oficial é o local: se o Actions estiver indisponível, o merge segue com a evidência do `scripts/check.sh` registrada no PR.

## Rito por fatia

Issue → branch `feat/<fatia>` a partir da `main` atualizada → TDD → `scripts/check.sh` verde → revisão independente → commit semântico em inglês → push → PR com evidência → merge squash → apagar branch. Uma fatia, uma branch, um PR.

## Backup e recuperação

Não há dados de servidor. A proteção do usuário é a própria Lixeira + `history.json` (Desfazer). Teste de recuperação: a suíte de testes cobre "limpar → desfazer → arquivos de volta com o mesmo conteúdo".
