# Task 12: DMG, documentation, final QA and v0.1.0 release

Packages the app as a `.dmg`, completes the README install guide (including the Gatekeeper "Open Anyway" steps for an unnotarized app), runs the final QA on a fake home and then on the real home, and publishes the v0.1.0 GitHub Release.

**Files:**
- Create: `scripts/make-dmg.sh`
- Modify: `scripts/build-app.sh` (universal binary attempt)
- Modify: `README.md`, `CHANGELOG.md`, `docs/planta/STATUS.md`, `docs/planta/05-OPERACAO-E-RELEASE.md` (only if something differs from reality)
- Create: `docs/qa/2026-10-v0.1.0.md` (QA report with evidence)

**Interfaces:**
- Consumes: the complete app and CLI.
- Produces: `dist/Spare-0.1.0.dmg`, `dist/Spare-0.1.0.dmg.sha256`, tag `v0.1.0`, GitHub Release with both files.

- [ ] **Step 1: Universal build attempt**

In `scripts/build-app.sh`, replace the single build with:

```bash
swift build -c release --product SpareApp --arch arm64
ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/SpareApp"
if swift build -c release --product SpareApp --arch x86_64 2>/dev/null; then
    X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/SpareApp"
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/Spare"
    echo "Built universal binary (arm64 + x86_64)"
else
    cp "$ARM_BIN" "$APP/Contents/MacOS/Spare"
    echo "WARNING: x86_64 build unavailable with this toolchain, shipping arm64 only"
fi
```

(Create the bundle folders before this block.) Record which path was taken in the QA report and in the release notes ("Apple Silicon only" if arm64 only).

- [ ] **Step 2: DMG script**

`scripts/make-dmg.sh` (make executable):

```bash
#!/usr/bin/env bash
# Builds dist/Spare-<version>.dmg with the app and an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
scripts/build-app.sh

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R dist/Spare.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="dist/Spare-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Spare $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "$DMG"
```

Run: `scripts/make-dmg.sh` → produces both files. Verify: `hdiutil attach dist/Spare-0.1.0.dmg -nobrowse`, check `Spare.app` and `Applications` exist, `codesign --verify --strict` on the mounted app, then `hdiutil detach`.

- [ ] **Step 3: README install guide**

Add `## Install` (and `## Instalação` in the Portuguese half):
1. Download `Spare-0.1.0.dmg` from the Releases page; optionally verify with `shasum -a 256`.
2. Open it, drag Spare to Applications.
3. First launch: macOS blocks apps from developers without a paid Apple certificate. Open Spare once, then go to System Settings › Privacy & Security, scroll to "Spare was blocked", click "Open Anyway", confirm. Only needed once.
4. Spare lives in the menu bar (no Dock icon). Quit from the panel.
5. CLI: `swift build -c release --product spare` and copy `.build/release/spare` to a folder in PATH (Homebrew tap is planned for later).
6. Why no notarization yet: it costs USD 99 per year; planned once the project has users.
7. Screenshots: the panel, Overview after a scan, Cleanup cards, Result screen (from the QA run, saved under `docs/img/`).

- [ ] **Step 4: Final QA on a fake home**

Run `scripts/check.sh` and `scripts/qa-fake-home.sh` → both green. Then the app against a fake home (`SPARE_HOME`, `SPARE_TRASH_DIR`) through the whole flow of `docs/planta/03-TELAS-E-FLUXOS.md` flows 1 to 4, screenshots of every screen (T1 to T11) in pt-BR and once in English (`defaults write ai.rafaeljorge.spare AppleLanguages '("en")'`, relaunch, then `defaults delete ai.rafaeljorge.spare AppleLanguages`).

- [ ] **Step 5: Final QA on the real home (read-only first)**

1. `spare scan` and the app's "Analyze everything" on the real home: record total time (success criterion: under 60 s) and the safe reclaimable total (criterion: at least 20 GB on the author's Mac, or explain the difference, for example if caches were already cleaned on 2026-10-22).
2. Real cleanup limited to clearly regenerable categories the author approves in the session: `Developer caches` and `Idle project leftovers`. Record free space before and after.
3. Confirm nothing outside the catalog changed: `Documents`, `Desktop`, `.ssh` modification times unchanged (`stat -f %m`).

- [ ] **Step 6: QA report**

`docs/qa/2026-10-v0.1.0.md`: environment (macOS version, chip), gate outputs, fake-home flow results with screenshot links, real-home numbers (time, found, freed), known limitations (arm64 only if so, notarization absent, approximate memory numbers, open-at-login result), and the list of follow-ups for v0.2 (items marked 🟡 in the PRD).

- [ ] **Step 7: Release**

```bash
git add -A
git commit -m "chore(release): prepare v0.1.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Vm75dLn7CFX9KJdQqLAxtK"
```

After this task's PR is merged into `main`:

```bash
git checkout main && git pull
git tag -a v0.1.0 -m "Spare v0.1.0"
git push origin v0.1.0
gh release create v0.1.0 dist/Spare-0.1.0.dmg dist/Spare-0.1.0.dmg.sha256 \
  --title "Spare v0.1.0" --notes-file <(sed -n '/## \[0.1.0\]/,/## \[/p' CHANGELOG.md | sed '$d')
```

(Before tagging, move the CHANGELOG `Unreleased` content under `## [0.1.0] - <date>` in this task's PR.) Update STATUS to "v0.1.0 publicada" with the release URL.
