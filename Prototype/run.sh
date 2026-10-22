#!/usr/bin/env bash
# Builds the visual prototype as an app bundle and opens it.
# Usage: Prototype/run.sh            open the prototype
#        Prototype/run.sh --snapshot <dir>   save screenshots of each state and quit
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=$(swift build -c release --show-bin-path)/SpareProto
APP=.build/SpareProto.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SpareProto"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SpareProto</string>
    <key>CFBundleIdentifier</key><string>io.github.rafaeljorge-ai.spare.prototype</string>
    <key>CFBundleName</key><string>Spare (protótipo)</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1

if [ "${1:-}" = "--snapshot" ]; then
    "$APP/Contents/MacOS/SpareProto" --snapshot "$2"
else
    open "$APP"
fi
