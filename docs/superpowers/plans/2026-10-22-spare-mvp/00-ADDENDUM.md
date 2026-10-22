# Addendum (2026-10-22, after Tasks 1 to 3): overrides for Tasks 4 to 12

This file wins over any task file when they disagree. Approved by the owner together with
`docs/superpowers/specs/2026-10-22-spare-finish-design.md`. Execution runs to the end without new questions.

## A. Global rules (all remaining tasks)
- [ ] Tests run only through `scripts/check.sh` (plain `swift test` misses the Swift Testing plugin with Command Line Tools).
- [ ] No `@Observable`, `@State`, `@Entry` or `#Preview` macros (the `SwiftUIMacros` plugin is missing from Command Line Tools). Use `ObservableObject` + `@Published`, `@StateObject` / `@ObservedObject`, and small `ObservableObject` view models for local view state. Precedent: `Sources/SpareApp/SpareApp.swift`.
- [ ] CLI failures go to `writeError` (stderr), never stdout.
- [ ] Every PR updates `CHANGELOG.md` `[Unreleased]` and `docs/planta/STATUS.md`. Public docs in English (README keeps its pt-BR section), planning docs in pt-BR. No em or en dashes anywhere.
- [ ] Product principles (PRD): safe and visibly safe, polished, light (target under 60 MB RAM idle), intuitive.

## B. Safety carry-overs
- [ ] Task 4: in-use detection feeds `ScanItem.inUseBy`; items in use are never selectable.
- [ ] Task 5: Scanner and SafetyGuard share one `RuleCatalog` and one clock (`environment.now`). The Cleaner calls `SafetyGuard.violation` right before acting on each item, and for project artifacts rechecks `ProjectScanner.isIdle` at the repository root; a changed item is skipped with a reason.
- [ ] Task 5: consider refusing files inside `Library/Mail`, `Library/Messages`, `Library/Mobile Documents` in `canTrashUserFile` (Large Files trash path).
- [ ] Task 9: project discovery honors cancellation (Stop) and reports progress.

## C. Visual direction (Tasks 9 to 11)
- [ ] The approved prototype (`Prototype/`, design system in `.interface-design/system.md`) is the visual source of truth. Code blocks in task files that use plain system styling are replaced by the prototype's components and tokens: move `Ink`, `Txt`, `Backdrop`, `PrimaryButton`, `QuietButton`, `Tile`, `Badge`, `Card`, `Checkbox`, `SpareRing`, `ScanButton`, sidebar and header into `Sources/SpareApp/Design/`, wired to real data.
- [ ] Dark only (`.preferredColorScheme(.dark)` on every window and the panel). Main window 1000 x 660, hidden title bar.
- [ ] Menu bar: mini Spare ring icon plus free GB ("15 GB"); below the alert threshold the icon becomes a warning triangle.
- [ ] Dock icon only while the main window is open (activation policy `.regular` when shown, `.accessory` when closed).
- [ ] App icon: the Spare ring on the night gradient, generated at build time into `Packaging/AppIcon.icns`.
- [ ] Every state in `03-TELAS-E-FLUXOS.md` exists (loading, empty, error, in use, partial scan).

## D. Visual verification (replaces `screencapture`)
- [ ] The terminal has no Screen Recording permission. Port the prototype's in-process snapshot to the app: launch argument `--snapshot <dir>` (with `SPARE_HOME` pointing at a fake home) walks the key states and saves the window as PNG, then quits. Each UI task attaches those PNGs to its PR after the coordinator inspects them.
- [ ] `agent-browser` is used only for web pages (the GitHub release page in Task 12).

## E. Task 12 (QA and release)
- [ ] Fake-home QA of flows 1 to 4, pt-BR and English, screenshots in `docs/img/`.
- [ ] Real Mac run, authorized by the owner: clean only categories that regenerate on their own (`safe` rules in developer caches, app caches, logs). Never project leftovers, AI models, installers or the Trash. Record free space before and after, time and items in `docs/qa/2026-10-v0.1.0.md`.
- [ ] Publish v0.1.0 as a normal (not pre-release) GitHub Release with the `.dmg`, its SHA-256 and notes explaining "Open Anyway" for an unsigned app. Release record in `docs/releases/`. Check the public release page with `agent-browser`.
- [ ] Out of scope for v0.1.0: Homebrew tap, notarization, light theme.
