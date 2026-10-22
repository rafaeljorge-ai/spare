#!/usr/bin/env bash
# Official local gate. Every PR must pass this.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build"
swift build
echo "==> swift test"
# SwiftPM with Command Line Tools only intermittently omits the Swift Testing macro
# plugin path ("plugin for module 'TestingMacros' not found"), so pass it explicitly.
TEST_FLAGS=()
PLUGINS="$(dirname "$(xcrun -f swift)")/../lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
    TEST_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi
swift test ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"}
echo "==> localized strings"
python3 scripts/check-strings.py
echo "==> app bundle"
scripts/build-app.sh > /dev/null
echo "OK: all gates passed"
