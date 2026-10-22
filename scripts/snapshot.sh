#!/usr/bin/env bash
# Visual snapshots of the app on a throwaway home. The terminal has no Screen Recording permission, so the
# app draws its own windows to PNG (`--snapshot`). Never touches the real home: SPARE_HOME points at a fake
# one, and the app refuses to run `--snapshot` without it.
#
# Usage: scripts/snapshot.sh [output-dir] [language]   (defaults: docs/img, pt-BR; the other one is en)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs/img}"
LANGUAGE="${2:-pt-BR}"
LOCALE="${LANGUAGE//-/_}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

scripts/build-app.sh > /dev/null
APP="$PWD/dist/Spare.app/Contents/MacOS/Spare"

FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/spare-snapshot.XXXXXX")"
# The fake Trash sits next to the fake home (never the real Trash).
trap 'rm -rf "$FAKE_HOME" "$FAKE_HOME-trash"' EXIT

# One real 256 MB file, then APFS clones: the scan sees gigabytes, the disk pays for 256 MB.
BASE="$FAKE_HOME/.base-blob"
dd if=/dev/zero of="$BASE" bs=1048576 count=256 2> /dev/null
fill() { # fill <folder> <number of 256 MB clones>
    mkdir -p "$FAKE_HOME/$1"
    for i in $(seq 1 "$2"); do cp -c "$BASE" "$FAKE_HOME/$1/blob$i"; done
}
project() { # project <name> <clones>
    echo '{}' > "$FAKE_HOME/Projetos/$1/package.json"
    fill "Projetos/$1/node_modules/lib" "$2"
}
mkdir -p "$FAKE_HOME/Projetos/agentia-wa" "$FAKE_HOME/Projetos/mavikos-ads" "$FAKE_HOME/Projetos/imobai" \
    "$FAKE_HOME/Projetos/estetiqo"
project agentia-wa 6
project mavikos-ads 5
project imobai 5
project estetiqo 4
fill ".npm/_cacache" 3
fill "Library/pnpm/store" 4
fill ".cache/pre-commit" 2
fill "Library/Caches/com.spotify.client" 4
fill "Library/Caches/com.example.editor" 2
fill "Library/Logs/Example" 1
fill ".cache/huggingface" 6
fill ".cache/whisper" 3
fill ".npm/_npx/eb65ac700b3c4dc9" 1
fill ".npm/_npx/c943b712072b77c4" 2
fill "Downloads" 0
cp -c "$BASE" "$FAKE_HOME/Downloads/Docker.dmg"
cp -c "$BASE" "$FAKE_HOME/Downloads/Cursor-arm64.dmg"

# Big personal files for the Large Files screen: one 1100 MB real file, then clones cut to size (a clone
# shrunk with truncate only keeps the blocks it still uses, so the disk pays for the 1100 MB once).
BIG="$FAKE_HOME/.base-big"
dd if=/dev/zero of="$BIG" bs=1048576 count=1100 2> /dev/null
bigfile() { # bigfile <path> <size in MB> <last opened, touch -t format>
    mkdir -p "$(dirname "$FAKE_HOME/$1")"
    cp -c "$BIG" "$FAKE_HOME/$1"
    truncate -s "${2}m" "$FAKE_HOME/$1"
    touch -t "$3" "$FAKE_HOME/$1"
}
bigfile "Movies/Gravação de tela 2026-08-14.mov" 1100 202608141030
bigfile "Movies/Casamento (bruto).mp4" 980 202504021900
bigfile "Documents/Máquinas/ubuntu-24.04.iso" 870 202411100800
bigfile "Downloads/dataset-treino.zip" 760 202606201500
bigfile "Pictures/Exportação RAW.tar" 690 202509051200
bigfile "Documents/Backup 2025.zip" 610 202501151000
bigfile "Music/Sessão ao vivo.wav" 540 202602281800
rm "$BASE" "$BIG"

# Old enough for the installer (30 days) and idle project (30 days) rules.
find "$FAKE_HOME/Projetos" "$FAKE_HOME/Downloads" -exec touch -t "$(date -v-60d +%Y%m%d%H%M)" {} +

echo "==> snapshot to $OUT"
SPARE_HOME="$FAKE_HOME" "$APP" -AppleLanguages "($LANGUAGE)" -AppleLocale "$LOCALE" --snapshot "$OUT" &
APP_PID=$!
for _ in $(seq 1 90); do
    kill -0 "$APP_PID" 2> /dev/null || break
    sleep 1
done
if kill -0 "$APP_PID" 2> /dev/null; then
    kill "$APP_PID"
    echo "snapshot timed out" >&2
    exit 1
fi

# Retina captures are huge: keep them at most 1200 px wide.
sips -Z 1200 "$OUT"/*.png > /dev/null

status=0
for name in 1-panel 2-overview-idle 3-overview-scanning 4-overview-done 5-cleanup-cards 6-cleanup-review \
    7-cleanup-confirm 8-cleanup-progress 9-cleanup-result 10-history \
    t11-large-files-result t11-large-files-confirm t11-memory t11-memory-confirm t11-settings; do
    file="$OUT/$name.png"
    # A blank window renders as a tiny PNG; real screens are well above this.
    if [ ! -f "$file" ] || [ "$(stat -f %z "$file")" -lt 10000 ]; then
        echo "missing or blank: $file" >&2
        status=1
    else
        echo "$file"
    fi
done
exit $status
