#!/bin/zsh
# Builds Fantastik.app (Apple silicon, release) into ./build
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Fantastik.app

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/Fantastik

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Fantastik"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Drop your own icon at Resources/AppIcon.icns to override the generated one.
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET"
  "$APP/Contents/MacOS/Fantastik" --render-icon "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP"
echo "Built $APP"
