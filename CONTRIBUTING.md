# Contributing to Spare

## Run the gates

```
swift build
scripts/check.sh
```

Use `scripts/check.sh` to run the tests: with only Command Line Tools, a plain `swift test` can fail with "plugin for module 'TestingMacros' not found", and the script passes the plugin path for you.

`scripts/check.sh` is the official gate (build, tests, localized strings, app bundle). Every PR must pass it locally; paste the real output in the PR body.

## Branch and PR rite

One slice, one branch, one PR:

1. Open an issue.
2. Branch `feat/<slice>` from an up-to-date `main`.
3. Write the failing test first (TDD), then the code.
4. Run `scripts/check.sh` until green.
5. Independent review.
6. Semantic commit in English, push, open a PR with the evidence and `Closes #<issue>`.
7. Squash merge, delete the branch.

Each PR also updates `docs/planta/STATUS.md` and the `## [Unreleased]` section of `CHANGELOG.md`.

## Commits

Conventional Commits in English, imperative, subject up to 50 characters, no trailing period: `feat(scope): subject`, `fix(scope): subject`.

## Localization

English literals are the localization keys. Every UI literal in `Sources/SpareApp` needs a `pt-BR` translation in `Localization/pt-BR.lproj/Localizable.strings`; `scripts/check-strings.py` enforces it. Interpolate only `String` values inside localized literals (format sizes first), so every placeholder is `%@`; counts of items are the exception: interpolate the `Int` and add the plural forms to `Localizable.stringsdict` (`en` and `pt-BR`, key with `%lld`). Use `Text(verbatim:)` for text that must not be translated (paths, names). Inside a localized literal, keep interpolations simple: at most one level of nested parentheses and no string literals; compute the value into a local `let` first.

## Developer options

Read once at launch, for QA on a throwaway home (never set them for normal use):

- `SPARE_HOME=<folder>` points the app and the CLI at a fake home. Without `SPARE_TRASH_DIR`, the app uses `<folder>/.Trash` as its Trash.
- `SPARE_TRASH_DIR=<folder>` replaces the real Trash with a plain folder.
- `--show <section>` opens the window on a section; `--snapshot <dir>` (needs `SPARE_HOME`) saves the key states as PNG (`scripts/snapshot.sh`).

## Adding a cleanup rule

Add a `Rule` to `RuleCatalog.standard` plus a test with a fake home (`TempHome` and `SpareEnvironment.test(home:)`). Tests never touch the real home folder or the real Trash.

## Other rules

- `SpareCore` must not import SwiftUI or AppKit, and every side effect goes through `SpareEnvironment`.
- No third-party dependencies.
- No em dash or en dash characters anywhere.
