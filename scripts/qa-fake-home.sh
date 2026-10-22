#!/usr/bin/env bash
# End to end QA of the CLI on a throwaway home. Never touches the real home or the real Trash:
# SPARE_HOME points at the fake home and SPARE_TRASH_DIR at a folder inside it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product spare > /dev/null
SPARE="$PWD/.build/debug/spare"

FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/spare-qa.XXXXXX")"
trap 'rm -rf "$FAKE_HOME"' EXIT
export SPARE_HOME="$FAKE_HOME"
export SPARE_TRASH_DIR="$FAKE_HOME/.Trash"
mkdir -p "$SPARE_TRASH_DIR"

mkdir -p "$FAKE_HOME/.npm/_cacache" "$FAKE_HOME/Library/Caches/com.example.app" \
    "$FAKE_HOME/Downloads" "$FAKE_HOME/Documents" \
    "$FAKE_HOME/Projetos/old/node_modules/dep" "$FAKE_HOME/Library/Logs/Example"
head -c 200000 /dev/zero > "$FAKE_HOME/.npm/_cacache/blob"
head -c 200000 /dev/zero > "$FAKE_HOME/Library/Caches/com.example.app/data"
head -c 200000 /dev/zero > "$FAKE_HOME/Downloads/old.dmg"
head -c 200000 /dev/zero > "$FAKE_HOME/Projetos/old/node_modules/dep/index.js"
head -c 1000 /dev/zero > "$FAKE_HOME/Library/Logs/Example/a.log"
echo '{}' > "$FAKE_HOME/Projetos/old/package.json"
echo keep > "$FAKE_HOME/Documents/keep.txt"
# Old enough for the installer (30 days) and the project (idle 30 days) rules.
touch -t "$(date -v-60d +%Y%m%d%H%M)" "$FAKE_HOME/Downloads/old.dmg" "$FAKE_HOME/Projetos/old/package.json" \
    "$FAKE_HOME/Projetos/old/node_modules/dep/index.js" "$FAKE_HOME/Projetos/old/node_modules/dep" \
    "$FAKE_HOME/Projetos/old/node_modules" "$FAKE_HOME/Projetos/old"

echo "==> scan"
"$SPARE" scan

echo "==> clean without --yes and with --dry-run changes nothing"
"$SPARE" clean --rule apps.caches --rule downloads.installers --rule project.nodeModules
"$SPARE" clean --rule apps.caches --yes --dry-run
test -e "$FAKE_HOME/Library/Caches/com.example.app/data"
test -e "$FAKE_HOME/Downloads/old.dmg"
test -e "$FAKE_HOME/Projetos/old/node_modules/dep/index.js"

echo "==> clean --yes"
"$SPARE" clean --rule apps.caches --rule downloads.installers --rule project.nodeModules --yes
test ! -e "$FAKE_HOME/Library/Caches/com.example.app"
test ! -e "$FAKE_HOME/Projetos/old/node_modules"
test ! -e "$FAKE_HOME/Downloads/old.dmg"
test -n "$(ls "$SPARE_TRASH_DIR")"
test -e "$FAKE_HOME/Documents/keep.txt"
test -e "$FAKE_HOME/.npm/_cacache/blob"

echo "==> undo"
"$SPARE" undo
test -e "$FAKE_HOME/Downloads/old.dmg"
test -z "$(ls "$SPARE_TRASH_DIR")"

echo "==> clean again, then purge only Spare's items"
"$SPARE" clean --rule downloads.installers --yes
echo "someone else's file" > "$SPARE_TRASH_DIR/users-own-file.txt"
"$SPARE" purge
test -n "$(ls "$SPARE_TRASH_DIR")"
"$SPARE" purge --yes
test "$(ls "$SPARE_TRASH_DIR")" = "users-own-file.txt"
test -e "$FAKE_HOME/Documents/keep.txt"

echo "==> history"
"$SPARE" history
test "$(stat -f %Lp "$FAKE_HOME/Library/Application Support/Spare")" = "700"

echo "QA OK"
