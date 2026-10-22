#!/usr/bin/env bash
# Visual snapshots of the app on a throwaway home. The terminal has no Screen Recording permission, so the
# app draws its own windows to PNG (`--snapshot`). Never touches the real home: SPARE_HOME points at a fake
# one, and the app refuses to run `--snapshot` without it.
#
# Usage: scripts/snapshot.sh [output-dir]   (default: docs/img)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs/img}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

scripts/build-app.sh > /dev/null
APP="$PWD/dist/Spare.app/Contents/MacOS/Spare"

FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/spare-snapshot.XXXXXX")"
trap 'rm -rf "$FAKE_HOME"' EXIT

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
rm "$BASE"

# Old enough for the installer (30 days) and idle project (30 days) rules.
find "$FAKE_HOME/Projetos" "$FAKE_HOME/Downloads" -exec touch -t "$(date -v-60d +%Y%m%d%H%M)" {} +

echo "==> snapshot to $OUT"
SPARE_HOME="$FAKE_HOME" "$APP" -AppleLanguages "(pt-BR)" -AppleLocale pt_BR --snapshot "$OUT" &
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
for name in 1-panel 2-overview-idle 3-overview-scanning 4-overview-done; do
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
