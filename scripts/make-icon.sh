#!/usr/bin/env bash
# Generates Packaging/AppIcon.icns (the Spare ring on the night gradient) with CoreGraphics and iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."

SET=$(mktemp -d)/AppIcon.iconset
trap 'rm -rf "$(dirname "$SET")"' EXIT
mkdir -p "$SET"
swiftc -O scripts/make-icon.swift -o "$(dirname "$SET")/make-icon"
for size in 16 32 128 256 512; do
    "$(dirname "$SET")/make-icon" "$size" "$SET/icon_${size}x${size}.png"
    "$(dirname "$SET")/make-icon" "$((size * 2))" "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o Packaging/AppIcon.icns
echo "Packaging/AppIcon.icns"
