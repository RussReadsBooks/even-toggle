#!/usr/bin/env bash
#
# make-dmg.sh — wraps build/EvenToggle.app into a shareable DMG.
# Run build-app.sh first. Usage:  ./scripts/make-dmg.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="EvenToggle"
[ -d "build/${APP}.app" ] || { echo "Run ./scripts/build-app.sh first."; exit 1; }

# Stage a folder containing the app + a shortcut to /Applications, so the DMG
# shows the familiar "drag me into Applications" layout.
STAGE="build/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "build/${APP}.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "build/${APP}.dmg"
rm -rf "$STAGE"
echo "✅ build/${APP}.dmg  (attach this to a GitHub Release)"
