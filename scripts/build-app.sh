#!/usr/bin/env bash
# Builds dist/Spare.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
APP=dist/Spare.app

swift build -c release --product SpareApp
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SpareApp" "$APP/Contents/MacOS/Spare"
sed "s/__VERSION__/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"
cp -R Localization/*.lproj "$APP/Contents/Resources/"
scripts/make-icon.sh > /dev/null
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "$APP"
