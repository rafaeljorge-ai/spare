# Spare: finishing v0.1.0 (design)

Date: 2026-10-22. Status: awaiting owner approval ("DE ACORDO"); then execution runs to the end without new questions.

## Goal
Deliver Spare v0.1.0 finished, tested and published: a light, safe, intuitive macOS app that shows free space, finds what AI and coding tools leave behind and frees it, with the approved CleanMyMac-like look.

## Where we are
Tasks 1 to 3 merged (#13, #14, #16): disk status, rule catalog, safety guard, read-only scanner, idle project leftovers. Visual prototype approved and merged (#15).

## Decisions taken today (owner)
| Topic | Decision |
|---|---|
| Visual | Prototype approved: dark gradient, Spare Ring, sidebar with colored tiles. Dark only. |
| Menu bar | Mini ring icon plus free GB; warning icon below the threshold. |
| Real test on the owner's Mac | Allowed, only categories that regenerate on their own (developer caches, app caches, logs). |
| Release | Publish v0.1.0 as a normal public GitHub Release with the `.dmg`, no extra confirmation. |
| Principles | Safe and visibly safe, polished, light, intuitive. Everything recorded in the CHANGELOG. |
| Docs language | Public docs in English (README also in pt-BR); planning docs in pt-BR. |

Defaults taken by the coordinator: Dock icon only while the window is open; app icon drawn from the Spare Ring; no Homebrew tap, notarization or light theme in v0.1.0.

## Remaining work (unchanged scope)
Task 4 in-use detection · 5 cleaner · 6 history, undo, purge, cleaning CLI · 7 large files · 8 memory · 9 app shell and Analyze everything · 10 cleanup flow and history screens · 11 large files, memory, settings, alerts, login item · 12 DMG, docs, QA and release.

Overrides for those tasks: `docs/superpowers/plans/2026-10-22-spare-mvp/00-ADDENDUM.md`.

## How each task is done
Branch from updated `main`, TDD by an implementer subagent, `scripts/check.sh` green, in-app snapshots inspected for UI tasks, independent reviewer, PR with real gate output, squash merge. Engine tasks 7 and 8 are independent of 5 and 6 and may run in parallel (separate worktrees, at most two writers).

## Success criteria
- `scripts/check.sh` green on `main`; every screen in `03-TELAS-E-FLUXOS.md` rendered and inspected.
- Real run frees space on the owner's Mac with zero touches outside safe categories; numbers recorded.
- Public release v0.1.0 page shows the `.dmg` and checksum; install instructions work.

## Risks
- Unsigned app: users must use "Open Anyway"; documented in README and release notes.
- Command Line Tools only: no SwiftUI macros; handled by the ObservableObject rule.
- Memory numbers are approximate without private APIs; labelled as such.
