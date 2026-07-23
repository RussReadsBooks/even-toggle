#!/usr/bin/env bash
#
# build-app.sh — compiles EvenToggle and wraps it into a double-clickable
# EvenToggle.app that you can drag into /Applications.
#
# Requirements: Xcode (or Xcode Command Line Tools) installed, so `swift` exists.
# Usage:  ./scripts/build-app.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."     # run from the repo root

APP="EvenToggle"
BUNDLE_ID="com.thomasz.eventoggle"  
RELEASE=".build/release"
OUT="build/${APP}.app"

echo "▶ Compiling (release)…"
swift build -c release

echo "▶ Assembling ${APP}.app…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$RELEASE/$APP" "$OUT/Contents/MacOS/$APP"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP}</string>
  <key>CFBundleDisplayName</key><string>${APP}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Optional custom icon: drop a 1024×1024 PNG at build/icon.png before building.
if [ -f "build/icon.png" ]; then
  echo "▶ Building app icon…"
  ICONSET="build/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 64 128 256 512 1024; do
    sips -z $s $s build/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$OUT/Contents/Info.plist" || true
fi

echo "▶ Ad-hoc code signing (lets it run on this Mac)…"
codesign --force --deep --sign - "$OUT"

echo "✅ Built: $OUT"
echo "   Next: drag ${APP}.app into /Applications and open it."
