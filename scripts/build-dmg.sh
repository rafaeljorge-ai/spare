#!/usr/bin/env bash
# Builds dist/Spare-<version>.dmg (the app and an Applications shortcut) and its .sha256.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
scripts/build-app.sh > /dev/null

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R dist/Spare.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="dist/Spare-$VERSION.dmg"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "Spare $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" > /dev/null
# The checksum file names the .dmg without its folder, so `shasum -c` works next to the download.
(cd dist && shasum -a 256 "Spare-$VERSION.dmg" | tee "Spare-$VERSION.dmg.sha256")
echo "$DMG"
