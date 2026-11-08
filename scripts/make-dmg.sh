#!/bin/zsh
# Builds Fantastik.app and packages it into build/Fantastik-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="build/Fantastik-$VERSION.dmg"
STAGE=build/dmg-stage

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Fantastik.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Fantastik" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Created $DMG"
