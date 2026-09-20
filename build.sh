#!/bin/bash
# Builds Rocky.app. No Xcode project, no dependencies.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Rocky.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Host architecture: whoever builds it gets a native binary. Distributing a
# prebuilt app instead would need both slices and a `lipo` pass.
swiftc -O -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/Rocky" Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/spritesheet.png Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

"$APP/Contents/MacOS/Rocky" --selftest
echo "Built $APP"
