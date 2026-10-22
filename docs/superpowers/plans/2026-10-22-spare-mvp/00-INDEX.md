# Spare MVP (v0.1.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task lives in its own file in this folder; read this index first, then only your task file.

**Goal:** Ship Spare v0.1.0, a free open-source macOS 14+ menu bar app (plus `spare` CLI) that monitors disk and memory and safely frees space taken by developer and AI junk.

**Architecture:** One Swift package. `SpareCore` is a Foundation-only engine (rules catalog, scanner, cleaner, history, monitors) with every side effect injected through `SpareEnvironment`, so all destructive logic is tested against temporary fake home folders. `SpareCLI` and the `SpareApp` SwiftUI menu bar app are thin shells over the engine.

**Tech Stack:** Swift 6 (language mode 6), SwiftPM, Swift Testing, SwiftUI (`MenuBarExtra` + an AppKit-hosted main window), Observation, no third-party dependencies. Builds with Command Line Tools only (verified 2026-10-22, Swift 6.4).

**Spec:** `docs/planta/01-PRD.md`, `02-TRD.md`, `03-TELAS-E-FLUXOS.md`, `04-DADOS-E-PERMISSOES.md`, `05-OPERACAO-E-RELEASE.md`. Read the PRD and TRD before any task; read 03 before UI tasks.

## Global Constraints

- Minimum OS: macOS 14.0 (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` 14.0).
- `// swift-tools-version:6.0`; Swift language mode 6 with strict concurrency; zero warnings policy is not enforced, but zero errors is.
- No third-party dependencies.
- Bundle identifier: `ai.rafaeljorge.spare`. App name: `Spare`. CLI name: `spare`. License: MIT.
- `SpareCore` must not import SwiftUI or AppKit.
- Every file system side effect in `SpareCore` goes through `SpareEnvironment` (home, trash, command runner, processes, disk space, clock). Tests never touch the real home folder or the real Trash: always use `TempHome` and `SpareEnvironment.test(home:)` from `SpareTestSupport`.
- UI strings: English literals are the localization keys; every UI literal must have a `pt-BR` translation in `Localization/pt-BR.lproj/Localizable.strings`. `scripts/check-strings.py` enforces this. Interpolate only `String` values inside localized literals (format numbers and sizes to `String` first), so every placeholder is `%@`. Use `Text(verbatim:)` or `Text(someString)` for non-translatable text (paths, names). Inside a localized literal, an interpolation may contain at most one level of nested parentheses and no string literals (no `?? ""`, no closures): compute such values into a local `let` or property first, so the check script can derive the key.
- No em dash or en dash characters anywhere (code, docs, UI copy, commits).
- Commits: Conventional Commits in English, imperative, subject at most 50 characters, no trailing period, ending with the two attribution lines:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK`.
- One task = one branch (`feat/tNN-<slug>`) = one PR (`Closes #<issue>`), squash merged after `scripts/check.sh` is green and the independent review approves.
- Each task updates `docs/planta/STATUS.md` (current step) and the `## [Unreleased]` section of `CHANGELOG.md`.
- Sizes shown to users use `ByteFormat.string(_:)` (decimal units, `ByteCountFormatter` `.file` style).

## Review Focus

1. A cache folder containing a symlink to another disk or outside the home folder: sizes must not follow it and cleaning must never touch the target. Pinned in Task 2 (`SizeCalculator` and `SafetyGuard` symlink tests) and Task 5 (`Cleaner` refuses forged and symlinked items).
2. An item disappears between scan and clean (a tool cleaned it, user deleted it): must be reported as skipped `notFound`, never as a failure or crash. Pinned in Task 5.
3. Undo after the tool already recreated the original folder (for example `npm` recreated `_cacache`): the item must stay in the Trash and be reported, never overwrite. Pinned in Task 6.
4. Corrupt or hand-edited `history.json`, `settings.json`, or `last-scan.json`: the app and CLI must start with defaults and keep the bad file renamed. Pinned in Task 6 (history) and Task 9 (settings, last scan).
5. Hard-linked files (pnpm store, uv cache): counted once per item so the promised "you can free X GB" is not inflated. Pinned in Task 2.

## File Map

```
Package.swift
VERSION                                  # 0.1.0
Packaging/Info.plist                     # template, __VERSION__ placeholder
Localization/en.lproj/Localizable.strings
Localization/pt-BR.lproj/Localizable.strings
scripts/check.sh  build-app.sh  make-dmg.sh  check-strings.py  qa-fake-home.sh
.github/workflows/ci.yml
Sources/SpareCore/
  Support/SpareEnvironment.swift  ByteFormat.swift
  Disk/DiskMonitor.swift
  Rules/Rule.swift  RuleCatalog.swift  SafetyGuard.swift
  Scan/SizeCalculator.swift  Scanner.swift  ScanReport.swift  ProjectScanner.swift  LargeFileFinder.swift
  Processes/RunningProcess.swift  ProcessLister.swift  InUseGuard.swift  ProcessTerminator.swift
  Clean/TrashService.swift  CommandRunner.swift  Cleaner.swift  CleanupRecord.swift  LargeFileCleaner.swift
  History/HistoryStore.swift  JSONFileStore.swift
  Memory/MemoryMonitor.swift
  Settings/SpareSettings.swift  SettingsStore.swift  ScanReportStore.swift
  Insights/Recommendation.swift  AlertPolicy.swift
Sources/SpareCLI/SpareCLI.swift  (+ Commands/*.swift)
Sources/spare/main.swift
Sources/SpareApp/  SpareApp.swift  AppModel*.swift  MainWindowController.swift  Views/*.swift  AlertCenter.swift  LoginItem.swift
Sources/SpareTestSupport/TempHome.swift  Fakes.swift  OutputCapture.swift
Tests/SpareCoreTests/*.swift
Tests/SpareCLITests/*.swift
```

## Tasks

| # | File | Deliverable |
|---|---|---|
| 1 | `T01-walking-skeleton.md` | Package, disk monitor, `spare status`, menu bar app showing free GB, gates, CI, repo docs |
| 2 | `T02-catalog-and-scanner.md` | Rule catalog, safety guard, size calculator, scanner, `spare scan` |
| 3 | `T03-project-leftovers.md` | Idle project artifacts (`node_modules`, `.venv`, `.next`, `target`) in scans |
| 4 | `T04-in-use-detection.md` | Process listing and in-use detection wired into scans |
| 5 | `T05-cleaner.md` | Cleaner (delete, trash, command, empty Trash) with all guards |
| 6 | `T06-history-and-undo.md` | History, undo, purge; `spare clean`, `undo`, `purge`, `history` |
| 7 | `T07-large-files.md` | Large file finder and trash; `spare large` |
| 8 | `T08-memory.md` | Memory snapshot, top consumers, terminator; `spare memory` |
| 9 | `T09-app-shell-and-analyze.md` | Settings, recommendation, app model, menu panel, main window, Analyze everything |
| 10 | `T10-app-cleanup-flow.md` | Cards, review, confirm, progress, result, undo, history screen |
| 11 | `T11-app-files-memory-settings-alerts.md` | Large files, memory, settings screens; notifications; login item |
| 12 | `T12-release-and-qa.md` | DMG, README install guide, QA on fake and real home, v0.1.0 release |

Tasks are sequential: each depends on the merged result of the previous one.
